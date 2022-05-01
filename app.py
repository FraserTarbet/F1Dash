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
    meta_tags=[],
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
        const client_info = {height :screen.height, width: screen.width, userAgent: navigator.userAgent};
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
    Output("top_filters", "data"),
    Output("crossfilters", "data"),
    Output("time_filters", "data"),
    Input("client_info", "data")
)
def initiate(client_info):
    # Use this callback to customise layouts within container based on desktop/mobile device
    # print(client_info)

    available_events_and_sessions = json.dumps(read_database.get_available_sessions())

    top_filters = {}
    crossfilters = {}
    time_filters = {}

    return (
        layouts.desktop,
        available_events_and_sessions,
        top_filters,
        crossfilters,
        time_filters
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

# Populate session options and filters on panel open
@dash_app.callback(
    Output("event_select", "options"),
    Output("event_select", "value"),
    Output("session_select", "options"),
    Output("session_select", "value"),
    Input("open_parameters_button", "n_clicks"),
    State("events_and_sessions", "data"),
    State("selected_session", "data"),
    State("loaded_session", "data")
)
def populate_parameters(click, events_and_sessions, selected_session, loaded_session):
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
    
    return (
        events_list,
        event_value,
        sessions_list,
        session_value
    )

# Request session datasets
@dash_app.callback(
    Output("selected_session", "data"),
    Input("load_button", "n_clicks"),
    State("event_select", "value"),
    State("session_select", "value"),
    State("selected_session", "data")
)
def request_datasets(click, event_id, session_name, selected_session_state):
    if click is None:
        return no_update
    if selected_session_state is None:
        selected_session = {"EventId": event_id, "SessionName": session_name}   
    if selected_session_state is not None:
        selected_session_state = json.loads(selected_session_state)
        if selected_session_state["EventId"] != event_id or selected_session_state["SessionName"] != session_name:
            selected_session = {"EventId": event_id, "SessionName": session_name}  
        else:
            return no_update       

    return json.dumps(selected_session)


# Load session datasets to store
@dash_app.callback(
    ServersideOutput("datasets", "data"),
    Output("load_spinner", "loading_output"),
    Output("loaded_session", "data"),
    Input("selected_session", "data")
)
def load_datasets(selected_session):

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
        loaded_session = json.dumps({"EventId": event_id, "SessionName": session_name})
        use_test_data = True if config["ForceTestData"] == "1" else False
        data_dict = read_database.read_session_data(event_id, session_name, use_test_data)
        
        return (
            data_dict,
            1, 
            loaded_session
        )

# Update heading on dataset reload
@dash_app.callback(
    Output("dashboard_heading", "children"),
    Input("loaded_session", "data"),
    State("events_and_sessions", "data")
)
def refresh_heading(loaded_session, events_and_sessions):
    if loaded_session is None:
        return no_update
    else:
        loaded_session = json.loads(loaded_session)
        event_id = loaded_session["EventId"]
        session_name = loaded_session["SessionName"]
        events_dict = json.loads(events_and_sessions)[0]["events"]
        for event_name in events_dict:
            if int(events_dict[event_name]) == int(event_id): break

    return f"{event_name}, {session_name}"



# Refresh all four main visuals on dataset reload
@dash_app.callback(
    Output("lap_plot", "figure"),
    Output("track_map", "figure"),
    Output("stint_graph", "figure"),
    Output("inputs_graph", "figure"),
    Input("datasets", "data")
)
def refresh_visuals(data):

    # Ascertain which input has triggered this callback
    caller = callback_context.triggered[0]["prop_id"].split(".")[0]

    # Updated dataset triggers rebuild of all visuals
    if caller == "datasets" or caller == "":
        lap_plot = visuals.build_lap_plot()
        track_map = visuals.build_track_map()
        stint_graph = visuals.build_stint_graph()
        inputs_graph = visuals.build_inputs_graph()

    # Updated top level filters rebuilds all visuals?

    # Updated crossfilters updates only affected visuals?

    # Hovering is very selective


    return (
        lap_plot,
        track_map,
        stint_graph,
        inputs_graph
    )


if __name__ == "__main__":
    # Azure host will not run this
    dash_app.run_server(debug=True)