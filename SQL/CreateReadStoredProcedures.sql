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
		,T.BrakeOrGearId
		,T.BrakeOrGear
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


DROP PROCEDURE IF EXISTS dbo.Read_CarData
GO
CREATE PROCEDURE dbo.Read_CarData @EventId INT, @SessionName VARCHAR(MAX)
AS
BEGIN

	/*
		Car data for inputs graph
	*/

	SELECT L.Driver
		,L.LapId
		,L.StintNumber
		,L.LapsInStint
		,L.IsPersonalBest
		,L.Compound
		,L.CleanLap
		,T.id AS SampleId
		,T.NearestNonSourceId AS PositionSampleId
		,T.SectorNumber
		,T.ZoneNumber
		,T.[Time]
		,T.RPM
		,T.Speed
		,T.Gear
		,T.Throttle
		,T.Brake
		,T.DRS
		,T.DRSOpen
		,T.DRSClose
		,T.DRSActive
		,D.Tla
		,D.TeamColour
		,D.DriverOrder

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
	AND T.[Source] = 'car'

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

	SELECT SampleId
		,X
		,Y
		,SectorNumber
		,ZoneNumber

	FROM dbo.TrackMap

	WHERE EventId = @EventId

END
GO


DROP PROCEDURE IF EXISTS dbo.Read_LapTimes
GO
CREATE PROCEDURE dbo.Read_LapTimes @EventId INT, @SessionName VARCHAR(MAX)
AS
BEGIN

	/*
		Lap times for lap scatter plot and stint line graph
	*/

	SELECT L.Driver
		,L.LapId
		,L.NumberOfLaps
		,L.StintNumber
		,L.LapsInStint
		,L.IsPersonalBest
		,L.Compound
		,L.TyreAge
		,L.CleanLap
		,L.TimeEnd
		,L.LapTime
		,D.Tla
		,D.TeamName
		,D.TeamColour

	FROM dbo.Session AS S

	INNER JOIN dbo.MergedLapData AS L
	ON S.id = L.SessionId

	INNER JOIN dbo.DriverInfo AS D
	ON S.id = D.SessionId
	AND L.Driver = D.RacingNumber

	WHERE EventId = @EventId
	AND (
		SessionName = @SessionName
		OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
	)
	AND L.LapTime IS NOT NULL

	ORDER BY D.TeamName ASC
		,L.Driver ASC
		,StintNumber ASC
		,LapsInStint ASC

END
GO


DROP PROCEDURE IF EXISTS dbo.Read_SectorTimes
GO
CREATE PROCEDURE dbo.Read_SectorTimes @EventId INT, @SessionName VARCHAR(MAX)
AS
BEGIN

	/*
		Sector times for lap scatter plot and stint line graph
	*/

	SELECT L.Driver
		,L.LapId
		,L.NumberOfLaps
		,L.StintId
		,L.StintNumber
		,L.LapsInStint
		,L.IsPersonalBest
		,L.Compound
		,L.TyreAge
		,L.CleanLap
		,L.TimeEnd
		,Sec.SectorNumber
		,Sec.SectorTime
		,D.Tla
		,D.TeamName
		,D.TeamColour
		,D.TeamOrder
		,D.DriverOrder

	FROM dbo.Session AS S

	INNER JOIN dbo.MergedLapData AS L
	ON S.id = L.SessionId

	INNER JOIN dbo.Sector AS Sec
	ON L.LapId = Sec.LapId

	INNER JOIN dbo.DriverInfo AS D
	ON S.id = D.SessionId
	AND L.Driver = D.RacingNumber

	WHERE EventId = @EventId
	AND (
		SessionName = @SessionName
		OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
	)

	ORDER BY D.TeamOrder ASC
	,D.DriverOrder ASC
	,StintNumber ASC
	,LapsInStint ASC

END
GO


DROP PROCEDURE IF EXISTS dbo.Read_ZoneTimes
GO
CREATE PROCEDURE dbo.Read_ZoneTimes @EventId INT, @SessionName VARCHAR(MAX)
AS
BEGIN

	/*
		Zone times for lap scatter plot and stint line graph
	*/

	SELECT L.Driver
		,L.LapId
		,L.NumberOfLaps
		,L.StintId
		,L.StintNumber
		,L.LapsInStint
		,L.IsPersonalBest
		,L.Compound
		,L.TyreAge
		,L.CleanLap
		,L.TimeEnd
		,Z.ZoneNumber
		,Z.ZoneTime
		,D.Tla
		,D.TeamName
		,D.TeamColour
		,D.TeamOrder
		,D.DriverOrder

	FROM dbo.Session AS S

	INNER JOIN dbo.MergedLapData AS L
	ON S.id = L.SessionId

	INNER JOIN dbo.Zone AS Z
	ON L.LapId = Z.LapId

	INNER JOIN dbo.DriverInfo AS D
	ON S.id = D.SessionId
	AND L.Driver = D.RacingNumber

	WHERE EventId = @EventId
	AND (
		SessionName = @SessionName
		OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
	)

	ORDER BY D.TeamOrder ASC
	,D.DriverOrder ASC
	,StintNumber ASC
	,LapsInStint ASC

END
GO