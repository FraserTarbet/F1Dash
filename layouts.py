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
                    dbc.Col(html.H3("F1Dash", style={"color": "#FF1E00"}), lg=12)
                ],
                justify="end"
            ),
            dbc.Row(
                [
                    dbc.Col(html.P("Blah blah blah blah blah blah blah blah blah blah blah blah blah blah blah"), style={"color": "#F7F4F1"})
                ]
            ),
            dbc.Row(
                [
                    html.Hr(style={"color": "#F7F4F1"})
                ]
            ),
            html.Div(
                id="filters_div",
                hidden=True,
                children=[
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
                            dbc.Col(html.Label("Teams:", style={"color": "#F7F4F1"}), lg=3),
                            dbc.Col(dcc.Dropdown(id="team_filter_dropdown", multi=True), lg=9)
                        ],
                        align="center",
                        style={"margin-bottom": "5px"}
                    ),
                    dbc.Row(
                        [
                            dbc.Col(html.Label("Drivers:", style={"color": "#F7F4F1"}), lg=3),
                            dbc.Col(dcc.Dropdown(id="driver_filter_dropdown", multi=True), lg=9)
                        ],
                        align="center",
                        style={"margin-bottom": "5px"}
                    ),
                    dbc.Row(
                        [
                            dbc.Col(html.Label("Compounds:", style={"color": "#F7F4F1"}), lg=3),
                            dbc.Col(dcc.Dropdown(id="compound_filter_dropdown", multi=True), lg=9)
                        ]
                    ),
                    dbc.Row(
                        [
                            dbc.Col(dbc.Label("Split laps by: ", style={"color": "#F7F4F1"}), lg=4),
                            dbc.Col(dbc.RadioItems(
                                id="track_split_selector", 
                                options=[{"label": "Sectors", "value": "sectors"}, {"label": "Zones", "value": "zones"}],
                                value="sectors",
                                inline=True,
                                style={"color": "#F7F4F1"}
                                ),
                                lg = 8
                            )
                        ],
                        align="center",
                        style={"margin-bottom": "5px"}
                    ),
                    dbc.Row(
                        [
                            dbc.Col(dbc.Label("Clean laps only (recommended): ", style={"color": "#F7F4F1"}), lg=9),
                            dbc.Col(dbc.Checkbox(id="clean_laps_checkbox", value=True), lg=3)
                        ],
                        align="center",
                        style={"margin-bottom": "5px"}
                    ),
                    dbc.Row(
                        [
                            html.Hr(style={"color": "#F7F4F1"})
                        ]
                    ),
                    dbc.Row(
                        [
                            dbc.Col(html.H5("Load a different session:", style={"color": "#F7F4F1"}))
                        ],
                        align="center",
                        justify="start",
                        style={"margin-bottom": "5px"}
                    )
                ]
            ),
            dbc.Row(
                [
                    dbc.Col(html.Label("Event:", style={"color": "#F7F4F1"}), lg=3),
                    dbc.Col(dbc.Select(id="event_select", size="sm"), lg=9)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            ),
            dbc.Row(
                [
                    dbc.Col(html.Label("Session:", style={"color": "#F7F4F1"}), lg=3),
                    dbc.Col(dbc.Select(id="session_select", size="sm"), lg=9)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            )
            ,dbc.Row(
                [
                    dbc.Col(dbc.Button(children=["Load session"], id="load_button"), lg=6),
                ],
                align="center",
                justify="start",
                style={"margin-bottom": "5px"}
            )
        ]
    ),
    html.Div(
        id="dashboard_div",
        hidden=True,
        children=[
            html.Div(
                [
                    dbc.Row(
                        [
                            dbc.Col(dbc.Button("Filters", id="open_parameters_button", color="secondary", style={"margin-left": "10px"}), lg=2),
                            dbc.Col(html.H1(id="dashboard_heading", style={"font-weight": "600"}), lg=10)
                        ],
                        align="center", justify="end"
                    ),
                ],
                style={"background-color": "#FF1E00"}
            ),
            dbc.Row(
                [
                    dbc.Col(dcc.Graph(id="lap_plot", config={"displayModeBar": False}), lg=8),
                    dbc.Col(dcc.Graph(id="track_map", config={"displayModeBar": False}, clear_on_unhover=True), lg=4)
                ],
                align="center", justify="evenly"
            ),
            dbc.Row(
                [
                    dbc.Col(dcc.Graph(id="stint_graph", config={"displayModeBar": False}), lg=4),
                    dbc.Col(dcc.Graph(id="inputs_graph", config={"displayModeBar": False}), lg=7),
                    dbc.Col(
                        html.Div(
                            id="input_trace_selector_div",
                            hidden=True,
                            children=[
                                dbc.Checklist(
                                    id="input_trace_selector", 
                                    options=[
                                        {"label": "RPM", "value": "RPM"},
                                        {"label": "Speed", "value": "Speed"},
                                        {"label": "Gear", "value": "Gear"},
                                        {"label": "Brake", "value": "Brake"}
                                    ], 
                                    value=["RPM", "Speed", "Gear", "Brake"], 
                                    inline=False
                                )
                            ]
                        ),
                        lg=1,
                        align="center"
                    )
                ]
            ),
            dbc.Row(
                [
                    dbc.Col(dbc.Button(id="open_conditions_button", children="Open timeline"), lg=1)
                ],
                align="center",
                justify="center"
            ),
        ]
    ),
    dbc.Offcanvas(
        id="conditions_panel",
        is_open=False,
        close_button=False,
        scrollable=True,
        placement="bottom",
        style={"height": 300},
        children=[
            dbc.Row(
                [
                    dbc.Col(html.P("Blah blah blah blah blah blah blah blah blah blah blah blah blah", style={"color": "#F7F4F1"}), lg=2),
                    dbc.Col(dcc.Graph(id="conditions_plot", config={"displayModeBar": False, "responsive": False}), lg=10)
                ],
                align="start",
                justify="center"
            )
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

