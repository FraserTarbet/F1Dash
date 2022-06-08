from dash import dcc, html
import dash_bootstrap_components as dbc

light_version = None
allow_zones = None

heights_dict = {
    "desktop": {
        "headings_div": "100px",
        "visuals_div": "90vh",
        "visuals_upper": "40vh",
        "visuals_lower": "38vh",
        "conditions_offcanvas": "48vh",
        "conditions_plot": "40vh"
    },
    "mobile": {
        "lap_plot": "60vw",
        "stint_graph": "50vw",
        "track_map": "60vw",
        "track_map_readout": "10vw",
        "inputs_graph": "60vw",
        "inputs_selector": "20vw"
    }
}

abstract_text = [
    html.P(
        [
            html.Br(),
            html.B("Who is fastest? Where are they fastest, and when?"),
            html.Br(),
            html.Br(),
            """
                This dashboard has been designed to explore these questions for any session in a Formula One race weekend.
            """,
            html.Br(),
            html.Br(),
            """
                For information on methodology, caveats, sources, and all code, please see the 
            """,
            html.A("F1Dash GitHub repository", href="https://github.com/FraserTarbet/F1Dash", target="_blank"),
            ".",
            html.Br(),
            html.Br(),
            """
                Select an event and session below to begin.
            """
        ]
    )
]

short_abstract_text = [
    """
        For information on methodology, caveats, sources, and all code, please see the 
    """,
    html.A("F1Dash GitHub repository", href="https://github.com/FraserTarbet/F1Dash", target="_blank"),
    "."
]

patience_text = [
    "Note: It may take a short time for a new session to load if it has not been queried recently by any users."
]

hints_text = [
    html.H5("Tips:"),
    html.Ul([
        html.Li("Select points in the scatter plot and track map to cross filter other visuals."),
        html.Li("Drag or shift and click to select multiple points (disabled on mobile devices)."),
        html.Li("Double click anywhere in the visual to clear the current selection.")
    ])
]

conditions_text = [
    html.H5("Session Timeline:"),
    html.Br(),
    "Click and drag on this chart to filter the dashboard to the selected session time period.",
    html.Br(),
    "Double click to clear the filter."
]

