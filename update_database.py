import fastf1 as ff
import pandas as pd
import datetime
import os
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
        session_frame = schedule[["id", "Session" + str(i), "Session" + str(i) + "Date"]]
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


if __name__ == "__main__":
    ff.Cache.enable_cache(".")
    refresh_schedule(sql_connection.get_pyodbc_connection(), sql_connection.get_sqlalchemy_engine())
    ff.Cache.clear_cache(".")