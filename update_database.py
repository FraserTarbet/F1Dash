import fastf1 as ff
import pandas as pd
import datetime
import sql_connection


def refresh_schedule(reload_history=False):
    # Refreshes future event data only - past events untouched
    #ff.Cache.clear_cache(".", deep=True)
    current_year = datetime.datetime.now().year
    current_date = datetime.datetime.now().date
    
    years = list(range(2018, current_year + 1)) if reload_history else [current_year]

    print(years)




if __name__ == "__main__":
    #ff.Cache.enable_cache(".")
    pass