from dash import dcc, html, Input, Output, State, dash_table, callback_context, no_update
from dash.exceptions import PreventUpdate
from dash_extensions.enrich import DashProxy, ServersideOutput, ServersideOutputTransform
import dash_bootstrap_components as dbc
import json
import time
import threading
import update_database
import read_database
import layouts
import file_store
import visuals


def filter_dict_from_inputs(input_dict):
    # Takes dict of callback inputs and computes a dict for visual filtering

    filters = {}
    for field in ["TeamName", "Driver", "Compound"]:
        if field in input_dict and input_dict[field] is not None and input_dict[field] not in [[False], []]:
            filters[field] = input_dict[field]

    if "CleanLap" in input_dict and input_dict["CleanLap"] != False:
        filters["CleanLap"] = [input_dict["CleanLap"]]

    if "track_split" in input_dict:
        filters["track_split"] = [input_dict["track_split"]]

    if "input_trace" in input_dict:
        filters["input_trace"] = input_dict["input_trace"]

    if "LapId" in input_dict and input_dict["LapId"] is not None:
        lap_ids = set()
        for point in input_dict["LapId"]["points"]:
            lap_id = point["customdata"]["LapId"]
            lap_ids.add(lap_id)
        filters["LapId"] = list(lap_ids)

    if "StintId" in input_dict and input_dict["StintId"] is not None:
        stint_ids = set()
        for point in input_dict["StintId"]["points"]:
            stint_id = point["customdata"]["StintId"]
            stint_ids.add(stint_id)
        filters["StintId"] = list(stint_ids)

    if "SectorOrZoneNumber" in input_dict and input_dict["SectorOrZoneNumber"] is not None:
        values = set()
        field = list(input_dict["SectorOrZoneNumber"]["points"][0]["customdata"].keys())[0]
        for point in input_dict["SectorOrZoneNumber"]["points"]:
            value = point["customdata"][field]
            values.add(value)
        filters[field] = list(values)

    if "TimeFilter" in input_dict and input_dict["TimeFilter"] is not None:
        range = input_dict["TimeFilter"]["range"]["x"]
        filter = (min(range), max(range))
        filters["TimeFilter"] = filter

    return filters


def database_thread_loop(thread_sleep_in_hours):
    thread_sleep_in_seconds = thread_sleep_in_hours * 60 * 60
    loops = 0
    while True:
        # On first loop, delay to keep concurrent processing low
        if loops == 0: time.sleep(30)
        read_database.app_logging("app", "database_thread", f"Running database thread loop ({str(loops)})")
        update_database.wrapper()
        time.sleep(thread_sleep_in_seconds)
        loops += 1


def cache_cleanup_thread_loop(thread_sleep_in_hours, delete_delay_in_hours):
    thread_sleep_in_seconds = thread_sleep_in_hours * 60 * 60
    loops = 0
    while True:
        # On first loop, delay to keep concurrent processing low
        if loops == 0: time.sleep(45)
        read_database.app_logging("app", "cache_cleanup_thread", f"Running cache cleanup thread loop ({str(loops)})")
        files_deleted = file_store.cleanup(delete_delay_in_hours)
        if files_deleted > 0:
            read_database.app_logging("app", "cache_cleanup_thread", f"Cache cleanup thread deleted {files_deleted} files")
        time.sleep(thread_sleep_in_seconds)
        loops += 1

read_database.app_logging("app", "startup", "App starting")

config = read_database.get_app_config()

file_store.size_limit_in_GB = float(config["MaxFileStoreSizeInGB"])
file_store.delete_files(delete_all=True)

database_thread = threading.Thread(
    target=database_thread_loop,
    daemon=True,
    args=(float(config["DatabaseThreadSleepInHours"]),)
)
#database_thread.start()

cache_cleanup_thread = threading.Thread(
    target=cache_cleanup_thread_loop,
    daemon=True,
    args=(
        float(config["CacheThreadSleepInHours"]),
        float(config["CacheFileDeleteDelayInHours"])
    )
)
#cache_cleanup_thread.start()

dash_app = DashProxy(__name__,
    meta_tags=[
        {"name": "viewport", "content": "width=device-width, initial-scale=1"}
    ],
    transforms=[ServersideOutputTransform()]
    # suppress_callback_exceptions=True
)
app = dash_app.server
dash_app.title = "F1Dash"

