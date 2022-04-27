USE F1Dash

DROP PROCEDURE IF EXISTS dbo.Read_PositionData
GO
CREATE PROCEDURE dbo.Read_PositionData @EventId INT, @SessionName VARCHAR(MAX)
AS
BEGIN

	/*
		Position data for track map
	*/

	SELECT L.Driver
		,L.LapId
		,L.StintNumber
		,L.LapsInStint
		,L.IsPersonalBest
		,L.Compound
		,L.CleanLap
		,T.id AS SampleId
		,T.NearestNonSourceId AS CarSampleId
		,T.SectorNumber
		,T.ZoneNumber
		,T.[Time]
		,T.X
		,T.Y
		,T.Speed
		,T.Gear
		,T.Brake
		,D.Tla
		,D.TeamColour

	FROM dbo.Session AS S

	INNER JOIN dbo.MergedLapData AS L
	ON S.id = L.SessionId

	INNER JOIN dbo.MergedTelemetry AS T
	ON L.LapId = T.LapId

	INNER JOIN dbo.DriverInfo AS D
	ON S.id = D.SessionId
	AND L.Driver = D.RacingNumber

	WHERE EventId = @EventId
	AND (
		SessionName = @SessionName
		OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
	)
	AND T.[Source] = 'pos'

END
GO


DROP PROCEDURE IF EXISTS dbo.Read_ZoneTimes
GO
CREATE PROCEDURE dbo.Read_ZoneTimes @EventId INT, @SessionName VARCHAR(MAX)
AS
BEGIN

	/*
		Times per zone each lap.
		Could add this to load process if needed...
	*/

	SELECT L.Driver
		,L.LapId
		,L.Compound
		,L.CleanLap
		,L.TimeEnd
		,T.ZoneNumber
		,MAX(T.[Time]) - MIN(T.[Time]) AS ZoneTime
		,D.Tla
		,D.TeamColour


	FROM dbo.Session AS S

	INNER JOIN dbo.MergedLapData AS L
	ON S.id = L.SessionId

	INNER JOIN dbo.MergedTelemetry AS T
	ON L.LapId = T.LapId

	INNER JOIN dbo.DriverInfo AS D
	ON S.id = D.SessionId
	AND L.Driver = D.RacingNumber

	WHERE EventId = @EventId
	AND (
		SessionName = @SessionName
		OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
	)
	AND T.[Source] = 'pos'

	GROUP BY L.Driver
		,L.LapId
		,L.Compound
		,L.CleanLap
		,L.TimeEnd
		,T.ZoneNumber
		,D.Tla
		,D.TeamColour

END
GO


DROP PROCEDURE IF EXISTS dbo.Read_TrackMap
GO
CREATE PROCEDURE dbo.Read_TrackMap @EventId INT
AS
BEGIN

	/*
		Event track map. Handy for plotting fastest sectors/zones.
	*/

	SELECT X
		,Y
		,SectorNumber
		,ZoneNumber

	FROM dbo.TrackMap

	WHERE EventId = @EventId

END
GO