parameters_panel_children = [
    dbc.Row(
        [
            dbc.Col(html.H3("F1Dash", style={"color": "#FF1E00"}), xs=12)
        ],
        justify="end"
    ),
    html.Div(
        id="abstract_div",
        children=[
            dbc.Row(
                [
                    dbc.Col(html.P(abstract_text), style={"color": "#F7F4F1"})
                ]
            ),
            dbc.Row(
                [
                    html.Hr(style={"color": "#F7F4F1"})
                ]
            ),
        ]
    ),
    html.Div(
        id="filters_div",
        hidden=True,
        children=[
            html.Br(),
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
                    dbc.Col(html.Label("Teams:", style={"color": "#F7F4F1"}), xs=3),
                    dbc.Col(dcc.Dropdown(id="team_filter_dropdown", multi=True), xs=9)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            ),
            dbc.Row(
                [
                    dbc.Col(html.Label("Drivers:", style={"color": "#F7F4F1"}), xs=3),
                    dbc.Col(dcc.Dropdown(id="driver_filter_dropdown", multi=True), xs=9)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            ),
            dbc.Row(
                [
                    dbc.Col(html.Label("Compounds:", style={"color": "#F7F4F1"}), xs=3),
                    dbc.Col(dcc.Dropdown(id="compound_filter_dropdown", multi=True), xs=9)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            ),
            html.Div(
                hidden=True,
                children=dbc.Row(
                    [
                        dbc.Col(dbc.Label("Split laps by: ", style={"color": "#F7F4F1"}), xs=4),
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
            ),
            dbc.Row(
                [
                    dbc.Col(dbc.Label("Clean laps only (recommended): ", style={"color": "#F7F4F1"}), xs=9),
                    dbc.Col(dbc.Checkbox(id="clean_laps_checkbox", value=True), xs=3)
                ],
                align="center",
                style={"margin-bottom": "5px"}
            ),
            html.Div(
                id="hints_div",
                children=[
                    dbc.Row(
                        [
                            html.Hr(style={"color": "#F7F4F1"})
                        ]
                    ),
                    dbc.Row(
                        [
                            dbc.Col(html.P(hints_text), style={"color": "#F7F4F1"})
                        ]
                    )
                ]
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
            dbc.Col(html.Label("Event:", style={"color": "#F7F4F1"}), xs=3),
            dbc.Col(dbc.Select(id="event_select", size="sm"), xs=9)
        ],
        align="center",
        style={"margin-bottom": "5px"}
    ),
    dbc.Row(
        [
            dbc.Col(html.Label("Session:", style={"color": "#F7F4F1"}), xs=3),
            dbc.Col(dbc.Select(id="session_select", size="sm"), xs=9)
        ],
        align="center",
        style={"margin-bottom": "5px"}
    )
    ,dbc.Row(
        [
            dbc.Col(dbc.Button(children=["Load session"], id="load_button"), xs=6),
        ],
        align="center",
        justify="start",
        style={"margin-bottom": "5px"}
    )
    ,dbc.Row(
        [
            dbc.Col(html.P(patience_text), style={"color": "#F7F4F1", "font-size": "0.75rem"})
        ]
    )
]



# Layouts for mobile / non-mobile devices, to be picked by initial dash callback on client load

layout_desktop = [
    dbc.Offcanvas(
        id="parameters_panel",
        is_open=True,
        backdrop="static",
        close_button=False,
        scrollable=True,
        children=parameters_panel_children
    ),
    html.Div(
        id="dashboard_div",
        hidden=True,
        children=[
            html.Div(
                style={"height": heights_dict["desktop"]["visuals_div"]},
                children=[
                    html.Div(
                        style={"height": heights_dict["desktop"]["headings_div"]},
                        children=[
                            dbc.Row(
                                [
                                    dbc.Col(html.H1(id="upper_heading"), xs=12)
                                ],
                                align="center", justify="start"
                            ),
                            dbc.Row(
                                [
                                    dbc.Col(html.H2(id="lower_heading"), xs=12)
                                ]
                            ),
                        ]
                    ),
                    dbc.Row(
                        [
                            dbc.Col(
                                [
                                    dcc.Graph(id="lap_plot", config={"displayModeBar": False}, style={"height": heights_dict["desktop"]["visuals_upper"]}),
                                    html.Div(dcc.Loading(id="lap_plot_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                                ], xs=8
                            ),
                            dbc.Col(
                                [
                                    dcc.Graph(
                                        id="track_map", 
                                        config={"displayModeBar": False}, 
                                        style={
                                            "height": heights_dict["desktop"]["visuals_upper"], 
                                            "width": heights_dict["desktop"]["visuals_upper"]
                                        },
                                        clear_on_unhover=True
                                    ),
                                    html.Div(dcc.Loading(id="track_map_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                                ],
                                xs=2
                            ),
                            dbc.Col(html.Div(id="track_map_readout", style={"font-size": "0.70rem", "float": "right"}), align="start", xs=2)
                        ],
                        align="center", justify="evenly"
                    ),
                    dbc.Row(
                        [
                            dbc.Col(
                                [
                                    dcc.Graph(id="stint_graph", config={"displayModeBar": False}, style={"height": heights_dict["desktop"]["visuals_lower"]}),
                                    html.Div(dcc.Loading(id="stint_graph_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                                ],
                                xs=5
                            ),
                            dbc.Col(
                                [
                                    dcc.Graph(id="inputs_graph", config={"displayModeBar": False}, style={"height": heights_dict["desktop"]["visuals_lower"]}),
                                    html.Div(dcc.Loading(id="inputs_graph_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                                ], 
                                xs=6
                            ),
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
                                                {"label": "Throttle", "value": "Throttle"},
                                                {"label": "Brake", "value": "Brake"}
                                            ], 
                                            value=["RPM", "Speed", "Gear", "Throttle", "Brake"], 
                                            inline=False
                                        )
                                    ]
                                ),
                                xs=1,
                                align="center"
                            )
                        ],
                    ),
                ]
            ),
            html.Hr(),
            html.Footer(
                children=[
                    dbc.Row(
                        [
                            dbc.Col(dbc.Button("Filters", id="open_parameters_button", style={"margin-left": "10px"}), xs=5),
                            dbc.Col(dbc.Button(id="open_conditions_button", children="Open timeline"), xs=2),
                            dbc.Col(html.P(short_abstract_text), style={"font-size": "0.9rem"}, xs=5)
                        ],
                        align="start",
                        justify="start"
                    ),
                ]
            )
        ]
    ),
    dbc.Offcanvas(
        id="conditions_panel",
        is_open=False,
        close_button=False,
        scrollable=True,
        placement="bottom",
        style={"height": heights_dict["desktop"]["conditions_offcanvas"]},
        children=[
            dbc.Row(
                [
                    dbc.Col(html.P(conditions_text, style={"color": "#F7F4F1", "align": "center"}), xs=2),
                    dbc.Col(dcc.Graph(id="conditions_plot", config={"displayModeBar": False}, style={"height": heights_dict["desktop"]["conditions_plot"]}), xs=10)
                ],
                align="start",
                justify="center"
            )
        ]
    )
]



layout_mobile = [
    dbc.Offcanvas(
        id="parameters_panel",
        is_open=True,
        backdrop="static",
        close_button=False,
        scrollable=True,
        children=parameters_panel_children,
        style={"max-width": "80vw", "font-size": "0.75rem"}
    ),
    html.Div(
        id="dashboard_div",
        hidden=True,
        children=[
            html.Div(
                id="visuals_div",
                children=[
                    html.Div(
                        id="headings_div",
                        children=[
                            html.Div(id="upper_heading", hidden=True),
                            dbc.Row(dbc.Col(html.H1(id="lower_heading"), xs=12)),
                            html.Hr(),
                            dbc.Row(
                                [
                                    dbc.Col(dbc.Button(id="open_parameters_button", children="Open Filters", size="sm"), xs=4),
                                    dbc.Col(html.P(short_abstract_text, style={"font-size": "0.75rem"}), xs=8)
                                ]
                            )
                        ]
                    ),
                    dbc.Row(
                        dbc.Col(
                            [
                                dcc.Graph(id="lap_plot", config={"displayModeBar": False}, style={"height": heights_dict["mobile"]["lap_plot"]}),
                                html.Div(dcc.Loading(id="lap_plot_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                            ],
                            xs=12
                        )                      
                    ),
                    dbc.Row(
                        dbc.Col(
                            [
                                dcc.Graph(id="stint_graph", config={"displayModeBar": False}, style={"height": heights_dict["mobile"]["stint_graph"]}),
                                html.Div(dcc.Loading(id="stint_graph_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                            ],
                            xs=12
                        )
                    ),
                    dbc.Row(
                        [
                            dbc.Col(
                                [
                                    dcc.Graph(
                                        id="track_map", 
                                        config={"displayModeBar": False}, 
                                        style={
                                            "height": heights_dict["mobile"]["track_map"], 
                                            "width": heights_dict["mobile"]["track_map"]
                                        },
                                        clear_on_unhover=True
                                    ),
                                    html.Div(dcc.Loading(id="track_map_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                                ],
                                xs=7
                            ),
                            dbc.Col(html.Div(id="track_map_readout", style={"font-size": "0.60rem"}), align="start", xs=5)
                        ],
                        justify="start"
                    ),
                    dbc.Row(
                        [
                            dbc.Col(
                                [
                                    dcc.Graph(id="inputs_graph", config={"displayModeBar": False}, style={"height": heights_dict["mobile"]["inputs_graph"]}),
                                    html.Div(dcc.Loading(id="inputs_graph_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                                ], 
                                xs=12
                            )
                        ]
                    ),
                    dbc.Row(
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
                                            {"label": "Throttle", "value": "Throttle"},
                                            {"label": "Brake", "value": "Brake"}
                                        ], 
                                        value=["RPM", "Speed", "Gear", "Throttle", "Brake"], 
                                        inline=True,
                                        style={"font-size": "0.8rem"}
                                    )
                                ]
                            ),
                            xs=12,
                            align="center"
                        )
                    )
                ]
            ),
            html.Div(
                hidden=True,
                children=[
                    dbc.Button(id="open_conditions_button"),
                    dbc.Offcanvas(
                        id="conditions_panel",
                        is_open=False,
                        children=[
                            dcc.Graph(id="conditions_plot")
                        ]
                    )
                ]
            )
        ]
    )

]


layout_desktop_light = [
    dbc.Offcanvas(
        id="parameters_panel",
        is_open=True,
        backdrop="static",
        close_button=False,
        scrollable=True,
        children=parameters_panel_children
    ),
    html.Div(
        id="dashboard_div",
        hidden=True,
        children=[
            html.Div(
                style={"height": heights_dict["desktop"]["visuals_div"]},
                children=[
                    html.Div(
                        style={"height": heights_dict["desktop"]["headings_div"]},
                        children=[
                            dbc.Row(
                                [
                                    dbc.Col(html.H1(id="upper_heading"), xs=12)
                                ],
                                align="center", justify="start"
                            ),
                            dbc.Row(
                                [
                                    dbc.Col(html.H2(id="lower_heading"), xs=12)
                                ]
                            ),
                        ]
                    ),
                    dbc.Row(
                        [
                            dbc.Col(
                                [
                                    dcc.Graph(id="lap_plot", config={"displayModeBar": False}, style={"height": heights_dict["desktop"]["visuals_upper"]}),
                                    html.Div(dcc.Loading(id="lap_plot_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                                ], xs=12
                            )
                        ],
                        align="center", justify="evenly"
                    ),
                    dbc.Row(
                        [
                            dbc.Col(
                                [
                                    dcc.Graph(id="stint_graph", config={"displayModeBar": False}, style={"height": heights_dict["desktop"]["visuals_lower"]}),
                                    html.Div(dcc.Loading(id="stint_graph_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                                ],
                                xs=6
                            ),
                            dbc.Col(
                                [
                                    dcc.Graph(
                                        id="track_map", 
                                        config={"displayModeBar": False}, 
                                        style={
                                            "height": heights_dict["desktop"]["visuals_lower"], 
                                            "width": heights_dict["desktop"]["visuals_lower"]
                                        },
                                        clear_on_unhover=True
                                    ),
                                    html.Div(dcc.Loading(id="track_map_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                                ],
                                xs=2
                            ),
                            dbc.Col(
                                html.Div(id="track_map_readout", style={"font-size": "0.7rem", "margin-left": "20px"}), 
                                align="start", 
                                xs=2
                            )
                            ,html.Div(
                                hidden=True, 
                                children=[
                                    dcc.Graph(id="inputs_graph"), 
                                    html.Div(id="input_trace_selector_div"), 
                                    dbc.Checklist(id="input_trace_selector"),
                                    dcc.Loading(id="inputs_graph_loading")
                                ]
                            )
                        ],
                        justify="between"
                    ),
                ]
            ),
            html.Hr(),
            html.Footer(
                children=[
                    dbc.Row(
                        [
                            dbc.Col(dbc.Button("Filters", id="open_parameters_button", style={"margin-left": "10px"}), xs=5),
                            dbc.Col(dbc.Button(id="open_conditions_button", children="Open timeline"), xs=2),
                            dbc.Col(html.P(short_abstract_text), style={"font-size": "0.9rem"}, xs=5)
                        ],
                        align="start",
                        justify="start"
                    ),
                ]
            )
        ]
    ),
    dbc.Offcanvas(
        id="conditions_panel",
        is_open=False,
        close_button=False,
        scrollable=True,
        placement="bottom",
        style={"height": heights_dict["desktop"]["conditions_offcanvas"]},
        children=[
            dbc.Row(
                [
                    dbc.Col(html.P(conditions_text, style={"color": "#F7F4F1", "align": "center"}), xs=2),
                    dbc.Col(dcc.Graph(id="conditions_plot", config={"displayModeBar": False}, style={"height": heights_dict["desktop"]["conditions_plot"]}), xs=10)
                ],
                align="start",
                justify="center"
            )
        ]
    )
]


layout_mobile_light = [
    dbc.Offcanvas(
        id="parameters_panel",
        is_open=True,
        backdrop="static",
        close_button=False,
        scrollable=True,
        children=parameters_panel_children,
        style={"max-width": "80vw", "font-size": "0.75rem"}
    ),
    html.Div(
        id="dashboard_div",
        hidden=True,
        children=[
            html.Div(
                id="visuals_div",
                children=[
                    html.Div(
                        id="headings_div",
                        children=[
                            html.Div(id="upper_heading", hidden=True),
                            dbc.Row(dbc.Col(html.H1(id="lower_heading"), xs=12)),
                            html.Hr(),
                            dbc.Row(
                                [
                                    dbc.Col(dbc.Button(id="open_parameters_button", children="Open Filters", size="sm"), xs=4),
                                    dbc.Col(html.P(short_abstract_text, style={"font-size": "0.75rem"}), xs=8)
                                ]
                            )
                        ]
                    ),
                    dbc.Row(
                        dbc.Col(
                            [
                                dcc.Graph(id="lap_plot", config={"displayModeBar": False}, style={"height": heights_dict["mobile"]["lap_plot"]}),
                                html.Div(dcc.Loading(id="lap_plot_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                            ],
                            xs=12
                        )                      
                    ),
                    dbc.Row(
                        dbc.Col(
                            [
                                dcc.Graph(id="stint_graph", config={"displayModeBar": False}, style={"height": heights_dict["mobile"]["stint_graph"]}),
                                html.Div(dcc.Loading(id="stint_graph_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                            ],
                            xs=12
                        )
                    ),
                    dbc.Row(
                        [
                            dbc.Col(
                                [
                                    dcc.Graph(
                                        id="track_map", 
                                        config={"displayModeBar": False}, 
                                        style={
                                            "height": heights_dict["mobile"]["track_map"], 
                                            "width": heights_dict["mobile"]["track_map"]
                                        },
                                        clear_on_unhover=True
                                    ),
                                    html.Div(dcc.Loading(id="track_map_loading", type="circle", color="#FF1E00", style={"margin-top": "-30vh"}), style={"height": "0px"})
                                ],
                                xs=7
                            ),
                            dbc.Col(html.Div(id="track_map_readout", style={"font-size": "0.60rem"}), align="start", xs=5)
                        ],
                        justify="start"
                    ),
                    html.Div(
                        hidden=True,
                        children=[
                            dcc.Graph(id="inputs_graph"), 
                            html.Div(id="input_trace_selector_div"), 
                            dbc.Checklist(id="input_trace_selector"),
                            dcc.Loading(id="inputs_graph_loading")
                        ]
                    )
                ]
            ),
            html.Div(
                hidden=True,
                children=[
                    dbc.Button(id="open_conditions_button"),
                    dbc.Offcanvas(
                        id="conditions_panel",
                        is_open=False,
                        children=[
                            dcc.Graph(id="conditions_plot")
                        ]
                    )
                ]
            )
        ]
    )

]