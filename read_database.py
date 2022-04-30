from matplotlib.style import available
import pandas as pd
import sql_connection
import os


def get_app_config():
    sqlalchemy_engine = sql_connection.get_sqlalchemy_engine()
    config_frame = pd.read_sql_query("SET NOCOUNT ON; EXEC dbo.Read_Config", sqlalchemy_engine)
    config = {}
    for i in range(len(config_frame)):
        config[config_frame["Parameter"].iloc[i]] = config_frame["Value"].iloc[i]
    sqlalchemy_engine.dispose()

    return config


def app_logging(client_info, type, message):
    host_name = os.popen("hostname").read()
    pyodbc_connection = sql_connection.get_pyodbc_connection()
    cursor = pyodbc_connection["cursor"]
    cursor.execute("EXEC dbo.Logging_App @HostName=?, @ClientInfo=?, @Type=?, @Message=?", host_name, client_info, type, message)
    cursor.commit()
    pyodbc_connection["connection"].close()
    print("app_logging: " + message)


def get_available_sessions():
    sqlalchemy_engine = sql_connection.get_sqlalchemy_engine()
    sessions_frame = pd.read_sql_query("SET NOCOUNT ON; EXEC dbo.Read_AvailableSessions", sqlalchemy_engine)
    unique_events = sessions_frame[["EventLabel", "EventId"]].drop_duplicates()
    available_events = dict(zip(unique_events["EventLabel"], unique_events["EventId"]))
    available_sessions = {}
    for event_id in list(unique_events["EventId"].unique()):
        available_sessions[event_id] = list(sessions_frame[(sessions_frame["EventId"] == event_id)]["SessionName"])
    sqlalchemy_engine.dispose()

    return {"events": available_events, "sessions": available_sessions}


def read_session_data(event_id, session_name):
    pass



if __name__ == "__main__":
    get_available_sessions()