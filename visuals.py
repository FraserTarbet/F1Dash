import plotly.graph_objects as go
import pandas as pd


def get_figure():
    # Returns a consistent starting point for each visual
    fig = go.Figure()
    fig.update_layout(
        {
            "plot_bgcolor": "rgba(0, 0, 0, 0)",
            "paper_bgcolor": "rgba(0, 0, 0, 0)"
        },
        font_color="white"
    )

    return fig


def filter_data(data, filter_dict_list, ignore=[]):

    # Loop through filters and filter dataframe by each

    for filter_dict in filter_dict_list:
        for field in filter_dict:
            if field in ["TimeFrom", "TimeTo"]:
                # Handle time filtering here
                if field not in ignore:
                    pass
            else:
                if field in data.columns and field not in ignore:
                    data = data[(data[field].isin(filter_dict[field]))]

    return data


def ns_to_delta_string(ns, is_benchmark=False):

    # Converts ns to readable string
    
    ms = ns / 1000000
    s = ms / 1000
    m = int(s / 60)
    rem_s = int(s - (m * 60))
    rem_ms = int(ms - (m * 60 + rem_s) * 1000)
    if is_benchmark == True:
        string = f"{str(m).rjust(2, '0')}:{str(rem_s).rjust(2, '0')}.{str(rem_ms)}"
    else:
        pol = "-" if ns < 0 else "+"
        if m > 0:
            string = f"{pol}{str(m).rjust(2, '0')}:{str(rem_s).rjust(2, '0')}.{str(rem_ms).rjust(3, '0')}"
        else:
            string = f"{pol}{str(rem_s).rjust(2, '0')}.{str(rem_ms).rjust(3, '0')}"
    
    return string


def get_time_axis_ticks(time_min, time_max):

    # Returns a dynamic number of axis values/labels for time Y axis
    
    max_ticks = 12
    time_range = time_max - time_min
    one_second = 1000000000

    tick_spacings = [
        one_second * 0.05,
        one_second * 0.1,
        one_second * 0.5,
        one_second,
        one_second * 2,
        one_second * 5,
        one_second * 10
    ]
    
    for spacing in tick_spacings:
        if time_range / spacing < max_ticks:
            break
            
    tick_values = []
    tick_labels = []
    for i in range(0, max_ticks):
        tick_values.append(time_min + i * spacing)
        if i == 0:
            label = ns_to_delta_string(time_min, True)
        else:
            label = ns_to_delta_string(i * spacing)
        tick_labels.append(label)
        
    return tick_values, tick_labels


def build_lap_plot():

    # Plot of lap times, banded by team -> driver -> stint
    # Not filtered by laps or stints

    fig = get_figure()

    return fig


def build_track_map():

    # Fastest driver per sector or zone, or brake/gear per sector or zone
    # Not filtered by sector or zone

    fig = get_figure()

    return fig


def build_stint_graph():

    # Lap/zone/sector times per driver over the session, or lap/zone/sector times per unique stint over stint laps
    # Not filtered by laps
    # Doesn't drive any crossfiltering

    fig = get_figure()

    return fig


def build_inputs_graph():

    # Car inputs over time for a maximum of two laps

    fig = get_figure()

    return fig


def build_conditions_plot():

    # Weather, track status, and track activity over total session time
    # Not crossfiltered by anything

    fig = get_figure()

    return fig