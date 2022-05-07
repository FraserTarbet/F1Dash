import plotly.graph_objects as go
import pandas as pd
from dash import html


def get_figure(client_info):
    # Returns a consistent starting point for each visual
    fig = go.Figure()
    fig.update_layout(
        {
            "plot_bgcolor": "rgba(0, 0, 0, 0)",
            "paper_bgcolor": "rgba(0, 0, 0, 0)"
        },
        font_color="#15151E",
        dragmode="lasso",
        clickmode="event+select",
        font_family="'Titillium Web', Arial",
        title_font_size=20,
        title_x=0,
        margin={
            "l": 10,
            "r": 10,
            "t": 50,
            "b": 10
        }
    )

    fig.update_xaxes(
        gridcolor="#B8B8BB",
        fixedrange=True
    )
    fig.update_yaxes(
        gridcolor="#15151E",
        fixedrange=True
    )

    if client_info["isMobile"]:
        # Disable more functionality
        fig.update_layout(
            dragmode=False
        )

    client_height = client_info["height"]
    # Dynamically size figure heights for screen sizes

    return fig


def empty_figure(fig, text="No data"):
    # Returns placeholder figure when no data is available (on initiate or when conflicting filters have been applied)
    fig.add_annotation(
            text=text,
            xref="paper",
            yref="paper",
            x=0.5,
            y=0.5,
            showarrow=False
        )
    fig.update_layout(
        font_color = "rgb(175, 175, 175)"
    )
    fig.update_xaxes(
        visible=False
    )
    fig.update_yaxes(
        visible=False
    )

    return fig


def filter_data(data, filter_dict, ignore=[]):

    # Loop through filters and filter dataframe by each
    for field in filter_dict:
        if field == "TimeFilter" and "SessionTime" in data.columns and field not in ignore:
            # Handle time filtering here
            time_min, time_max = filter_dict[field]
            data = data[(data["SessionTime"] >= time_min) & (data["SessionTime"] <= time_max)]
        else:
            if field in data.columns and field not in ignore:
                data = data[(data[field].isin(filter_dict[field]))]

    return data


def filter_exists(filter_dict, filter):

    # Determine whether a filter exists for a given field. Used to work out e.g. whether to use sector- or zone-level dataset.
    if filter in filter_dict:
            return True
    return False


def filter_values(filter_dict, filter):

    # Return values for a given filter
    if filter in filter_dict:
        return filter_dict[filter]
    else:
        return []


def get_filter_options(data, filter_dict, return_fields_tuple, ignore=[]):

    # Get valid filter options based on existing top-level filters. Used by filters, not data visuals.
    # Returns a list of dicts in shape [{label: value}] for multi-select dropdowns

    if not isinstance(data, pd.DataFrame):
        data = pd.DataFrame(data)

    for field in filter_dict:
        if field in data.columns and field not in ignore:
            data = data[(data[field].isin(filter_dict[field]))]

    label_field, value_field = return_fields_tuple
    if label_field == value_field:
        data = data[[label_field]].drop_duplicates()
        data.rename(columns={label_field: "label"}, inplace=True)
        data["value"] = data["label"]
    else:
        data = data[[label_field, value_field]].drop_duplicates()
        data.rename(columns={label_field: "label", value_field: "value"}, inplace=True)

    options_list = data.to_dict("records")

    return options_list


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


def get_dashboard_headings(events_and_sessions, loaded_event_id, loaded_session_name):
    # Returns two headings for top of dashboard
    if not isinstance(events_and_sessions, pd.DataFrame):
        events_and_sessions = pd.DataFrame(events_and_sessions)

    session_row = events_and_sessions[(events_and_sessions["EventId"] == int(loaded_event_id)) & (events_and_sessions["SessionName"] == loaded_session_name)]
    upper_heading = session_row["OfficialEventName"].iloc[0]
    lower_heading = f"{session_row['EventName'].iloc[0]}: {session_row['SessionName'].iloc[0]}"

    return (upper_heading, lower_heading)