dash_app.layout = html.Div(
    id="top_div",
    children=[
        dcc.Store(id="client_info", storage_type="memory"),
        dcc.Store(id="events_and_sessions", storage_type="memory"),
        dcc.Store(id="selected_session", storage_type="memory"),
        dcc.Store(id="loaded_session", storage_type="memory"),
        dcc.Store(id="datasets", storage_type="memory"),
        dbc.Container(
            id="container",
            fluid=True
        )
    ]
)

# Clientside callback to get client info such as screen size
dash_app.clientside_callback(
    """
    function(trigger){
        const client_info = {
            userAgent: navigator.userAgent, 
            height: screen.availHeight, 
            width: screen.width,
            documentHeight: document.documentElement.clientHeight,
            documentWidth: document.documentElement.clientWidth
        };
        client_info.isMobile = Boolean(client_info.width < """ + config["DetectMobileWidth"] + """ || client_info.height < """ + config["DetectMobileHeight"] + """);

        return client_info
    }
    """,
    Output("client_info", "data"),
    Input("top_div", "children")
)

# Initiating callback
@dash_app.callback(
    Output("container", "children"),
    Output("events_and_sessions", "data"),
    Input("client_info", "data")
)
def initiate(client_info):

    # Use this callback to customise layouts within container based on desktop/mobile device

    if client_info["isMobile"]:
        layout = layouts.layout_mobile
    else:
        layout = layouts.layout_desktop

    read_database.app_logging(str(client_info), "initiate", "mobile" if client_info["isMobile"] else "desktop")

    available_events_and_sessions = read_database.get_available_sessions().to_dict()

    return (
        layout,
        available_events_and_sessions
    )

# Open/close parameters panel
@dash_app.callback(
    Output("parameters_panel", "is_open"),
    Input("open_parameters_button", "n_clicks"),
    Input("datasets", "data"),
    State("parameters_panel", "is_open"),
    State("selected_session", "data"),
    State("loaded_session", "data")
)
def open_close_parameters(open_click, datasets, is_open, selected_session, loaded_session):

    if callback_context.triggered[0]["prop_id"].split(".")[0] == "datasets":
        # Close having loaded new datasets
        return False

    open = True
    if open_click and is_open == False:
        open = True
    elif selected_session is not None:
        # Check whether submitted selected session has been loaded yet
        selected_session = json.loads(selected_session)
        selected_event_id = selected_session["EventId"]
        selected_session_name = selected_session["SessionName"]
        loaded_session = json.loads(loaded_session)
        loaded_event_id = loaded_session["EventId"]
        loaded_session_name = loaded_session["SessionName"]
        if loaded_session is None or loaded_event_id != selected_event_id or loaded_session_name != selected_session_name:
            open = True
        else:
            open = False
    return open


# Toggle parameters panel close enable/disable, as well as loading indicator
@dash_app.callback(
    Output("parameters_panel", "backdrop"),
    Output("load_button", "children"),
    Input("open_parameters_button", "n_clicks"),
    Input("selected_session", "data")
)
def lock_panel_on_loading(open_parameters_button, selected_session):
    caller = callback_context.triggered[0]["prop_id"].split(".")[0]
    if caller == "open_parameters_button":
        return (
            True,
            "Load new session"
        )
    elif caller == "selected_session":
        return (
            "static",
            [dbc.Spinner(color="light", size="sm"), " Please wait..."]
        )
    else:
        return (
            "static",
            no_update
        )


# Populate event dropdown
@dash_app.callback(
    Output("event_select", "options"),
    Output("event_select", "value"),
    Input("events_and_sessions", "data"),
    Input("open_parameters_button", "n_clicks"),
    State("loaded_session", "data")
)
def event_selector_refresh(events_and_sessions, panel_open, loaded_session):
    if callback_context.triggered[0]["prop_id"].split(".")[0] == "events_and_sessions":
        #events_and_sessions = json.loads(events_and_sessions)
        event_options = visuals.get_filter_options(events_and_sessions, {}, ("EventLabel", "EventId"))
        event_value = event_options[0]["value"]
    elif callback_context.triggered[0]["prop_id"].split(".")[0] == "open_parameters_button":
        event_options = no_update
        event_value = json.loads(loaded_session)["EventId"]
    else:
        event_options = no_update
        event_value = no_update

    return (
        event_options,
        event_value
    )
    
