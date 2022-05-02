from dash import dcc, html, Input, Output, State, dash_table, callback_context, no_update
from dash.exceptions import PreventUpdate
from dash_extensions.enrich import DashProxy, ServersideOutput, ServersideOutputTransform
import dash_bootstrap_components as dbc
import json
import update_database
import read_database
import layouts
import file_store
import visuals

config = read_database.get_app_config()

file_store.size_limit_in_GB = float(config["MaxFileStoreSizeInGB"])
file_store.delete_files(delete_all=True)

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
        dcc.Store(id="layout_config", storage_type="memory"),
        dcc.Store(id="events_and_sessions", storage_type="memory"),
        dcc.Store(id="selected_session", storage_type="memory"),
        dcc.Store(id="loaded_session", storage_type="memory"),
        dcc.Store(id="top_filters", storage_type="memory"),
        dcc.Store(id="crossfilters", storage_type="memory"),
        dcc.Store(id="time_filters", storage_type="memory"),
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
        const client_info = {userAgent: navigator.userAgent, height: screen.height, width: screen.width};
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

    is_mobile = True if client_info["isMobile"] == True else False
    if is_mobile == True or config["ForceMobileLayout"] == "1":
        layout = layouts.layout_dict["mobile"]
    else:
        layout = layouts.layout_dict["desktop"]

    read_database.app_logging(str(client_info), "initiate", "mobile" if is_mobile else "desktop")
    
    available_events_and_sessions = json.dumps(read_database.get_available_sessions())

    return (
        layout,
        available_events_and_sessions
    )

# Open/close parameters panel
@dash_app.callback(
    Output("parameters_panel", "is_open"),
    Input("open_parameters_button", "n_clicks"),
    Input("close_parameters_button", "n_clicks"),
    Input("datasets", "data"),
    State("parameters_panel", "is_open"),
    State("selected_session", "data"),
    State("loaded_session", "data")
)
def open_close_parameters(open_click, close_click, datasets, is_open, selected_session, loaded_session):

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

# Populate session options and filters on panel open or filter change
@dash_app.callback(
    Output("event_select", "options"),
    Output("event_select", "value"),
    Output("session_select", "options"),
    Output("session_select", "value"),
    Output("team_filter_dropdown", "options"),
    Output("driver_filter_dropdown", "options"),
    Input("open_parameters_button", "n_clicks"),
    Input("top_filters", "data"),
    State("events_and_sessions", "data"),
    State("selected_session", "data"),
    State("loaded_session", "data"),
    State("datasets", "data")
)
def populate_parameters(click, top_filters, events_and_sessions, selected_session, loaded_session, datasets):
    events_and_sessions = json.loads(events_and_sessions)[0]

    # Event
    events_list = []
    for label in events_and_sessions["events"]:
        events_list.append({"label": label, "value": events_and_sessions["events"][label]})    
    if loaded_session is None:
        event_value = events_list[0]["value"]
    else:
        # Populate loaded event into input
        loaded_session = json.loads(loaded_session)
        loaded_event_id = loaded_session["EventId"]
        loaded_session_name = loaded_session["SessionName"]
        event_value = loaded_event_id

    # Session
    sessions_list = []
    for session in events_and_sessions["sessions"][str(event_value)]:
        sessions_list.append({"label": session, "value": session})
    if loaded_session is None:
        session_value = sessions_list[0]["value"]
    else:
        # Populate selected session into input
        session_value = loaded_session_name

    # Team & driver filters
    if datasets is None:
        team_options = no_update
        driver_options = no_update
    else:
        session_drivers = datasets["session_drivers"]
        team_options = visuals.get_filter_options(session_drivers, top_filters, ("TeamName", "TeamName"), ["TeamName", "Driver"])
        driver_options = visuals.get_filter_options(session_drivers, top_filters, ("Tla", "RacingNumber"), ["Driver"])
    
    return (
        events_list,
        event_value,
        sessions_list,
        session_value,
        team_options,
        driver_options
    )