def build_lap_plot(data_dict, filters, client_info):

    # Plot of lap times, banded by team -> driver -> stint
    # Not filtered by laps or stints

    fig = get_figure(client_info)

    if data_dict is None:
        fig = empty_figure(fig)
        return fig

    if filter_exists(filters, "SectorNumber"):
        data = data_dict["sector_times"].copy()
        time_field = "SectorTime"
        title_measure = "Sector"
        title_values = filter_values(filters, "SectorNumber")
    elif filter_exists(filters, "ZoneNumber"):
        data = data_dict["zone_times"].copy()
        time_field = "ZoneTime"
        title_measure = "Zone"
        title_values = filter_values(filters, "ZoneNumber")
    else:
        data = data_dict["lap_times"].copy()
        time_field = "LapTime"
        title_measure = "Lap"
        title_values = []

    title_values_string = ""
    if title_values != []:
        title_values_string += f"for {title_measure}"
        if len(title_values) > 1: title_values_string += "s" 
        title_values_string += " "
        for i, value in enumerate(title_values):
            title_values_string += str(value)
            if len(title_values) > i + 1: title_values_string += ", "
        title_values_string += " per Lap"

    if filter_exists(filters, "LapId"):
        subtitle = "<br><sup>Double click to clear lap selection</sup>"
    else:
        subtitle = ""

    title = f"<b>{title_measure} Times </b>{title_values_string}{subtitle}"
    fig.update_layout(
        title_text = title
    )

    data = filter_data(data, filters, ignore=["LapId", "StintId"])
    if len(data) == 0:
        fig = empty_figure(fig)
        return fig

    data = data.groupby(["TeamOrder", "DriverOrder", "StintId", "StintNumber", 
                         "LapsInStint", "LapId", "Compound", "Driver", 
                         "Tla", "TeamColour"])[time_field].sum().reset_index()
    
    data.sort_values(["TeamOrder", "DriverOrder", "StintNumber", "LapsInStint"], inplace=True)    
    data.reset_index(drop=True, inplace=True)

    min_lap_time = data[time_field].min()
    max_lap_time = data[time_field].max()
    data["text"] = data[time_field].apply(lambda x: ns_to_delta_string(
        x if x == min_lap_time else x - min_lap_time, 
        True if x == min_lap_time else False)
        )
    
    compound_colour = {
        "Soft": "rgba(255, 30, 0, 1)",
        "Medium": "rgba(247, 225, 21, 1)",
        "Hard": "rgba(255, 255, 255, 1)",
        "Unknown": "rgba(0, 0, 0, 1)"
    }

    def colour_opacity(compound, lap_id):
        colour = compound_colour[compound]
        if filter_exists(filters, "LapId") and lap_id not in filter_values(filters, "LapId"):
            colour = colour.replace("1)", "0.25)")
        return colour

    data["colour"] = data.apply(lambda x: colour_opacity(x["Compound"], x["LapId"]), axis=1)
    
    if filter_exists(filters, "LapId"):
        data["line_colour"] = data["LapId"].apply(lambda x: "rgba(0, 0, 0, 1)" if x in filter_values(filters, "LapId") else "rgba(0, 0, 0, 0.25)")
    else:
        data["line_colour"] = "rgba(0, 0, 0, 1)"
 
    # Plot times
    fig.add_trace(
        go.Scatter(
            x=data.index,
            y=data[time_field],
            mode="markers",
            marker_color=data["colour"],
            marker_line_color=data["line_colour"],
            marker_line_width=1,
            hoverinfo="text",
            hovertext=data["text"],
            customdata=data[["StintId", "LapId"]].to_dict("records")
        )
    )

    # Band by team colours and add X axis labels
    tick_values = []
    tick_labels = []
    previous_driver_index_end = 0
    
    for driver in list(data["Driver"].unique()):
        #index_min = data.index[(data["Driver"] == driver)].min()
        x_min = previous_driver_index_end
        x_max = data.index[(data["Driver"] == driver)].max()
        x_mid = int(x_min + (x_max - x_min) / 2)
        previous_driver_index_end = x_max
        tick_values.append(x_mid)
        tick_labels.append(data[(data["Driver"] == driver)]["Tla"].iloc[0])
        
        fig.add_vrect(
            x0=x_min,
            x1=x_max,
            fillcolor="#" + data[(data["Driver"] == driver)]["TeamColour"].iloc[0],
            layer="below",
            opacity=1,
            line_width=0.5,
            line_color="#FFFFFF"
        )
        
    fig.update_xaxes(
        tickvals=tick_values,
        ticktext=tick_labels,
        range=[-2, len(data) + 2],
        zeroline=False,
        showgrid=False,
        linewidth=2,
        linecolor="#B8B8BB"
    )

    # Update Y axis
    tick_values, tick_labels = get_time_axis_ticks(min_lap_time, max_lap_time)
    fig.update_yaxes(
        tickvals=tick_values,
        ticktext=tick_labels,
        range=[max_lap_time + min_lap_time * 0.01, min_lap_time - min_lap_time * 0.01],
        zeroline=False,
        gridwidth=0.25,
        linewidth=2,
        linecolor="#B8B8BB"
    )

    fig.update_layout(
        showlegend=False
    )

    return fig


