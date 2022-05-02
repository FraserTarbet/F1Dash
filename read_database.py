import pandas as pd
import sql_connection
import os
import threading


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
    print("app_logging: " + type + ": " + message)


def get_available_sessions():
    sqlalchemy_engine = sql_connection.get_sqlalchemy_engine()
    sessions_frame = pd.read_sql_query("SET NOCOUNT ON; EXEC dbo.Read_AvailableSessions", sqlalchemy_engine)
    unique_events = sessions_frame[["EventLabel", "EventId"]].drop_duplicates()
    available_events = dict(zip(unique_events["EventLabel"], unique_events["EventId"].tolist()))
    available_sessions = {}
    for event_id in list(unique_events["EventId"].unique().tolist()):
        available_sessions[event_id] = list(sessions_frame[(sessions_frame["EventId"] == event_id)]["SessionName"])
    sqlalchemy_engine.dispose()

    return [{"events": available_events, "sessions": available_sessions}]


def read_session_data(event_id, session_name, use_test_data):

    def read_sp(sqlalchemy_engine, sp_suffix, event_id, session_name, data_dict_list, data_key):

        if use_test_data == True:
            sql = f"SELECT * FROM TestData_{sp_suffix}"
        else:
            if data_key == "track_map":
                sql = f"EXEC dbo.Read_{sp_suffix} @EventId={event_id};"
            else:
                sql = f"EXEC dbo.Read_{sp_suffix} @EventId={event_id}, @SessionName='{session_name}';"

        data = pd.read_sql_query("SET NOCOUNT ON; " + sql, sqlalchemy_engine)
        data_dict = {data_key: data}
        data_dict_list.append(data_dict)
        print("appended " + data_key)

    sqlalchemy_engine = sql_connection.get_sqlalchemy_engine()

    sp_dict = {
        # "position_data": "PositionData",
        # "car_data": "CarData",
        # "track_map": "TrackMap",
        "lap_times": "LapTimes",
        # "sector_times": "SectorTimes",
        # "zone_times": "ZoneTimes",
        "conditions_data": "ConditionsData",
        "session_drivers": "SessionDrivers"
    }
    data_dict_list = []
    threads = []
    for key in sp_dict:
        # Start a new thread and have it append dataset to data_dict_list
        thread = threading.Thread(
            target=read_sp,
            daemon=True,
            args=(
                sqlalchemy_engine,
                sp_dict[key],
                event_id,
                session_name,
                data_dict_list,
                key
            )
        )

        threads.append(thread)
        thread.start()

    for thread in threads:
        thread.join()

    sqlalchemy_engine.dispose()

    # Turn list of single item dicts into a dict
    data_dict = {}
    for dict in data_dict_list:
        data_key = list(dict.keys())[0]
        data_dict[data_key] = dict[data_key]

    return data_dict


if __name__ == "__main__":
    read_session_data(87, "Race", True)