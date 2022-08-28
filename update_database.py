import fastf1 as ff
import pandas as pd
from sqlalchemy.exc import OperationalError
import datetime
import os
import time
import sql_connection


pd.options.mode.chained_assignment = None


def data_logging(pyodbc_connection, message):
    host_name = os.popen("hostname").read()
    cursor = pyodbc_connection["cursor"]
    cursor.execute("EXEC dbo.Logging_Data @HostName=?, @Message=?", host_name, message)
    cursor.commit()
    print("data_logging: " + message)


def refresh_schedule(pyodbc_connection, sqlalchemy_engine, reload_history=False):
    # Refreshes future event data only - rounds with existing data are not touched
    data_logging(pyodbc_connection, "Starting schedule refresh")
    current_year = datetime.datetime.now().year
    years = list(range(2018, current_year + 1))

    schedules_to_concat = []
    for year in years:
        schedules_to_concat.append(ff.get_event_schedule(year))

    schedule = pd.concat(schedules_to_concat)
    
    cursor = pyodbc_connection["cursor"]
    cursor.execute("EXEC dbo.Truncate_Schedule @ClearAll=?", 1 if reload_history else 0)
    cursor.commit()

    last_event_date_with_data = cursor.execute("SET NOCOUNT ON; EXEC dbo.Get_LastEventDateWithData").fetchval()
    schedule = schedule[(schedule["EventDate"] > last_event_date_with_data)].reset_index(drop=True)
    schedule["id"] = 0

    new_event_id = cursor.execute("SET NOCOUNT ON; EXEC dbo.Get_MaxId @TableName=?", "dbo.Event").fetchval() + 1
    new_session_id = cursor.execute("SET NOCOUNT ON; EXEC dbo.Get_MaxId @TableName=?", "dbo.Session").fetchval() + 1

    # Assign event keys
    for i in range(0, len(schedule)):
        schedule["id"].iloc[i] = new_event_id
        new_event_id += 1

    events = schedule[["id", "RoundNumber", "Country", "Location", "OfficialEventName", "EventDate", "EventName", "EventFormat", "F1ApiSupport"]]

    # Unpivot session data
    session_frames = []
    for i in range(1, 6):
        session_frame = schedule[["id", "Session" + str(i), "Session" + str(i) + "Date"]][(~schedule["Session" + str(i)].isnull())]
        if len(session_frame) == 0: continue
        session_frame.rename(columns={"id": "EventId", "Session" + str(i): "SessionName", "Session" + str(i) + "Date": "SessionDate"}, inplace=True)
        session_frame["SessionOrder"] = i
        session_frames.append(session_frame)

    sessions = pd.concat(session_frames)
    sessions["id"] = 0
    sessions.sort_values("SessionDate", inplace=True)

    # Assign session id
    for i in range(0, len(sessions)):
        sessions["id"].iloc[i] = new_session_id
        new_session_id += 1

    # Load to SQL
    data_logging(pyodbc_connection, f"Loading {len(events)} records to Event")
    events.to_sql("Event", sqlalchemy_engine, if_exists="append", index=False)
    data_logging(pyodbc_connection, f"Loading {len(sessions)} records to Session")
    sessions.to_sql("Session", sqlalchemy_engine, if_exists="append", index=False)