def build_track_map(data_dict, filters, client_info):

    # Fastest driver per sector or zone, or time vs session/personal best per sector or zone
    # Not filtered by sector or zone

    fig = get_figure(client_info)

    if data_dict is None:
        fig = empty_figure(fig)
        return fig, ""

    x_min = 0
    x_max = 0
    y_min = 0
    y_max = 0


    track_map = data_dict["track_map"]

    if filter_values(filters, "track_split")[0] == "zones":
        section_times = data_dict["zone_times"]
        section_identifier = "ZoneNumber"
        time_identifier = "ZoneTime"
        title_section = "Zone"
    else:
        section_times = data_dict["sector_times"]
        section_identifier = "SectorNumber"
        time_identifier = "SectorTime"
        title_section = "Sector"

    lap_id_filter = filter_values(filters, "LapId")
    if len(lap_id_filter) == 1:
        ignore = ["SectorNumber", "ZoneNumber", "LapId"]
    else:
        ignore = ["SectorNumber", "ZoneNumber"]

    section_times = filter_data(section_times, filters, ignore)
    
    section_times.reset_index(drop=True, inplace=True)
    sections = list(section_times[section_identifier].unique())

    colours = {
        "session_best": "#b228ad",
        "personal_best": "#0dcb0f",
        "no_improvement": "#f7e115"
    }

    # Readout data
    if any(field in ["SectorNumber", "ZoneNumber"] for field in filters):
        readout_data = filter_data(section_times, filters, ["LapId"])
        readout_time_identifier = time_identifier
    else:
        readout_data = filter_data(data_dict["lap_times"].copy(), filters, ignore)
        readout_time_identifier = "LapTime"
    
    if len(lap_id_filter) == 1:
        lap_id = lap_id_filter[0]
        lap_times = readout_data.groupby(["Tla", "LapId"])[readout_time_identifier].sum().reset_index()
        tla = lap_times[(lap_times["LapId"] == lap_id)]["Tla"].iloc[0]
        lap_time = lap_times[(lap_times["LapId"] == lap_id)][readout_time_identifier].iloc[0]
        personal_best = lap_times[(lap_times["Tla"] == tla)][readout_time_identifier].min()
        session_best = lap_times[readout_time_identifier].min()
        if lap_time == session_best:
            colour = colours["session_best"]
            readout_delta = []
        elif lap_time == personal_best:
            colour = colours["personal_best"]
            readout_delta = [ns_to_delta_string(lap_time - session_best) + " to session best"]
        else:
            colour = colours["no_improvement"]
            readout_delta = [
                ns_to_delta_string(lap_time - personal_best) + " to personal best",
                html.Br(),
                ns_to_delta_string(lap_time - session_best) + " to session best"
            ]
        readout = [
                "Total Time: ",
                html.Br(),
                html.Div(ns_to_delta_string(lap_time, True), style={"color": colour}),
                html.Br()
        ]
        readout.extend(readout_delta)

        
    else:
        readout_frame = filter_data(readout_data, filters).groupby(["Tla", "LapId", "TeamColour"])[readout_time_identifier].sum().reset_index()
        readout_driver_bests = readout_frame.groupby(["Tla", "TeamColour"])[readout_time_identifier].min().reset_index()
        readout_driver_bests.sort_values(readout_time_identifier, inplace=True)
        readout_dict_list = readout_driver_bests.to_dict("records")
        readout = []
        for i, tla_time in enumerate(readout_dict_list):
            time_delta = tla_time[readout_time_identifier] if i == 0 else tla_time[readout_time_identifier] - readout_dict_list[0][readout_time_identifier]
            readout.extend(
                [
                    #f"{tla_time['Tla']}: {ns_to_delta_string(time_delta, i == 0)}",
                    #html.Br()
                    html.Tr(
                        [
                            html.Td(str(i + 1), style={"color": "#15151E", "background-color": "#FFFFFF"}),
                            html.Td("▮", style={"color": "#" + tla_time["TeamColour"], "width": "10px"}),
                            html.Td(tla_time['Tla'], style={"color": "#FFFFFF"}),
                            html.Td(ns_to_delta_string(time_delta, i == 0), style={"color": "#FFFFFF", "background-color": "#555", "width": "80px"})
                        ],
                        style={"line-height": "0.8rem"}
                    )
                ]
            )
        readout = html.Table(readout, style={"background-color": "#15151E", "margin-top": "50px", "margin-left": "80px"})

    # Draw map
    for section in sections:
        track = track_map[(track_map[section_identifier]) == section].copy()
        track.sort_values("SampleId", inplace=True)

        driver_bests = section_times[(section_times[section_identifier] == section)].groupby(["Tla", "TeamColour"])[time_identifier].min().reset_index()
        driver_bests.sort_values(time_identifier, inplace=True)
        driver_bests.reset_index(drop=True, inplace=True)

        if filter_exists(filters, section_identifier) and section not in filter_values(filters, section_identifier):
            opacity = 0.5
        else:
            opacity = 1

        if len(lap_id_filter) == 1:
            # Show time vs session/personal bests per section

            lap_id = lap_id_filter[0]

            tla = section_times[(section_times["LapId"] == lap_id) & (section_times[section_identifier] == section)]["Tla"].iloc[0]
            section_time = section_times[(section_times["LapId"] == lap_id) & (section_times[section_identifier] == section)][time_identifier].iloc[0]
            personal_best = driver_bests[(driver_bests["Tla"] == tla)][time_identifier].iloc[0]
            session_best = driver_bests[time_identifier].min()

            if section_time == session_best:
                colour = colours["session_best"]
                hover_text = "Session best: " + ns_to_delta_string(section_time, True)
            elif section_time == personal_best:
                colour = colours["personal_best"]
                hover_text = f"Personal best, {ns_to_delta_string(section_time - session_best)} to session best"
            else:
                colour = colours["no_improvement"]
                hover_text = f"No improvement, {ns_to_delta_string(section_time - personal_best)} to personal best,<br>{ns_to_delta_string(section_time - session_best)} to session best"

            fig.add_trace(
                go.Scatter(
                    x=track["X"],
                    y=track["Y"],
                    mode="lines+markers",
                    marker_size=0.5,
                    hoverinfo="text",
                    hovertext=hover_text,
                    marker_color=colour,
                    opacity=opacity,
                    line_width=5,
                    line_shape="spline",
                    customdata=[{section_identifier: section}] * len(track)
                )
            )

        else:
            # Show best driver per section

            colour = "#" + driver_bests["TeamColour"].iloc[0]
            benchmark_time = driver_bests[time_identifier].iloc[0]
            hover_text = ""
            for i in range(0, min(len(driver_bests), 5)):
                tla = driver_bests["Tla"].iloc[i]
                if i == 0:
                    delta = ns_to_delta_string(benchmark_time, True)
                else:
                    delta = ns_to_delta_string(driver_bests[time_identifier].iloc[i] - benchmark_time)
                line =  f"{tla}: {delta}<br>"
                hover_text += line

            fig.add_trace(
                go.Scatter(
                    x=track["X"],
                    y=track["Y"],
                    mode="lines+markers",
                    marker_size=0.5,
                    hoverinfo="text",
                    hovertext=hover_text,
                    marker_color=colour,
                    opacity=opacity,
                    line_width=5,
                    line_shape="spline",
                    customdata=[{section_identifier: section}] * len(track)
                )
            )

    if len(filter_values(filters, "LapId")) == 1:
        lap_number = section_times[(section_times["LapId"] == lap_id)]["NumberOfLaps"].iloc[0]
        title_main = f"<b>{title_section} Times</b>, {tla} Lap {lap_number}"
    else:
        if filter_exists(filters, "LapId"):
            title_filter = ", selected Laps"
        else:
            title_filter = ""
        title_main = f"<b>Fastest Driver per {title_section}</b>{title_filter}"

    if filter_exists(filters, section_identifier):
        subtitle = f"<br><sup>Double click to clear {title_section.lower()} selection</sup>"
    else:
        subtitle = ""
    
    fig.update_layout(
        title_text=title_main + subtitle
    )

    x_min = track_map["X"].min()
    x_max = track_map["X"].max()
    y_min = track_map["Y"].min()
    y_max = track_map["Y"].max()

    # Extend X & Y axes a bit to fit whole map, also hide them
    x_centre = (x_min + x_max) / 2
    y_centre = (y_min + y_max) / 2
    axis_length = max(x_max - x_min, y_max - y_min)
    axis_length = axis_length * 1.05
    
    fig.update_xaxes(
        range=[x_centre - axis_length / 2, x_centre + axis_length / 2],
        visible=False
    )
    
    fig.update_yaxes(
        range=[y_centre - axis_length / 2, y_centre + axis_length / 2],
        visible=False
    )

    fig.update_layout(
        showlegend=False
    )

    return (
        fig,
        readout
    )

