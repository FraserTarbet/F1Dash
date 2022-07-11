import pyodbc
import sqlalchemy
import os


def get_pyodbc_connection():
    host_name = os.popen("hostname").read()
    if "DESKTOP" in host_name:
        server = "DESKTOP-O203E5C\SAMPLESERVER"
        database = "F1DashStreamline"
        connection = pyodbc.connect("DRIVER={ODBC Driver 13 for SQL Server};SERVER="+server+";DATABASE="+database+";TRUSTED_CONNECTION=yes;MARS_Connection=yes")
        cursor = connection.cursor()
    else:
        # Azure connection string
        connection_string = os.environ["SQLAZURECONNSTR_F1Dash"]
        connection = pyodbc.connect(connection_string)
        cursor = connection.cursor()

    return {
        "connection": connection,
        "cursor": cursor
    }


def get_sqlalchemy_engine():
    host_name = os.popen("hostname").read()
    if "DESKTOP" in host_name:
        server = "DESKTOP-O203E5C\SAMPLESERVER"
        database = "F1DashStreamline"
        engine = sqlalchemy.create_engine(
            "mssql+pyodbc://"+server+"/"+database+"?driver=ODBC+Driver+13+for+SQL+Server&trusted_connection=yes&mars_connection=yes",
            fast_executemany=True, pool_pre_ping=True, pool_recycle=3600
        )
    else:
        # Azure connection string
        connection_string = os.environ["CUSTOMCONNSTR_F1DashSqlAlchemy"]
        engine = sqlalchemy.create_engine(connection_string, fast_executemany=True, pool_pre_ping=True, pool_recycle=3600)

    return engine