# Populate session dropdown
@dash_app.callback(
    Output("session_select", "options"),
    Output("session_select", "value"),
    Input("open_parameters_button", "n_clicks"),
    Input("event_select", "value"),
    State("events_and_sessions", "data"),
    State("loaded_session", "data")
)
def session_selector_refresh(panel_open, event_select_value, events_and_sessions, loaded_session):
    if callback_context.triggered[0]["prop_id"].split(".")[0] == "event_select":
        #events_and_sessions = json.loads(events_and_sessions)
        session_options = visuals.get_filter_options(events_and_sessions, {"EventId": [int(event_select_value)]}, ("SessionName", "SessionName"))
        session_value = session_options[0]["value"]
    elif callback_context.triggered[0]["prop_id"].split(".")[0] == "open_parameters_button":
        session_options = no_update
        session_value = json.loads(loaded_session)["SessionName"]
    else:
        session_options = no_update
        session_value = no_update

    return (
        session_options,
        session_value
    )


# Request session datasets
@dash_app.callback(
    Output("selected_session", "data"),
    Input("load_button", "n_clicks"),
    State("event_select", "value"),
    State("session_select", "value"),
    State("selected_session", "data"),
    State("client_info", "data")
)
def request_datasets(click, event_id, session_name, selected_session_state, client_info):
    if click is None:
        new_request = False
    if click is not None and selected_session_state is None:
        new_request = True
    if selected_session_state is not None:
        selected_session_state = json.loads(selected_session_state)
        if selected_session_state["EventId"] != event_id or selected_session_state["SessionName"] != session_name:
            new_request = True
        else:
            new_request = False     

    if new_request == True:
        selected_session = {"EventId": event_id, "SessionName": session_name} 
        read_database.app_logging(str(client_info), "request_datasets", f"event_id: {event_id}, session_name: {session_name}")
        cache_files_deleted = file_store.delete_files()
        if cache_files_deleted is not None:
            read_database.app_logging(str(client_info), "delete_files", f"{str(cache_files_deleted)} cache files deleted")
        return json.dumps(selected_session)
    else:
        return no_update


# Load session datasets to store
@dash_app.callback(
    ServersideOutput("datasets", "data", session_check=False),
    Input("selected_session", "data"),
    memoize = True
)
def load_datasets(selected_session):

    # Note: Adding client info state into this callback would prevent sharing of cache between sessions 
    # because it would appear as a distinct arg to ServersideOutput

    if selected_session == None:
        return (
            no_update,
            no_update,
            no_update
        )
    else:
        selected_session = json.loads(selected_session)
        event_id = selected_session["EventId"]
        session_name = selected_session["SessionName"]
        
        use_test_data = True if config["ForceTestData"] == "1" else False
        data_dict = read_database.read_session_data(event_id, session_name, use_test_data)
        
        return (
            data_dict
        )


# Update heading and loaded session keys on dataset reload
# Unhide filters, create layout components for visuals
@dash_app.callback(
    Output("upper_heading", "children"),
    Output("lower_heading", "children"),
    Output("loaded_session", "data"),
    Output("filters_div", "hidden"),
    Output("dashboard_div", "hidden"),
    Output("abstract_div", "hidden"),
    Input("datasets", "data"),
    State("events_and_sessions", "data"),
    State("selected_session", "data")
)
def refresh_heading(datasets, events_and_sessions, selected_session):
    if selected_session is None:
        return (
            no_update,
            no_update,
            no_update,
            no_update,
            no_update,
            no_update
        )
    else:
        selected_session = json.loads(selected_session)
        event_id = selected_session["EventId"]
        session_name = selected_session["SessionName"]
        upper_heading, lower_heading = visuals.get_dashboard_headings(events_and_sessions, event_id, session_name)
        loaded_session = json.dumps({"EventId": event_id, "SessionName": session_name})

    return (
        upper_heading,
        lower_heading,
        loaded_session,
        False,
        False,
        True
    )


# Open timeline
# Force conditions_plot sizing here? Keeps expanding unpredictably
@dash_app.callback(
    Output("conditions_panel", "is_open"),
    #Output("conditions_plot", "style"),
    Input("open_conditions_button", "n_clicks"),
    State("client_info", "data")
)
def open_conditions_panel(click, client_info):
    if click is not None:
        return True
        #    {"height": 250}
        
    else:
        return False
        #    {}
        



### Callback for each dropdown filter

@dash_app.callback(
    Output("team_filter_dropdown", "options"),
    Output("team_filter_dropdown", "value"),
    Input("datasets", "data")
)
def team_filter_dropdown_refresh(datasets):
    if datasets is None:
        return no_update, no_update
    else:
        return visuals.get_filter_options(datasets["session_drivers"], {}, ("TeamName", "TeamName")), []