def build_stint_graph(data_dict, filters, client_info):

    # Lap/zone/sector times per driver over the session, or lap/zone/sector times per unique stint over stint laps
    # Not filtered by laps
    # Doesn't drive any crossfiltering

    fig = get_figure(client_info)

    if data_dict is None:
        fig = empty_figure(fig)
        return fig

    if filter_exists(filters, "SectorNumber"):
        data = data_dict["sector_times"].copy()
        time_field = "SectorTime"
        title_section = "Sector"
        title_values = filter_values(filters, "SectorNumber")
    elif filter_exists(filters, "ZoneNumber"):
        data = data_dict["zone_times"].copy()
        time_field = "ZoneTime"
        title_section = "Zone"
        title_values = filter_values(filters, "ZoneNumber")
    else:
        data = data_dict["lap_times"].copy()
        time_field = "LapTime"
        title_section = "Lap"
        title_values = []

    if filter_exists(filters, "StintId"):
        ignore = ["LapId", "TimeFilter"]
        title_over = "Stint"
    else:
        ignore = ["LapId"]
        title_over = "Session"
    
    data = filter_data(data, filters, ignore)
    if len(data) == 0:
        fig = empty_figure(fig)
        return fig

    title_values_string = ""
    if title_values != []:
        title_values_string += f"for {title_section}"
        if len(title_values) > 1: title_values_string += "s" 
        title_values_string += " "
        for i, value in enumerate(title_values):
            title_values_string += str(value)
            if len(title_values) > i + 1: title_values_string += ", "    

    title = f"<b>{title_section} Times over {title_over}</b> {title_values_string}"
    fig.update_layout(
        title_text=title
    )

    data = data.groupby(["TeamOrder", "DriverOrder", "NumberOfLaps", "StintId", "StintNumber", 
                         "LapsInStint", "LapId", "Compound", "Driver", 
                         "Tla", "TeamColour"])[time_field].sum().reset_index()

    data.sort_values(["TeamOrder", "DriverOrder", "NumberOfLaps"], inplace=True)  
    data.reset_index(drop=True, inplace=True)
    
    min_lap_time = data[time_field].min()
    max_lap_time = data[time_field].max()
    data["text"] = data[time_field].apply(lambda x: ns_to_delta_string(
        x if x == min_lap_time else x - min_lap_time, 
        True if x == min_lap_time else False)
        )
    
    # Trace per driver or stint
    stint_filtering = filter_exists(filters, "StintId") or filter_exists(filters, "Compound")
    if stint_filtering:
        x_field = "LapsInStint"
        x_title = "Stint Lap"
        trace_identifier = "StintId"
    else:
        x_field = "NumberOfLaps"
        x_title = "Lap"
        trace_identifier = "Driver"

    plotted_tlas = []
    plotted_teams = []
    
    for iterator in list(data[trace_identifier].unique()):        
        trace_data = data[(data[trace_identifier] == iterator)]
        colour = "#" + trace_data["TeamColour"].iloc[0]
        
        tla = trace_data["Tla"].iloc[0]
        team = trace_data["TeamOrder"].iloc[0]
        if tla in plotted_tlas or team in plotted_teams:
            dash_style = "dot"
        else:
            dash_style = "solid"
            plotted_tlas.append(tla)
            plotted_teams.append(team)
            
        trace_name = tla + " stint " + str(trace_data["StintNumber"].iloc[0]) if trace_identifier == "StintId" else tla
        
        fig.add_trace(
            go.Scatter(
                x=trace_data[x_field],
                y=trace_data[time_field],
                mode="lines",
                marker_color=colour,
                hoverinfo="text",
                hovertext=trace_data["Tla"] + ": " + trace_data["text"],
                line={"dash": dash_style},
                name=trace_name
            )
        )

    # Markers for crossfiltered laps
    filter_lap_ids = filter_values(filters, "LapId")
    if len(filter_lap_ids) > 0:
        for lap_id in filter_lap_ids:
            if lap_id in list(data["LapId"]):
                trace_data = data[(data["LapId"]) == lap_id]
                colour = "#" + trace_data["TeamColour"].iloc[0]
                fig.add_trace(
                    go.Scatter(
                        x=trace_data[x_field],
                        y=trace_data[time_field],
                        mode="markers",
                        marker_size=10,
                        marker_color=colour,
                        marker_line_width=1,
                        marker_line_color="rgb(255, 255, 255)",
                        hoverinfo="text",
                        hovertext=trace_data["Tla"] + ": " + trace_data["text"],
                        showlegend=False
                    )
                )
    
    # Update axes
    tick_values, tick_labels = get_time_axis_ticks(min_lap_time, max_lap_time)
    fig.update_yaxes(
        tickvals=tick_values,
        ticktext=tick_labels,
        range=[max_lap_time + min_lap_time * 0.01, min_lap_time - min_lap_time * 0.01],
        zeroline=False,
        gridwidth=0.2
    )
    fig.update_xaxes(
        title = x_title
    )

    return fig


