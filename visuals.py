import plotly.graph_objects as go
import pandas as pd


def get_figure(client_info):
    # Returns a consistent starting point for each visual
    fig = go.Figure()
    fig.update_layout(
        {
            "plot_bgcolor": "rgba(0, 0, 0, 0)",
            "paper_bgcolor": "rgba(0, 0, 0, 0)"
        },
        font_color="white",
        dragmode="select",
        clickmode="event+select"
    )

    if client_info["isMobile"]:
        # Disable more functionality
        pass
    else:
        pass

    client_height = client_info["height"]
    # Dynamically size figure heights for screen sizes

    return fig


def empty_figure(fig):
    # Returns placeholder figure when no data is available (on initiate or when conflicting filters have been applied)
    fig.add_annotation(
            text="No data",
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


def filter_data(data, filter_dict_list, ignore=[]):

    # Loop through filters and filter dataframe by each
    for filter_dict in filter_dict_list:
        for field in filter_dict:
            if field == "TimeFilter" and "SessionTime" in data.columns and field not in ignore:
                # Handle time filtering here
                time_min, time_max = filter_dict[field]
                data = data[(data["SessionTime"] >= time_min) & (data["SessionTime"] <= time_max)]
            else:
                if field in data.columns and field not in ignore:
                    data = data[(data[field].isin(filter_dict[field]))]

    return data


def filter_exists(filter_dict_list, filter):

    # Determine whether a filter exists for a given field. Used to work out e.g. whether to use sector- or zone-level dataset.
    for filter_dict in filter_dict_list:
        if filter in filter_dict:
            return True
    return False


def filter_values(filter_dict_list, filter):

    # Return values for a given filter
    for filter_dict in filter_dict_list:
        if filter in filter_dict:
            return filter_dict[filter]
    return []


def get_filter_options(data, top_filters_dict, return_fields_tuple, ignore=[]):

    # Get valid filter options based on existing top-level filters. Used by filters, not data visuals.
    # Returns a list of dicts in shape [{label: value}] for multi-select dropdowns

    for field in top_filters_dict:
        if field in data.columns and field not in ignore:
            data = data[(data[field].isin(top_filters_dict[field]))]

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
    elif filter_exists(filters, "ZoneNumber"):
        data = data_dict["zone_times"].copy()
        time_field = "ZoneTime"
    else:
        data = data_dict["lap_times"].copy()
        time_field = "LapTime"

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
        "SOFT": "rgba(255, 0, 0, 255)",
        "MEDIUM": "rgba(255, 191, 0, 255)",
        "HARD": "rgba(150, 150, 150, 255)",
        "UNKNOWN": "rgba(0, 0, 0, 255)"
    }
 
    # Plot times
    for compound in list(data["Compound"].unique()):
        trace_data = data[(data["Compound"] == compound)]
        fig.add_trace(
            go.Scatter(
                x=trace_data.index,
                y=trace_data[time_field],
                mode="markers",
                marker_color=compound_colour[compound],
                marker_line_width=1,
                marker_line_color="rgb(0, 0, 0)",
                hoverinfo="text",
                hovertext=trace_data["text"],
                customdata=trace_data[["StintId", "LapId"]].to_dict("records"),
                name=compound
            )
        )

    # Band by team colours and add X axis labels
    tick_values = []
    tick_labels = []
    
    for driver in list(data["Driver"].unique()):
        index_min = data.index[(data["Driver"] == driver)].min()
        index_max = data.index[(data["Driver"] == driver)].max()
        index_mid = int(index_min + (index_max - index_min) / 2)
        tick_values.append(index_mid)
        tick_labels.append(data[(data["Driver"] == driver)]["Tla"].iloc[0])
        
        fig.add_vrect(
            x0=index_min,
            x1=index_max,
            fillcolor="#" + data[(data["Driver"] == driver)]["TeamColour"].iloc[0],
            layer="below",
            opacity=0.8,
            line_width=0.5,
            line_color="rgb(0, 0, 0)"
        )
        
    fig.update_xaxes(
        tickvals=tick_values,
        ticktext=tick_labels,
        range=[-10, len(data) + 10],
        zeroline=False,
        showgrid=False
    )

    # Update Y axis
    tick_values, tick_labels = get_time_axis_ticks(min_lap_time, max_lap_time)
    fig.update_yaxes(
        tickvals=tick_values,
        ticktext=tick_labels,
        range=[max_lap_time + min_lap_time * 0.01, min_lap_time - min_lap_time * 0.01],
        zeroline=False,
        gridwidth=0.2,
        gridcolor="rgb(0, 0, 0)"
    )

    fig.update_layout(
        showlegend=False
    )

    return fig


