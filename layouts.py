from dash import dcc, html
import dash_bootstrap_components as dbc


# Layouts for mobile / non-mobile devices, to be picked by initial dash callback on client load

desktop = [
    dbc.Offcanvas(
        id="parameters_panel",
        is_open=True,
        backdrop="static",
        close_button=False,
        children=[
            dbc.Row(
                [
                    dbc.Col(html.H3("Options"), lg=9),
                    dbc.Col(dbc.Button(id="close_parameters_button", children="Close"), lg=3)
                ],
                justify="end"
            ),
            dbc.Row(
                [
                    dbc.Col(html.Label("Event:"), lg=3),
                    dbc.Col(dbc.Select(id="event_select", size="sm"), lg=9)
                ],
                style={"margin-bottom": "5px"}
            ),
            dbc.Row(
                [
                    dbc.Col(html.Label("Session:"), lg=3),
                    dbc.Col(dbc.Select(id="session_select", size="sm"), lg=9)
                ],
                style={"margin-bottom": "5px"}
            )
            ,dbc.Row(
                [
                    dbc.Col(dbc.Button("Load session", id="load_button"), lg=6),
                    dbc.Col(dbc.Spinner(id="load_spinner", children=html.Div(id="loading_output")), lg=6, align="center")
                ],
                justify="start",
                style={"margin-bottom": "5px"}
            )
        ]
    ),
    dbc.Row(
        [
            dbc.Col(dbc.Button("Options", id="open_parameters_button"), lg=1),
            dbc.Col(html.H1(id="dashboard_heading"), lg=11)
        ],
        align="center", justify="start"
    ),
    dbc.Row(
        [
            dbc.Col(dcc.Graph(id="lap_plot"), lg=8),
            dbc.Col(dcc.Graph(id="track_map"), lg=4)
        ],
        align="center", justify="evenly"
    ),
    dbc.Row(
        [
            dbc.Col(dcc.Graph(id="stint_graph"), lg=4),
            dbc.Col(dcc.Graph(id="inputs_graph"), lg=8)
        ]
    )
]


mobile = [
    html.Div("This is the mobile layout")
]