@dash_app.callback(
    Output("driver_filter_dropdown", "options"),
    Input("team_filter_dropdown", "value"),
    Input("datasets", "data")
)
def driver_filter_dropdown_refresh(team_filter_values, datasets):
    if datasets is None:
        return no_update
    else:
        filter = {} if team_filter_values is None or team_filter_values == [] else {"TeamName": team_filter_values}
        return visuals.get_filter_options(datasets["session_drivers"], filter, ("Tla", "RacingNumber"))

@dash_app.callback(
    Output("driver_filter_dropdown", "value"),
    Input("team_filter_dropdown", "value"),
    Input("datasets", "data"),
    State("driver_filter_dropdown", "value")
)
def driver_filter_values_refresh(team_filter_values, datasets, driver_filter_values):
    if (team_filter_values is None or team_filter_values == []) and (driver_filter_values is None or driver_filter_values == []):
        return no_update
    elif callback_context.triggered[0]["prop_id"].split(".")[0] == "datasets":
        return []
    else:
        session_drivers = datasets["session_drivers"]
        valid_drivers = list(session_drivers[(session_drivers["TeamName"].isin(driver_filter_values))]["RacingNumber"])
        return [driver for driver in driver_filter_values if driver in valid_drivers]

@dash_app.callback(
    Output("compound_filter_dropdown", "options"),
    Output("compound_filter_dropdown", "value"),
    Input("datasets", "data")
)
def compound_filter_dropdown_refresh(datasets):
    if datasets is None:
        return no_update, no_update
    else:
        return visuals.get_filter_options(datasets["lap_times"], {}, ("Compound", "Compound")), []



### Callback for each of the main visuals

# Lap plot

@dash_app.callback(
    Output("lap_plot", "figure"),
    Output("lap_plot_loading", "children"),
    Input("team_filter_dropdown", "value"),
    Input("driver_filter_dropdown", "value"),
    Input("compound_filter_dropdown", "value"),
    Input("clean_laps_checkbox", "value"),
    Input("lap_plot", "selectedData"),
    Input("track_map", "selectedData"),
    Input("conditions_plot", "selectedData"),
    Input("datasets", "data"),
    State("client_info", "data")
)
def lap_plot_refresh(
    team_filter_values,
    driver_filter_values,
    compound_filter_values,
    clean_laps_filter_values,
    lap_plot_selection,
    track_map_selection,
    conditions_plot_selection,
    datasets,
    client_info
):
    if datasets is None:
        return (
            visuals.build_lap_plot(datasets, [], client_info),
            False
        )
    else:
        if callback_context.triggered[0]["prop_id"].split(".")[0] == "datasets":
            filters = filter_dict_from_inputs({
                "CleanLap": clean_laps_filter_values
            })
        else:
            filters = filter_dict_from_inputs({
                "TeamName": team_filter_values,
                "Driver": driver_filter_values,
                "Compound": compound_filter_values,
                "CleanLap": clean_laps_filter_values,
                "LapId": lap_plot_selection,
                "SectorOrZoneNumber": track_map_selection,
                "TimeFilter": conditions_plot_selection
            })
        return (
            visuals.build_lap_plot(datasets, filters, client_info),
            True
        )


# Track map

@dash_app.callback(
    Output("track_map", "figure"),
    Output("track_map_readout", "children"),
    Output("track_map_loading", "children"),
    Input("team_filter_dropdown", "value"),
    Input("driver_filter_dropdown", "value"),
    Input("compound_filter_dropdown", "value"),
    Input("track_split_selector", "value"),
    Input("clean_laps_checkbox", "value"),
    Input("lap_plot", "selectedData"),
    Input("track_map", "selectedData"),
    Input("conditions_plot", "selectedData"),
    Input("datasets", "data"),
    State("client_info", "data")
)
def track_map_refresh(
    team_filter_values,
    driver_filter_values,
    compound_filter_values,
    track_split_values,
    clean_laps_filter_values,
    lap_plot_selection,
    track_map_selection,
    conditions_plot_selection,
    datasets,
    client_info
):
    if datasets is None:
        figure, readout = visuals.build_track_map(datasets, [], client_info)
        return (
            figure,
            readout,
            False
        )
    else:
        if callback_context.triggered[0]["prop_id"].split(".")[0] == "datasets":
            filters = filter_dict_from_inputs({
                "CleanLap": clean_laps_filter_values,
                "track_split": track_split_values
            })
        else:
            filters = filter_dict_from_inputs({
                "TeamName": team_filter_values,
                "Driver": driver_filter_values,
                "Compound": compound_filter_values,
                "track_split": track_split_values,
                "CleanLap": clean_laps_filter_values,
                "LapId": lap_plot_selection,
                "SectorOrZoneNumber": track_map_selection,
                "TimeFilter": conditions_plot_selection
            })
        track_map, track_map_readout = visuals.build_track_map(datasets, filters, client_info)
        return (
            track_map,
            track_map_readout,
            True
        )


