from dash import dcc, html
import dash_bootstrap_components as dbc


# Layouts for mobile / non-mobile devices, to be picked by initial dash callback on client load

desktop = [
    dbc.Offcanvas(
        id="parameters_panel",
        is_open=True,
        backdrop="static",
        close_button=False,
        scrollable=True,
        children=[
            dbc.Row(
                [
                    dbc.Col(html.H3("F1Dash"), lg=9),
                    dbc.Col(dbc.Button(id="close_parameters_button", children="Close"), lg=3)
                ],
                justify="end"
            ),
            dbc.Row(
                [
                    dbc.Col(html.P("Blah blah blah blah blah blah blah blah blah blah blah blah blah blah blah"))
                ]
            ),
            dbc.Row(
                [
                    dbc.Col(html.Label("Event:"), lg=3),
                    dbc.Col(dbc.Select(id="event_select", size="sm"), lg=9)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            ),
            dbc.Row(
                [
                    dbc.Col(html.Label("Session:"), lg=3),
                    dbc.Col(dbc.Select(id="session_select", size="sm"), lg=9)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            )
            ,dbc.Row(
                [
                    dbc.Col(dbc.Button("Load session", id="load_button"), lg=6),
                    dbc.Col(id="spinner_col")
                ],
                align="center",
                justify="start",
                style={"margin-bottom": "5px"}
            ),
            dbc.Row(
                [
                    html.Hr()
                ]
            ),
            dbc.Row(
                [
                    dbc.Col(html.H5("Filters:"))
                ],
                align="center",
                justify="start",
                style={"margin-bottom": "5px"}
            ),
            dbc.Row(
                [
                    dbc.Col(html.Label("Teams:"), lg=3),
                    dbc.Col(dcc.Dropdown(id="team_filter_dropdown", multi=True), lg=9)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            ),
            dbc.Row(
                [
                    dbc.Col(html.Label("Drivers:"), lg=3),
                    dbc.Col(dcc.Dropdown(id="driver_filter_dropdown", multi=True), lg=9)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            ),
            dbc.Row(
                [
                    dbc.Col(dbc.Label("Split laps by: "), lg=4),
                    dbc.Col(dbc.RadioItems(
                        id="track_split_selector", 
                        options=[{"label": "Sectors", "value": "sectors"}, {"label": "Zones", "value": "zones"}],
                        value="sectors",
                        inline=True
                        ),
                        lg = 8
                    )
                ],
                align="center",
                style={"margin-bottom": "5px"}
            ),
            dbc.Row(
                [
                    dbc.Col(dbc.Label("Clean laps only (recommended): "), lg=9),
                    dbc.Col(dbc.Checkbox(id="clean_laps_checkbox", value=True), lg=3)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            )

        ]
    ),
    dbc.Row(
        [
            dbc.Col(dbc.Button("Open", id="open_parameters_button"), lg=1),
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


layout_dict = {
    "desktop": desktop,
    "mobile": mobile
}