def load_session_data(pyodbc_connection, sqlalchemy_engine, force_eventId=None, force_sessionId=None, force_reload=False):

    cursor = pyodbc_connection["cursor"]

    # Clean up any old raw telemetry data
    cursor.execute("SET NOCOUNT ON; EXEC dbo.Cleanup_RawTelemetry")
    data_logging(pyodbc_connection, f"Ran Cleanup_RawTelemetry")
     
    # Get API strings
    if force_eventId is not None:
        sql = f"EXEC dbo.Get_SessionsToLoad @ForceEventId = {force_eventId}, @ForceSessionId = {force_sessionId};"
    else:
        sql = "EXEC dbo.Get_SessionsToLoad;"

    sessions_frame = pd.read_sql_query("SET NOCOUNT ON; " + sql, sqlalchemy_engine)

    if len(sessions_frame) == 0:
        data_logging(pyodbc_connection, "No sessions to update")
        return False

    

    sessions_data = []
    for i in range(0, len(sessions_frame)):
        wname = sessions_frame["EventName"].iloc[i]
        wdate = str(sessions_frame["EventDate"].iloc[i])[:10]
        sname = sessions_frame["SessionName"].iloc[i]
        sdate = str(sessions_frame["SessionDate"].iloc[i])[:10]
        api_string = ff.api.make_path(wname, wdate, sname, sdate)

        print(api_string)

        sessions_data.append({
            "EventId": sessions_frame["EventId"].iloc[i],
            "SessionId": sessions_frame["SessionId"].iloc[i],
            "api_string": api_string
        })

    # Get data from API, check row counts/update load status, clear down and load as required
    for session in sessions_data:
        data_logging(pyodbc_connection, f"Calling API: {session['api_string']}")
        abort = False
        try:
            lap_data = ff.api.timing_data(session["api_string"])[0]
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Lap data unavailable: {session['api_string']}")
            abort = True

        try:
            timing_data = ff.api.timing_app_data(session["api_string"])
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Timing data unavailable: {session['api_string']}")
            abort = True

        try:
            car_data = ff.api.car_data(session["api_string"])
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Car data unavailable: {session['api_string']}")
            abort = True

        try:
            position_data = ff.api.position_data(session["api_string"])
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Position data unavailable: {session['api_string']}")
            abort = True

        try:
            track_status = ff.api.track_status_data(session["api_string"])
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Track status data unavailable: {session['api_string']}")
            abort = True

        try:
            session_status = ff.api.session_status_data(session["api_string"])
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Session status data unavailable: {session['api_string']}")
            abort = True

        try:
            driver_info = ff.api.driver_info(session["api_string"])
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Session driver info unavailable: {session['api_string']}")
            abort = True

        try:
            weather_data = ff.api.weather_data(session["api_string"])
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Session weather data unavailable: {session['api_string']}")
            abort = True

        if abort:
            # Update aborted load count and add to log, continue to next loop iteration
            cursor.execute("EXEC dbo.Update_IncrementAbortedLoadCount @SessionId=?", int(session["SessionId"]))
            cursor.commit()
            data_logging(pyodbc_connection, f"Data load aborted: {session['api_string']}")
            continue

        
        new_lapId = cursor.execute("SET NOCOUNT ON; EXEC dbo.Get_MaxId @TableName=?", "dbo.Lap").fetchval() + 1

        lap_data["SessionId"] = session["SessionId"]
        lap_data["id"] = 0

        # Lap
        for i in range(0, len(lap_data)):
            lap_data["id"].iloc[i] = new_lapId

            new_lapId += 1

        laps = lap_data[["id", "SessionId", "Time", "Driver", "LapTime", "NumberOfLaps", "NumberOfPitStops", "PitOutTime", "PitInTime", "IsPersonalBest"]][(lap_data["Driver"] != "")]

        # Sector
        sector_frames = []
        for i in range(1, 4):
            sector_frame = lap_data[["id", "Driver", "Sector" + str(i) + "Time", "Sector" + str(i) + "SessionTime"]][(~lap_data["Sector" + str(i) + "Time"].isnull()) & (lap_data["Driver"] != "")]
            if len(sector_frame) == 0: continue
            sector_frame.rename(columns={"id": "LapId", "Sector" + str(i) + "Time": "SectorTime", "Sector" + str(i) + "SessionTime": "SectorSessionTime"}, inplace=True)
            sector_frame["SectorNumber"] = i
            sector_frames.append(sector_frame)

        sectors = pd.concat(sector_frames)
        sectors["SessionId"] = session["SessionId"]
        sectors.sort_values("LapId", inplace=True)

        # Timing data
        timing_data["SessionId"] = session["SessionId"]

        # Car data
        car_frames = []
        for driver in car_data:
            car_frame = car_data[driver]
            car_frame["Driver"] = driver
            car_frames.append(car_frame)

        car_data = pd.concat(car_frames)
        car_data["SessionId"] = session["SessionId"]
        car_data.rename(columns={"nGear": "Gear"}, inplace=True)

        # Position data
        position_frames = []
        for driver in position_data:
            position_frame = position_data[driver]
            position_frame.drop(["index"], axis=1, errors="ignore", inplace=True)
            position_frame["Driver"] = driver
            position_frames.append(position_frame)

        position_data = pd.concat(position_frames)
        position_data["SessionId"] = session["SessionId"]

        # Track status
        track_status = pd.DataFrame(track_status)
        track_status["SessionId"] = session["SessionId"]

        # Session status
        session_status = pd.DataFrame(session_status)
        session_status["SessionId"] = session["SessionId"]

        # Driver info
        driver_frames = []
        i = 0
        for driver in driver_info:
            driver_frame = pd.DataFrame(driver_info[driver], index=[i])
            driver_frames.append(driver_frame)
            i += 1

        driver_info = pd.concat(driver_frames)
        driver_info["SessionId"] = session["SessionId"]

        # Weather data
        weather_data = pd.DataFrame(weather_data)
        weather_data["SessionId"] = session["SessionId"]


        # Compare row counts to SQL
        existing_counts = pd.read_sql_query(f"SET NOCOUNT ON; EXEC dbo.Get_TelemetryRowCounts @SessionId = {session['SessionId']}", sqlalchemy_engine)
        existing_total =  existing_counts["Laps"][0] + existing_counts["Sectors"][0] \
            + existing_counts["TimingData"][0] + existing_counts["CarData"][0] + existing_counts["PositionData"][0] \
            + existing_counts["TrackStatus"][0] + existing_counts["SessionStatus"][0] + existing_counts["DriverInfo"][0] \
            + existing_counts["WeatherData"][0]
        new_total = len(laps) + len(sectors) + len(timing_data) + len(car_data) + len(position_data) \
            + len(track_status) + len(session_status) + len(driver_info) + len(weather_data)

        if new_total <= existing_total and force_reload == False:
            # Data already fully loaded, update flag
            cursor.execute("EXEC dbo.Update_SessionLoadStatus @SessionId=?, @Status=?", int(session["SessionId"]), 1)
            cursor.commit()
            data_logging(pyodbc_connection, f"Confirmed data load complete for SessionId {session['SessionId']}")
        else:
            # Load /reload data
            cursor.execute("EXEC dbo.Delete_Telemetry @SessionId=?", int(session["SessionId"]))
            cursor.commit()

            # Break up large datasets into 100k row chunks - Azure SQL returns intermittent errors when maxed out
            # Retry max three times on any load before giving up
            for dataset in [
                (laps, "Lap"),
                (sectors, "Sector"),
                (timing_data, "TimingData"),
                (car_data, "CarData"),
                (position_data, "PositionData"),
                (track_status, "TrackStatus"),
                (session_status, "SessionStatus"),
                (driver_info, "DriverInfo"),
                (weather_data, "WeatherData")
            ]:
                data_logging(pyodbc_connection, f"Loading {len(dataset[0])} records to {dataset[1]}")
                chunk_ranges = []
                chunk_size = 100000
                abort = False
                for i in range(0, int(len(dataset[0]) / chunk_size) + 1):
                    chunk_ranges.append(
                        (
                            i * chunk_size,
                            min((i + 1) * chunk_size, len(dataset[0]))
                        )
                    )

                for chunk_range in chunk_ranges:
                    success = False
                    error_count = 0
                    if len(chunk_ranges) > 1:
                        data_logging(pyodbc_connection, f"Loading chunk {str(chunk_range[0])}:{str(chunk_range[1])} to {dataset[1]}")
                    while not success and error_count < 3:
                        try:
                            dataset[0].iloc[chunk_range[0]:chunk_range[1]].to_sql(dataset[1], sqlalchemy_engine, if_exists="append", index=False)
                        except OperationalError:
                            error_count += 1
                            data_logging(pyodbc_connection, f"Operational error loading chunk; attempt {str(error_count)}")
                            time.sleep(5)
                        else:
                            success = True
                            time.sleep(5)

                    if not success:
                        abort = True

                if abort:
                    cursor.execute("EXEC dbo.Update_IncrementAbortedLoadCount @SessionId=?", int(session["SessionId"]))
                    cursor.commit()
                    data_logging(pyodbc_connection, f"Data load aborted: {session['api_string']}")
                    break

            if not abort:
                cursor.execute("EXEC dbo.Update_SetNullTimes @SessionId=?", int(session["SessionId"]))
                cursor.execute("EXEC dbo.Update_SetDriverTeamOrders @SessionId=?", int(session["SessionId"]))
                cursor.execute("EXEC dbo.Insert_MissingSectors @SessionId=?", int(session["SessionId"]))

                cursor.execute("EXEC dbo.Update_SessionLoadStatus @SessionId=?, @Status=?", int(session["SessionId"]), 0)
                cursor.commit()
                data_logging(pyodbc_connection, f"Data load at least partially complete for SessionId {session['SessionId']}")

    return True