def build_track_map(data_dict, filters, client_info):

    # Fastest driver per sector or zone, or brake/gear per sector or zone
    # Not filtered by sector or zone

    fig = get_figure(client_info)

    if data_dict is None:
        fig = empty_figure(fig)
        return fig

    data = data_dict["position_data"].copy()

    data = filter_data(data, filters)

    if len(data) == 0:
        fig = empty_figure(fig)
        return fig

    if len(filter_values(filters, "LapId")) == 1:
        # Braking and gear changes
        chart_data = data[["LapId", "SessionTime", "X", "Y", "BrakeOrGearId", "BrakeOrGear", "CarSampleId"]]
        trace_ids = list(chart_data["BrakeOrGearId"].unique())

        colours = {
            -1: "rgb(255, 0, 0)",
            0: "rgb(30, 30, 30)",
            1: "rgb(60, 60, 60)",
            2: "rgb(90, 90, 90)",
            3: "rgb(120, 120, 120)",
            4: "rgb(150, 150, 150)",
            5: "rgb(180, 180, 180)",
            6: "rgb(210, 210, 210)",
            7: "rgb(230, 230, 230)",
            8: "rgb(255, 255, 255)",
        }

        for brake_or_gear_id in trace_ids:
            trace_data = chart_data[(chart_data["BrakeOrGearId"] == brake_or_gear_id)].copy()
            trace_data.sort_values("SessionTime", inplace=True)
            fig.add_trace(
                go.Scatter(
                    x=trace_data["X"],
                    y=trace_data["Y"],
                    mode="lines+markers",
                    marker_size=0.5,
                    marker_color=colours[trace_data["BrakeOrGear"].iloc[0]],
                    hoverinfo="text",
                    hovertext="Brake" if trace_data["BrakeOrGear"].iloc[0] == -1 else "Gear " + str(trace_data["BrakeOrGear"].iloc[0]),
                    line_width=5,
                    line_shape="spline",
                    customdata=trace_data[["LapId", "CarSampleId"]].to_dict("records") 
                    # Use time since start of lap instead of sample id?
                )
            )

    else:
        # Fastest driver per zone/sector
        track_map = data_dict["track_map"]

        if filter_values(filters, "track_split")[0] == "zones":
            section_times = data_dict["zone_times"]
            section_identifier = "ZoneNumber"
            time_identifier = "ZoneTime"
        else:
            section_times = data_dict["sector_times"]
            section_identifier = "SectorNumber"
            time_identifier = "SectorTime"

        section_times = filter_data(section_times, filters, ignore=["SectorNumber", "ZoneNumber"])
        
        section_times.reset_index(drop=True, inplace=True)
        sections = list(section_times[section_identifier].unique())

        for section in sections:
            index_min = section_times[(section_times[section_identifier] == section)][time_identifier].idxmin()
            Tla = section_times["Tla"].iloc[index_min]
            colour = "#" + section_times["TeamColour"].iloc[index_min]
            track = track_map[(track_map[section_identifier]) == section].copy()
            track.sort_values("SampleId", inplace=True)
            
            fig.add_trace(
                go.Scatter(
                    x=track["X"],
                    y=track["Y"],
                    mode="lines+markers",
                    marker_size=0.5,
                    hoverinfo="text",
                    hovertext=Tla, # Show time deltas?
                    marker_color=colour,
                    line_width=5,
                    line_shape="spline"
                    # Make custom data sector / zone number, for crossfiltering (and highlighting on inputs?)
                )
            )

    # Extend X & Y axes a bit to fit whole map, also hide them
    xmin = data["X"].min()
    xmax = data["X"].max()
    ymin = data["Y"].min()
    ymax = data["Y"].max()
    x_centre = (xmin + xmax) / 2
    y_centre = (ymin + ymax) / 2
    axis_length = max(xmax - xmin, ymax - ymin)
    axis_length = axis_length * 1.05
    
    fig.update_xaxes(
        range=[x_centre - axis_length / 2, x_centre + axis_length / 2],
        visible=False
    )
    
    fig.update_yaxes(
        range=[y_centre - axis_length / 2, y_centre + axis_length / 2],
        visible=False
    )

    return fig


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
    elif filter_exists(filters, "ZoneNumber"):
        data = data_dict["zone_times"].copy()
        time_field = "ZoneTime"
    else:
        data = data_dict["lap_times"].copy()
        time_field = "LapTime"

    data = filter_data(data, filters, ignore=["LapId"])
    if len(data) == 0:
        fig = empty_figure(fig)
        return fig

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
        gridwidth=0.2,
        gridcolor="rgb(0, 0, 0)"
    )
    fig.update_xaxes(
        title = x_title
    )

    return fig


