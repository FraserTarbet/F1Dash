import sql_connection
import random
import time
import string
import os
import read_database
import update_database
import file_store

characters = string.ascii_lowercase + string.digits


def thread_initiate(max_wakeup_delay):

    wait_time = random.random() * max_wakeup_delay
    time.sleep(wait_time)
    host_name = os.popen("hostname").read()
    thread_id = ''.join(random.choice(characters) for i in range(24))

    return host_name, thread_id


def thread_checkin(type, host_name, thread_id):
    pyodbc_connection = sql_connection.get_pyodbc_connection()
    cursor = pyodbc_connection["cursor"]
    param_values = (type, host_name, thread_id)
    return_val = cursor.execute("SET NOCOUNT ON; EXEC dbo.Thread_Checkin @CheckinType=?, @HostName=?, @ThreadId=?", param_values).fetchval()
    cursor.commit()
    pyodbc_connection["connection"].close()
    return return_val == 1


def thread_loop(type, max_wakeup_delay, thread_sleep_in_hours, delete_delay_in_hours=None):

    host_name, thread_id = thread_initiate(max_wakeup_delay)
    thread_sleep_in_seconds = thread_sleep_in_hours * 60 * 60

    read_database.app_logging("app", "thread", f"Initiated {type} thread id {thread_id}")

    while True:
        if thread_checkin(type, host_name, thread_id):  

            # Run relevant process
            if type == "Database":
                read_database.app_logging("app", "database_thread", f"Running database thread loop id {thread_id}")
                quick_loop = update_database.wrapper()
            elif type == "Cache":
                read_database.app_logging("app", "cache_cleanup_thread", f"Running cache cleanup thread loop id {thread_id}")
                files_deleted = file_store.cleanup(delete_delay_in_hours)
                if files_deleted > 0:
                    read_database.app_logging("app", "cache_cleanup_thread", f"Cache cleanup thread deleted {files_deleted} files")
                quick_loop = False
            
            if quick_loop:
                time.sleep(60 * 5)
            else:
                time.sleep(thread_sleep_in_seconds)