def run_transforms(pyodbc_connection, sqlalchemy_engine, force_eventId=None, force_sessionId=None):
    # Transforms all take place using stored procedures, this script just calls and passes parameters to each
    cursor = pyodbc_connection["cursor"]

    success = False
    error_count = 0

    while not success and error_count < 3:
        try:
            if force_eventId is not None:
                sql = f"EXEC dbo.Get_SessionsToTransform @ForceEventId = {force_eventId}, @ForceSessionId = {force_sessionId};"
            else:
                sql = "EXEC dbo.Get_SessionsToTransform"

            sessions_frame = pd.read_sql_query("SET NOCOUNT ON; " + sql, sqlalchemy_engine)[["SessionId", "EventId"]]
            session_dicts = []
            for i in range(0, len(sessions_frame)):
                session_dicts.append({
                    "SessionId": sessions_frame["SessionId"].iloc[i],
                    "EventId": sessions_frame["EventId"].iloc[i]
                })

            if len(session_dicts) > 0:
                data_logging(pyodbc_connection, f"Running transforms for {len(session_dicts)} sessions...")

            for iSession, session_dict in enumerate(session_dicts):
                sessionId = session_dict["SessionId"]
                eventId = session_dict["EventId"]
                data_logging(pyodbc_connection, f"Running transforms for sessionId {sessionId}")

                cursor.execute("SET NOCOUNT ON; EXEC dbo.Update_SessionTransformStatus @SessionId=?, @Status=?", int(sessionId), 0)

                cursor.execute("SET NOCOUNT ON; EXEC dbo.Merge_UpdateTelemetryTimes @SessionId=?", int(sessionId))
                data_logging(pyodbc_connection, f"Ran Merge_UpdateTelemetryTimes for sessionId {sessionId}")

                cursor.execute("SET NOCOUNT ON; EXEC dbo.Merge_LapData @SessionId=?", int(sessionId))
                data_logging(pyodbc_connection, f"Ran Merge_LapData for sessionId {sessionId}")

                cursor.execute("SET NOCOUNT ON; EXEC dbo.Merge_CarData @SessionId=?", int(sessionId))
                data_logging(pyodbc_connection, f"Ran Merge_CarData for sessionId {sessionId}")

                cursor.execute("SET NOCOUNT ON; EXEC dbo.Merge_TrackMap @EventId=?", int(eventId))
                data_logging(pyodbc_connection, f"Ran Merge_TrackMap for SessionId {sessionId}")

                cursor.execute("SET NOCOUNT ON; EXEC dbo.Merge_CarDataNorms @SessionId=?", int(sessionId))
                data_logging(pyodbc_connection, f"Ran Merge_CarDataNorms for SessionId {sessionId}")

                cursor.execute("SET NOCOUNT ON; EXEC dbo.Update_SessionTransformStatus @SessionId=?, @Status=?", int(sessionId), 1)
                data_logging(pyodbc_connection, f"Completed transforms for SessionId {sessionId} ({iSession+1} of {len(session_dicts)})")

                cursor.commit()

        except OperationalError:
            error_count += 1
            data_logging(pyodbc_connection, f"Operational error during transforms; attempt {str(error_count)}")
            time.sleep(5)
        else:
            success = True


def wrapper(force_eventId=None, force_sessionId=None, force_reload=False):
    # Wraps together the refresh/load/transform functions
    pyodbc_connection = sql_connection.get_pyodbc_connection()
    sqlalchemy_engine = sql_connection.get_sqlalchemy_engine()
    refresh_schedule(pyodbc_connection, sqlalchemy_engine)
    quick_loop = load_session_data(pyodbc_connection, sqlalchemy_engine, force_eventId, force_sessionId, force_reload)
    run_transforms(pyodbc_connection, sqlalchemy_engine, force_eventId, force_sessionId)
    pyodbc_connection["connection"].close()
    sqlalchemy_engine.dispose()

    return quick_loop
