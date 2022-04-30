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
		,L.NumberOfLaps
		,L.StintNumber
		,L.LapsInStint
		,L.IsPersonalBest
		,L.Compound
		,L.CleanLap
		,T.id AS SampleId
		,T.NearestNonSourceId AS CarSampleId
		,T.SectorNumber
		,T.ZoneNumber
		,T.[Time] + SO.SessionTimeOffset AS SessionTime
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

	INNER JOIN dbo.SessionOffsets(@EventId, @SessionName) AS SO
	ON S.id = SO.SessionId

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
		,L.NumberOfLaps
		,L.StintNumber
		,L.LapsInStint
		,L.IsPersonalBest
		,L.Compound
		,L.CleanLap
		,T.id AS SampleId
		,T.NearestNonSourceId AS PositionSampleId
		,T.SectorNumber
		,T.ZoneNumber
		,T.[Time] + SO.SessionTimeOffset AS SessionTime
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

	INNER JOIN dbo.SessionOffsets(@EventId, @SessionName) AS SO
	ON S.id = SO.SessionId

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
		,L.StintId
		,OS.OffsetStintNumber AS StintNumber
		,L.LapsInStint
		,L.IsPersonalBest
		,L.Compound
		,L.TyreAge
		,L.CleanLap
		,L.TimeEnd + SO.SessionTimeOffset AS SessionTime
		,L.LapTime
		,D.Tla
		,D.TeamName
		,D.TeamColour
		,D.TeamOrder
		,D.DriverOrder

	FROM dbo.Session AS S

	INNER JOIN dbo.MergedLapData AS L
	ON S.id = L.SessionId

	INNER JOIN dbo.DriverInfo AS D
	ON S.id = D.SessionId
	AND L.Driver = D.RacingNumber

	INNER JOIN dbo.SessionOffsets(@EventId, @SessionName) AS SO
	ON S.id = SO.SessionId

	INNER JOIN dbo.OffsetStintNumbers(@EventId, @SessionName) AS OS
	ON L.StintId = OS.StintId

	WHERE EventId = @EventId
	AND (
		SessionName = @SessionName
		OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
	)
	AND L.LapTime IS NOT NULL

	ORDER BY D.TeamOrder ASC
		,D.DriverOrder ASC
		,OS.OffsetStintNumber ASC
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
		,OS.OffsetStintNumber AS StintNumber
		,L.LapsInStint
		,L.IsPersonalBest
		,L.Compound
		,L.TyreAge
		,L.CleanLap
		,L.TimeEnd + SO.SessionTimeOffset AS SessionTime
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

	INNER JOIN dbo.SessionOffsets(@EventId, @SessionName) AS SO
	ON S.id = SO.SessionId

	INNER JOIN dbo.OffsetStintNumbers(@EventId, @SessionName) AS OS
	ON L.StintId = OS.StintId

	WHERE EventId = @EventId
	AND (
		SessionName = @SessionName
		OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
	)

	ORDER BY D.TeamOrder ASC
	,D.DriverOrder ASC
	,OS.OffsetStintNumber ASC
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
		,OS.OffsetStintNumber AS StintNumber
		,L.LapsInStint
		,L.IsPersonalBest
		,L.Compound
		,L.TyreAge
		,L.CleanLap
		,L.TimeEnd + SO.SessionTimeOffset AS SessionTime
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

	INNER JOIN dbo.SessionOffsets(@EventId, @SessionName) AS SO
	ON S.id = SO.SessionId

	INNER JOIN dbo.OffsetStintNumbers(@EventId, @SessionName) AS OS
	ON L.StintId = OS.StintId

	WHERE EventId = @EventId
	AND (
		SessionName = @SessionName
		OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
	)

	ORDER BY D.TeamOrder ASC
	,D.DriverOrder ASC
	,OS.OffsetStintNumber ASC
	,LapsInStint ASC

END
GO


