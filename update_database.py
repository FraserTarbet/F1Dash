import fastf1 as ff
import pandas as pd
import numpy as np
import datetime
import os
from requests import session

import sqlalchemy
import sql_connection

pd.options.mode.chained_assignment = None


def data_logging(pyodbc_connection, message):
    host_name = os.popen("hostname").read()
    cursor = pyodbc_connection["cursor"]
    cursor.execute("EXEC dbo.Logging_Data @HostName=?, @Message=?", host_name, message)
    cursor.commit()


def refresh_schedule(pyodbc_connection, sqlalchemy_engine, reload_history=False):
    # Refreshes future event data only - rounds with existing data are not touched
    data_logging(pyodbc_connection, "Starting schedule refresh")
    current_year = datetime.datetime.now().year
    current_date = datetime.datetime.now()
    
    years = list(range(2018, current_year + 1)) if reload_history else [current_year]

    schedules_to_concat = []
    for year in years:
        schedules_to_concat.append(ff.get_event_schedule(year))

    schedule = pd.concat(schedules_to_concat)
    
    cursor = pyodbc_connection["cursor"]
    cursor.execute("EXEC dbo.Truncate_Schedule @ClearAll=?", 1 if reload_history else 0)
    cursor.commit()

    last_event_date_with_data = cursor.execute("SET NOCOUNT ON; EXEC dbo.Get_LastEventDateWithData").fetchval()
    schedule = schedule[(schedule["EventDate"] >= last_event_date_with_data)].reset_index(drop=True)
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


def load_session_data(force_eventId=None, force_sessionId=None, force_reload=False): 
    # Get API strings
    if force_eventId is not None:
        sql = f"EXEC dbo.Get_SessionsToUpdate @ForceEventId = {force_eventId}, @ForceSessionId = {force_sessionId};"
    else:
        sql = "EXEC dbo.Get_SessionsToUpdate;"

    sessions_frame = pd.read_sql_query("SET NOCOUNT ON; " + sql, sqlalchemy_engine)

    if len(sessions_frame) == 0:
        data_logging(pyodbc_connection, "No sessions to update")
        return

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

        try:
            lap_data = ff.api.timing_data(session["api_string"])[0]
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Lap data unavailable: {session['api_string']}")
            continue

        try:
            timing_data = ff.api.timing_app_data(session["api_string"])
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Timing data unavailable: {session['api_string']}")
            continue

        try:
            car_data = ff.api.car_data(session["api_string"])
        except ff.api.SessionNotAvailableError:
            data_logging(pyodbc_connection, f"Car data unavailable: {session['api_string']}")
            continue


        cursor = pyodbc_connection["cursor"]
        new_lapId = cursor.execute("SET NOCOUNT ON; EXEC dbo.Get_MaxId @TableName=?", "dbo.Lap").fetchval() + 1

        lap_data["SessionId"] = session["SessionId"]
        lap_data["id"] = 0

        # Lap
        for i in range(0, len(lap_data)):
            lap_data["id"].iloc[i] = new_lapId

            new_lapId += 1

        laps = lap_data[["id", "SessionId", "Time", "Driver", "LapTime", "NumberOfLaps", "NumberOfPitStops", "PitOutTime", "PitInTime", "IsPersonalBest"]]

        # Sector
        sector_frames = []
        for i in range(1, 4):
            sector_frame = lap_data[["id", "Sector" + str(i) + "Time", "Sector" + str(i) + "SessionTime"]][(~lap_data["Sector" + str(i) + "Time"].isnull())]
            if len(sector_frame) == 0: continue
            sector_frame.rename(columns={"id": "LapId", "Sector" + str(i) + "Time": "SectorTime", "Sector" + str(i) + "SessionTime": "SectorSessionTime"}, inplace=True)
            sector_frame["SectorNumber"] = i
            sector_frames.append(sector_frame)

        sectors = pd.concat(sector_frames)
        sectors.sort_values("LapId", inplace=True)

        # Speed trap
        speed_trap_frames = []
        for i in ["I1", "I2", "FL", "ST"]:
            speed_trap_frame = lap_data[["id", "Speed" + i]][(~lap_data["Speed" + i].isnull())]
            if len(speed_trap_frame) == 0: continue
            speed_trap_frame.rename(columns={"id": "LapId", "Speed" + i: "Speed"}, inplace=True)
            speed_trap_frame["SpeedTrapPoint"] = i
            speed_trap_frames.append(speed_trap_frame)

        speed_traps = pd.concat(speed_trap_frames)
        speed_traps.sort_values("LapId", inplace=True)

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


        # Compare row counts to SQL
        existing_counts = pd.read_sql_query(f"SET NOCOUNT ON; EXEC dbo.Get_TelemetryRowCounts @SessionId = {session['SessionId']}", sqlalchemy_engine)
        existing_total =  existing_counts["Laps"][0] + existing_counts["Sectors"][0] + existing_counts["SpeedTraps"][0] + existing_counts["TimingData"][0] + existing_counts["CarData"][0]
        new_total = len(laps) + len(sectors) + len(speed_traps) + len(timing_data) + len(car_data)

        if new_total <= existing_total and force_reload == False:
            # Data already fully loaded
            cursor.execute("EXEC dbo.Update_SessionLoadStatus @SessionId=?, @Status=?", int(session["SessionId"]), 1)
            cursor.commit()
            data_logging(pyodbc_connection, f"Confirmed data load complete for {session['SessionId']}")
        else:
            # Load /reload data
            cursor.execute("EXEC dbo.Delete_Telemetry @SessionId=?", int(session["SessionId"]))
            cursor.commit()
            for dataset in [
                (laps, "Lap"),
                (sectors, "Sector"),
                (speed_traps, "SpeedTrap"),
                (timing_data, "TimingData"),
                (car_data, "CarData")
            ]:
                data_logging(pyodbc_connection, f"Loading {len(dataset[0])} records to {dataset[1]}")
                dataset[0].to_sql(dataset[1], sqlalchemy_engine, if_exists="append", index=False)

            cursor.execute("EXEC dbo.Update_SetNullTimes @SessionId=?", int(session["SessionId"]))

            cursor.execute("EXEC dbo.Update_SessionLoadStatus @SessionId=?, @Status=?", int(session["SessionId"]), 0)
            cursor.commit()
            data_logging(pyodbc_connection, f"Data load at least partially complete for {session['SessionId']}")
        



if __name__ == "__main__":
    pyodbc_connection = sql_connection.get_pyodbc_connection()
    sqlalchemy_engine = sql_connection.get_sqlalchemy_engine()
    ff.Cache.enable_cache("./ffcache")
    # refresh_schedule(pyodbc_connection, sqlalchemy_engine)
    load_session_data(3, 10, True)
    ff.Cache.clear_cache("./ffcache")