def build_inputs_graph(data_dict, filters, client_info):

    # Car inputs over time for a maximum of two laps
    # Returns an extra boolean to indicate whether any data is being displayed

    fig = get_figure(client_info)

    if data_dict is None:
        fig = empty_figure(fig)
        return fig, False

    if filters["input_trace"] == []:
        fig = empty_figure(fig)
        return fig, True

    filtered_lap_ids = filter_values(filters, "LapId")
    if not 2 >= len(filtered_lap_ids) > 0:
        fig = empty_figure(fig, "Filter to one/two laps to view driver input telemetry")
        return fig, False

    data = data_dict["car_data"].copy()

    norms = {
        "RPM": (data["RPM"].min(), data["RPM"].max()),
        "Speed": (data["Speed"].min(), data["Speed"].max()),
        "Throttle": (data["Throttle"].min(), data["Throttle"].max()),
        "Gear": (data["Gear"].min(), data["Gear"].max())
    }

    data = filter_data(data, filters)

    traces_colours = {
        "RPM": "#FF1E00",
        "Speed": "#b228ad",
        "Brake": "#15151E",
        "Gear": "#0dcb0f",
        "Throttle": "#2972ed"
    }

    for trace in filters["input_trace"]:
        if trace == "Brake":
            data[trace] = data[trace].apply(lambda x: 1 if x == True else 0)
            data["text_" + trace] = data[trace].apply(lambda x: "Brake applied" if x == True else "Brake off")
        else:
            trace_min, trace_max = norms[trace]
            trace_range = trace_max - trace_min
            data["norm_" + trace] = data[trace].apply(lambda x: (x - trace_min) / trace_range)
            if trace == "Speed":
                data["text_" + trace] = data[trace].apply(lambda x: str(x) + " km/h")
            elif trace == "RPM":
                data["text_" + trace] = data[trace].apply(lambda x: str(x) + " RPM")
            elif trace == "Gear":
                data["text_" + trace] = data[trace].apply(lambda x: "Gear " + str(x))
            elif trace == "Throttle":
                data["text_" + trace] = data[trace].apply(lambda x: "Throttle: " + str(x))
            
    first_lap_start_time = 0
    max_lap_end_time = 0
    title_drivers = []
    title_laps = []
    for i, lap_id in enumerate(filtered_lap_ids):
        
        lap_data = data[(data["LapId"] == lap_id)].copy()
        lap_data.sort_values("SessionTime", inplace=True)
        
        legend_group = str(i)
        tla = lap_data["Tla"].iloc[0]
        lap_number = lap_data["NumberOfLaps"].iloc[0]
        legend_group_title = f"{tla} lap {lap_number}"

        title_drivers.append(tla)
        title_laps.append(lap_number)
        
        if i == 0: 
            first_lap_start_time = lap_data["SessionTime"].min()
            max_lap_end_time = lap_data["SessionTime"].max()
            time_offset = 0
            dash_style = "solid"
        else:
            time_offset = lap_data["SessionTime"].min() - first_lap_start_time
            max_lap_end_time = max(max_lap_end_time, lap_data["SessionTime"].max() - time_offset)
            dash_style = "dot"
            
        for trace in filters["input_trace"]:
            fig.add_trace(
                go.Scatter(
                    x=lap_data["SessionTime"] - time_offset,
                    y=lap_data["Brake"] if trace == "Brake" else lap_data["norm_" + trace],
                    mode="lines+markers",
                    marker_color=traces_colours[trace],
                    marker_size=0.5,
                    hoverinfo="text",
                    hovertext=lap_data["text_" + trace],
                    line={"dash": dash_style},
                    legendgroup=legend_group,
                    legendgrouptitle_text=legend_group_title,
                    name=trace
                )
            )

    # Hide axes
    fig.update_xaxes(
        showticklabels=False,
        showgrid=False,
        showline=True,
        linewidth=2,
        linecolor="#B8B8BB",
        title_text="Time",
        range=[first_lap_start_time, max_lap_end_time]
    )
    fig.update_yaxes(
        showticklabels=False,
        showgrid=False,
        showline=True,
        linewidth=2,
        linecolor="#B8B8BB",
        range=[0, 1.05]
    )
    
    # Get title
    if filter_exists(filters, "SectorNumber"):
        title_measure = "Sector"
        title_values = filter_values(filters, "SectorNumber")
    elif filter_exists(filters, "ZoneNumber"):
        title_measure = "Zone"
        title_values = filter_values(filters, "ZoneNumber")
    else:
        title_values = []

    title_values_string = ""
    if title_values != []:
        title_values_string += f", {title_measure}"
        if len(title_values) > 1: title_values_string += "s" 
        title_values_string += " "
        for i, value in enumerate(title_values):
            title_values_string += str(value)
            if len(title_values) > i + 1: title_values_string += ", "

    title = f"<b>Input Telemetry</b> for "
    for i, lap in enumerate(title_laps):
        if i > 0: title += " and "
        title += f"{title_drivers[i]} Lap {str(lap)}"
    title += title_values_string

    fig.update_layout(
        title_text=title,
        showlegend=True
    )

    return fig, True