DROP PROCEDURE IF EXISTS dbo.Read_ConditionsData
GO
CREATE PROCEDURE dbo.Read_ConditionsData @EventId INT, @SessionName VARCHAR(MAX)
AS
BEGIN

	/*
		Weather, track status, and track activity data for session conditions visual
	*/

	DECLARE @ActivityTimeRange FLOAT = 60 * CAST(1000000000 AS FLOAT) -- 1 minute either side of weather sample


	;WITH Weather AS (
		SELECT S.id AS SessionId
			,W.Time + SO.SessionTimeOffset AS SessionTime
			,W.AirTemp
			,W.Humidity
			,W.Pressure
			,W.Rainfall
			,W.TrackTemp
			,W.WindDirection
			,W.WindSpeed

		FROM dbo.Session AS S

		INNER JOIN dbo.WeatherData AS W
		ON S.id = W.SessionId

		INNER JOIN dbo.SessionOffsets(@EventId, @SessionName) AS SO
		ON S.id = SO.SessionId
		AND W.[Time] >= SO.MinStartTime
		AND W.[Time] < SO.MaxFinalisedTime

		WHERE EventId = @EventId
		AND (
			SessionName = @SessionName
			OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
		)
	)
	, Track AS (
		SELECT S.id AS SessionId
			,T.Time + SO.SessionTimeOffset AS SessionTime
			,T.Message AS TrackStatus

		FROM dbo.Session AS S

		INNER JOIN dbo.TrackStatus AS T
		ON S.id = T.SessionId

		INNER JOIN dbo.SessionOffsets(@EventId, @SessionName) AS SO
		ON S.id = SO.SessionId

		WHERE EventId = @EventId
		AND (
			SessionName = @SessionName
			OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
		)
	)
	, TimesJoin AS (
		SELECT W.SessionId
			,W.SessionTime AS WeatherTime
			,W.AirTemp
			,W.Humidity
			,W.Pressure
			,W.Rainfall
			,W.TrackTemp
			,W.WindDirection
			,W.WindSpeed
			,T.SessionTime AS TrackTime
			,T.TrackStatus
			,ROW_NUMBER() OVER(PARTITION BY W.SessionTime ORDER BY T.SessionTime DESC) AS RN

		FROM Weather AS W

		LEFT JOIN Track AS T
		ON W.SessionTime >= T.SessionTime
	)

	SELECT T.SessionId
		,T.WeatherTime AS SessionTime
		,T.AirTemp
		,T.Humidity / 100.0 AS Humidity
		,T.Pressure
		,T.Rainfall
		,T.TrackTemp
		,T.WindDirection
		,T.WindSpeed
		,T.TrackStatus
		,COUNT(L.SessionTime) AS Laps

	FROM TimesJoin AS T

	LEFT JOIN (
		-- Get track activity from lap data; base it on rolling count of laps ending
		SELECT L.TimeEnd + SO.SessionTimeOffset AS SessionTime

		FROM dbo.Session AS S

		INNER JOIN dbo.MergedLapData AS L
		ON S.id = L.SessionId

		INNER JOIN dbo.SessionOffsets(@EventId, @SessionName) AS SO
		ON S.id = SO.SessionId

		WHERE EventId = @EventId
		AND (
			SessionName = @SessionName
			OR LEFT(SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
		)
		AND L.TimeEnd IS NOT NULL
	) AS L
	ON T.WeatherTime + @ActivityTimeRange >= L.SessionTime
	AND T.WeatherTime - @ActivityTimeRange < L.SessionTime

	WHERE RN = 1

	GROUP BY T.SessionId
		,T.WeatherTime
		,T.AirTemp
		,T.Humidity
		,T.Pressure
		,T.Rainfall
		,T.TrackTemp
		,T.WindDirection
		,T.WindSpeed
		,T.TrackStatus

	ORDER BY T.WeatherTime ASC

END
GO