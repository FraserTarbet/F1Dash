from dash import dcc, html
import dash_bootstrap_components as dbc


# Layouts for mobile / non-mobile devices, to be picked by initial dash callback on client load

desktop = [
    dbc.Offcanvas(
        id="parameters_panel",
        title="Options",
        is_open=False,
        children=[
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
                    dbc.Col(dbc.Spinner(id="load_spinner"), lg=6)
                ],
                style={"margin-bottom": "5px"}
            )
        ]
    ),
    dbc.Row(
        [
            dbc.Col(dbc.Button("Options", id="parameters_button"), lg=1),
            dbc.Col(html.H1("Race name: Session name", id="dashboard_heading"), lg=11)
        ],
        align="center", justify="start"
    ),
    dbc.Row(
        dbc.Col(html.Div("Yeah yeah"))
    )
]


mobile = [
    html.Div("This is the mobile layout")
]