from dash import Dash, dcc, html, Input, Output, State, dash_table, callback_context, no_update
from dash.exceptions import PreventUpdate
import dash_bootstrap_components as dbc
import json
import update_database
import read_database
import layouts

config = read_database.get_app_config()

dash_app = Dash(__name__,
    meta_tags=[],
    # suppress_callback_exceptions=True
)
app = dash_app.server
dash_app.title = "F1Dash"

dash_app.layout = html.Div(
    id="top_div",
    children=[
        dcc.Store(id="client_info", storage_type="memory"),
        dcc.Store(id="layout_config", storage_type="memory"),
        dcc.Store(id="available_events_and_sessions", storage_type="memory"),
        dcc.Store(id="top_filters", storage_type="memory"),
        dcc.Store(id="crossfilters", storage_type="memory"),
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
    Output("available_events_and_sessions", "data"),
    Input("client_info", "data")
)
def read_client_info(client_info):
    # Use this callback to customise layouts within container based on desktop/mobile device
    # print(client_info)

    available_events_and_sessions = json.dumps(read_database.get_available_sessions())

    return (layouts.desktop,
        available_events_and_sessions
    )

# Open parameters panel
@dash_app.callback(
    Output("parameters_panel", "is_open"),
    Input("parameters_button", "n_clicks"),
    State("parameters_panel", "is_open")
)
def open_parameters(click, is_open):
    if click:
        return not is_open
    return is_open

# Populate session options and filters
@dash_app.callback(
    Output("event_select", "options"),
    Input("parameters_button", "n_clicks"),
    State("available_events_and_sessions", "data")
)
def populate_parameters(click, available_events_and_sessions):
    print(available_events_and_sessions)
    return [{"label": "test", "value": "5"}]


if __name__ == "__main__":
    # Azure host will not run this
    dash_app.run_server(debug=True)