# Stint graph

@dash_app.callback(
    Output("stint_graph", "figure"),
    Output("stint_graph_loading", "children"),
    Input("team_filter_dropdown", "value"),
    Input("driver_filter_dropdown", "value"),
    Input("compound_filter_dropdown", "value"),
    Input("clean_laps_checkbox", "value"),
    Input("lap_plot", "selectedData"),
    Input("track_map", "selectedData"),
    Input("conditions_plot", "selectedData"),
    Input("datasets", "data"),
    State("client_info", "data")
)
def stint_graph_refresh(
    team_filter_values,
    driver_filter_values,
    compound_filter_values,
    clean_laps_filter_values,
    lap_plot_selection,
    track_map_selection,
    conditions_plot_selection,
    datasets,
    client_info
):
    if datasets is None:
        return (
            visuals.build_stint_graph(datasets, [], client_info),
            False
        )
    else:
        if callback_context.triggered[0]["prop_id"].split(".")[0] == "datasets":
            filters = filter_dict_from_inputs({
                "CleanLap": clean_laps_filter_values
            })
        else:
            filters = filter_dict_from_inputs({
                "TeamName": team_filter_values,
                "Driver": driver_filter_values,
                "Compound": compound_filter_values,
                "CleanLap": clean_laps_filter_values,
                "LapId": lap_plot_selection,
                "StintId": lap_plot_selection,
                "SectorOrZoneNumber": track_map_selection,
                "TimeFilter": conditions_plot_selection
            })
        return (
            visuals.build_stint_graph(datasets, filters, client_info),
            True
        )


# Inputs graph

@dash_app.callback(
    Output("inputs_graph", "figure"),
    Output("input_trace_selector_div", "hidden"),
    Output("inputs_graph_loading", "children"),
    Input("team_filter_dropdown", "value"),
    Input("driver_filter_dropdown", "value"),
    Input("compound_filter_dropdown", "value"),
    Input("clean_laps_checkbox", "value"),
    Input("lap_plot", "selectedData"),
    Input("track_map", "selectedData"),
    Input("input_trace_selector", "value"),
    Input("datasets", "data"),
    State("client_info", "data")
)
def inputs_graph_refresh(
    team_filter_values,
    driver_filter_values,
    compound_filter_values,
    clean_laps_filter_values,
    lap_plot_selection,
    track_map_selection,
    input_trace_selector_values,
    datasets,
    client_info
):
    if datasets is None:
        figure, data_displayed = visuals.build_inputs_graph(datasets, [], client_info)
        return (
            figure,
            True,
            False
        )
    else:
        if callback_context.triggered[0]["prop_id"].split(".")[0] == "datasets":
            filters = filter_dict_from_inputs({
                "CleanLap": clean_laps_filter_values,
                "input_trace": input_trace_selector_values
            })
        else:
            filters = filter_dict_from_inputs({
                "TeamName": team_filter_values,
                "Driver": driver_filter_values,
                "Compound": compound_filter_values,
                "CleanLap": clean_laps_filter_values,
                "LapId": lap_plot_selection,
                "SectorOrZoneNumber": track_map_selection,
                "input_trace": input_trace_selector_values
            })
        figure, data_displayed = visuals.build_inputs_graph(datasets, filters, client_info)
        return (
            figure,
            not data_displayed,
            True
        )


# Conditions plot
@dash_app.callback(
    Output("conditions_plot", "figure"),
    Input("datasets", "data"),
    Input("conditions_plot", "selectedData"),
    State("conditions_plot", "figure"),
    State("client_info", "data")
)
def conditions_plot_refresh(datasets, conditions_plot_selection, conditions_plot_state, client_info):
    if datasets is None:
        return visuals.build_conditions_plot(datasets, client_info)
    else:
        if callback_context.triggered[0]["prop_id"].split(".")[0] == "datasets":
            return visuals.build_conditions_plot(datasets, client_info)
        else:
            filter = filter_dict_from_inputs({
                "TimeFilter": conditions_plot_selection
            })
            return visuals.shade_conditions_plot(conditions_plot_state, filter)

        
if __name__ == "__main__":
    # Azure host will not run this
    dash_app.run_server(debug=True)