def build_conditions_plot(data_dict, client_info):

    # Weather, track status, and track activity over total session time
    # Not crossfiltered by anything

    fig = get_figure(client_info)
    fig.update_layout(
        bargap=0,
        showlegend=False,
        selectdirection="h",
        clickmode="event",
        selectionrevision=False,
        font_color="#FFFFFF"
    )

    if data_dict is None:
        fig = empty_figure(fig)
        return fig

    data = data_dict["conditions_data"].copy()

    if len(data) == 0:
        fig = empty_figure(fig)
        return fig
    
    max_laps = float(data["Laps"].max())
    data["Laps"] = data["Laps"].apply(lambda x: x / max_laps)
    
    status_colours = {
        "AllClear": "#0dcb0f",
        "Red": "#FF1E00",
        "Yellow": "#f7e115",
        "SCDeployed": "#f56b0e",
        "VSCDeployed": "#b228ad"
    }

    metrics = {
        "Humidity": {
            "trace_type": "scatter",
            "axis_label": "Humidity",
            "hoverable": True, 
            "text_suffix": "%",
            "colour": "#b228ad"
        },
        "Rainfall": {
            "trace_type": "scatter",
            "axis_label": "Rain",
            "hoverable": False, 
            "text_suffix": "",
            "colour": "#2972ed"
        },
        "TrackTemp": {
            "trace_type": "annotation",
            "axis_label": "Temp (track)",
            "hoverable": False,
            "text_suffix": "°C"
        },
        "AirTemp": {
            "trace_type": "annotation",
            "axis_label": "Temp (air)",
            "hoverable": False,
            "text_suffix": "°C"
        },
        "WindSpeed": {
            "trace_type": "annotation",
            "axis_label": "Wind speed",
            "hoverable": False,
            "text_suffix": "kph"
        },
        "WindDirection": {
            "trace_type": "annotation",
            "axis_label": "Wind direction",
            "hoverable": False,
            "text_suffix": "°"
        },
        "Laps": {
            "trace_type": "scatter",
            "axis_label": "Track activity",
            "hoverable": False,
            "text_suffix": "",
            "colour": "#FF1E00"
        }
    }

    # Get evenly spaced samples of session time for annotations
    x_spacing = int(len(data) / 10)
    x_indices = list(range(int(x_spacing / 2), len(data), x_spacing))
    x_sampled_data = data[(data.index.isin(x_indices))]
    x_sampled_data.reset_index(drop=True, inplace=True)

    # Hover labels
    for metric in metrics:
        data["text_" + metric] = data[metric].apply(lambda x: str(x) + metrics[metric]["text_suffix"])

    # Traces
    y_values = []
    y_labels = []
    for y, metric in enumerate(metrics):
        metric_dict = metrics[metric]
        y_values.append(y + 0.5)
        y_labels.append(metric_dict["axis_label"])
        
        if metric_dict["trace_type"] == "scatter":
            fig.add_trace(
                go.Scatter(
                    x=data["SessionTime"],
                    y=data[metric] + y,
                    hoverinfo="text" if metric_dict["hoverable"] == True else "none",
                    hovertext=data["text_" + metric] if metric_dict["hoverable"] == True else "", 
                    marker_color=metric_dict["colour"],
                    fill="toself"
                )
            )
        elif metric_dict["trace_type"] == "annotation":
            for i in range(0, len(x_sampled_data)):
                fig.add_annotation(
                    x=x_sampled_data["SessionTime"].iloc[i],
                    y=y + 0.5,
                    text=data["text_" + metric].iloc[i],
                    showarrow=False
                )

    # Do track status separately
    line_y = max(y_values) + 1
    y_values.append(max(y_values) + 1)
    y_labels.append("Track status")

    for status in status_colours:
        trace_data = data[(data["TrackStatus"] == status)]
        fig.add_trace(
            go.Scatter(
                x=trace_data["SessionTime"],
                y=[line_y] * len(trace_data),
                mode="lines+markers",
                line_width=5,
                fill="toself",
                marker_color=status_colours[status],
                marker_size=0.5,
                hoverinfo="text",
                hovertext=status
            )
        )
    
    # Update axes
    fig.update_yaxes(
        tickvals = y_values,
        ticktext = y_labels,
        zeroline=False,
        showgrid=False,
        range = [0, len(y_values)]
    )
    fig.update_xaxes(
        visible=True,
        title_text="Time",
        range=[data["SessionTime"].min(), data["SessionTime"].max()],
        showticklabels=False,
        showgrid=False,
        showline=True
    )

    fig.update_layout(
        margin={"l":100, "r":100, "t":0, "b":0},
        dragmode="select"
    )

    return fig