def build_inputs_graph(data_dict, filters, client_info):

    # Car inputs over time for a maximum of two laps

    fig = get_figure(client_info)

    return fig


def build_conditions_plot(data_dict, client_info):

    # Weather, track status, and track activity over total session time
    # Not crossfiltered by anything

    fig = get_figure(client_info)
    fig.update_layout(
        bargap=0,
        showlegend=False,
        selectdirection="h",
        clickmode="event",
        selectionrevision=False
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
        "AllClear": "rgb(0, 255, 0)",
        "Red": "rgb(255, 0, 0)",
        "Yellow": "rgb(255, 191, 0)",
        "SCDeployed": "rgb(242, 140, 40)",
        "VSCDeployed": "rgb(191, 64, 191)"
    }

    metrics = {
        "Humidity": {
            "trace_type": "scatter",
            "axis_label": "Humidity",
            "hoverable": True, 
            "text_suffix": "%",
            "colour": "rgb(100, 100, 255)"
        },
        "Rainfall": {
            "trace_type": "scatter",
            "axis_label": "Rain",
            "hoverable": False, 
            "text_suffix": "",
            "colour": "rgb(0, 0, 255)"
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
            "colour": "rgb(255, 0, 0)"
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
    bar_bottom = max(y_values) + 0.7
    y_values.append(max(y_values) + 1)
    y_labels.append("Track status")
    
    for status in status_colours:
        trace_data = data[(data["TrackStatus"] == status)]
        fig.add_trace(
            go.Bar(
                x=trace_data["SessionTime"],
                y=[0.6] * len(trace_data),
                base=[bar_bottom] * len(trace_data),
                marker_color=status_colours[status],
                hoverinfo="text",
                hovertext=status
            )
        )
    
    # Update axes
    fig.update_yaxes(
        tickvals = y_values,
        ticktext = y_labels
    )
    fig.update_xaxes(
        visible=False
    )

    fig.update_layout(
        margin={"l":100, "r":100, "t":0, "b":0}
    )

    return fig


def shade_conditions_plot(figure_state, filters):
    
    # Takes session time tuple from relayoutData xaxis.range output and draws vrects either side

    # Build fig from existing dict, clear any existing shapes
    fig = go.Figure(figure_state)
    fig.layout.shapes = []

    print(type(fig))

    # Get time filter values
    filter_min_max = filter_values(filters, "TimeFilter")
    if len(filter_min_max) == 0:
        return fig

    filter_min, filter_max = (filter_min_max[0], filter_min_max[1])

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
    