# Toggle parameters panel close enable/disable, as well as loading indicator
@dash_app.callback(
    Output("close_parameters_button", "disabled"),
    Output("spinner_col", "children"),
    Input("open_parameters_button", "n_clicks"),
    Input("selected_session", "data")
)
def lock_panel_on_loading(open_parameters_button, selected_session):
    caller = callback_context.triggered[0]["prop_id"].split(".")[0]
    if caller == "open_parameters_button":
        return (
            False,
            None
        )
    elif caller == "selected_session":
        return (
            True,
            dbc.Spinner(color="primary")
        )
    else:
        return (
            True,
            no_update
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
@dash_app.callback(
    Output("dashboard_heading", "children"),
    Output("loaded_session", "data"),
    Input("datasets", "data"),
    State("events_and_sessions", "data"),
    State("selected_session", "data")
)
def refresh_heading(datasets, events_and_sessions, selected_session):
    if selected_session is None:
        return no_update
    else:
        selected_session = json.loads(selected_session)
        event_id = selected_session["EventId"]
        session_name = selected_session["SessionName"]
        events_dict = json.loads(events_and_sessions)[0]["events"]
        for event_name in events_dict:
            if int(events_dict[event_name]) == int(event_id): break

        loaded_session = json.dumps({"EventId": event_id, "SessionName": session_name})

    return (
        f"{event_name}, {session_name}",
        loaded_session
    )


# Update filters
@dash_app.callback(
    Output("top_filters", "data"),
    Output("crossfilters", "data"),
    Output("time_filters", "data"),
    Output("team_filter_dropdown", "value"),
    Output("driver_filter_dropdown", "value"),
    Input("team_filter_dropdown", "value"),
    Input("driver_filter_dropdown", "value"),
    Input("track_split_selector", "value"),
    Input("clean_laps_checkbox", "value"),
    State("datasets", "data")
)
def update_filters(team_filter_values, driver_filter_values, track_split_value, clean_laps_value, datasets):

    if datasets is not None:
        caller = callback_context.triggered[0]["prop_id"].split(".")[0]

         # Top level filters
        if caller in ["team_filter_dropdown", "driver_filter_dropdown", "track_split_selector", "clean_laps_checkbox"]:

            top_filters = {}

            # Team and driver filters
            original_driver_filter_values = driver_filter_values
            if team_filter_values is not None and len(team_filter_values) > 0: top_filters["TeamName"] = team_filter_values
            team_filter_values_output = no_update
            if caller == "team_filter_dropdown":
                # Remove any filtered drivers that are not in currently filtered teams
                if driver_filter_values is not None and len(driver_filter_values) > 0:
                    valid_drivers = list(visuals.filter_data(datasets["session_drivers"], [top_filters])["RacingNumber"])
                    driver_filter_values = [i for i in driver_filter_values if i in valid_drivers]
            driver_filter_values_output = driver_filter_values if driver_filter_values != original_driver_filter_values else no_update
            if driver_filter_values is not None and len(driver_filter_values) > 0: top_filters["Driver"] = driver_filter_values

            # Split selector
            top_filters["track_split"] = [track_split_value]

            # Clean laps
            top_filters["CleanLap"] = [clean_laps_value]

            # Lower filters
            crossfilters = {} # Clear crossfilters on top filter change to avoid orphaned filtering, e.g. crossfiltering a lap for an unfiltered driver
            time_filters = no_update

    else:
        # Create default / empty dictionaries when no dataset has been loaded yet
        top_filters = {
            "track_split": ["sectors"],
            "CleanLap": [True]
        }
        crossfilters = {}
        time_filters = {}
        team_filter_values_output = no_update
        driver_filter_values_output = no_update


    return (
        top_filters,
        crossfilters,
        time_filters,
        team_filter_values_output,
        driver_filter_values_output
    )


# Update all four main visuals on dataset reload, filter update, or visual interation
@dash_app.callback(
    Output("lap_plot", "figure"),
    Output("track_map", "figure"),
    Output("stint_graph", "figure"),
    Output("inputs_graph", "figure"),
    Output("conditions_plot", "figure"),
    Input("datasets", "data"),
    Input("top_filters", "data"),
    Input("crossfilters", "data"),
    Input("time_filters", "data"),
    State("client_info", "data")
)
def refresh_visuals(datasets, top_filters, crossfilters, time_filters, client_info):

    # Ascertain which input has triggered this callback
    caller = callback_context.triggered[0]["prop_id"].split(".")[0]


    # Updated dataset triggers rebuild of all visuals
    # Updated top level filters also rebuilds all visuals except conditions plot?
    if caller in ["datasets", "top_filters",  ""]:
        data_dict = datasets
        filters = [
            top_filters,
            crossfilters,
            time_filters
        ]
        client_is_mobile = client_info["isMobile"]
        lap_plot = visuals.build_lap_plot(data_dict, filters, client_is_mobile)
        track_map = visuals.build_track_map(data_dict, filters, client_is_mobile)
        stint_graph = visuals.build_stint_graph(data_dict, filters, client_is_mobile)
        inputs_graph = visuals.build_inputs_graph(data_dict, filters, client_is_mobile)
        conditions_plot = visuals.build_conditions_plot(data_dict, client_is_mobile) if ~client_is_mobile else no_update

    # Updated crossfilters & time filters update only affected visuals
    if caller in ["crossfilters", "time_filters"]:
        lap_plot = no_update
        track_map = no_update
        stint_graph = no_update
        inputs_graph = no_update
        conditions_plot = no_update

    # Hovering is very selective


    return (
        lap_plot,
        track_map,
        stint_graph,
        inputs_graph,
        conditions_plot
    )


if __name__ == "__main__":
    # Azure host will not run this
    dash_app.run_server(debug=True)