def shade_conditions_plot(figure_state, filters):
    
    # Takes session time tuple from selectedData xaxis.range output and draws vrects either side

    # Build fig from existing dict, clear any existing shapes
    fig = go.Figure(figure_state)
    fig.layout.shapes = []

    # Get time filter values
    if len(filters) == 0:
        return fig

    filter_min, filter_max = filters["TimeFilter"]

    # Get session min and max times from arrays within fig (doesn't seem to be possible to get these from any simple fig.prop)
    x_values = figure_state["data"][0]["x"]
    x_min, x_max = (x_values[0], x_values[-1])

    # Draw shapes
    for x_values in [(x_min, filter_min), (filter_max, x_max)]:
        fig.add_vrect(
            x0=x_values[0],
            x1=x_values[1],
            fillcolor="rgb(175, 175, 175)",
            opacity=0.5,
            layer="above",
            line_width=0
        )

    return fig
    

def add_line_to_inputs_graph(figure_state, session_time):

    # Too slow to render in app. Maybe implement as part of a JS clientside callback?

    # Build fig from existing dict, clear any existing shapes
    fig = go.Figure(figure_state)
    fig.layout.shapes = []

    if session_time is None:
        return fig

    x_values = figure_state["data"][0]["x"]
    x_min, x_max = (x_values[0], x_values[-1])

    if not x_min <= session_time <= x_max:
        return fig

    fig.add_vline(
        x=session_time,
        line_color="rgba(255, 0, 255, 0.5)"
    )

    return fig