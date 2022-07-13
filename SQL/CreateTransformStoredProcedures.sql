USE F1DashStreamline

DROP PROCEDURE IF EXISTS dbo.Merge_LapData
GO
CREATE PROCEDURE dbo.Merge_LapData @SessionId INT
AS
BEGIN

	/*
		Combines lap data with the irregular timing app messages.
		Identifies weather id keys for each lap.
		Generally creates a more useful dataset than the raw lap import provides.
	*/

	-- Using 107% rule per driver so that slower cars don't have lots of unclean race laps
	-- Also partitioning by compound to handle changing conditions during a session.
	DECLARE @CleanLapTimeThreshold FLOAT = 1.07


	-- Clear out existing data for this session from dbo.MergedLapData
	DELETE
	FROM dbo.MergedLapData
	WHERE SessionId = @SessionId

	-- Get existing max StintId; StintId should be unique across sessions
	DECLARE @ExistingMaxStintId INT = (SELECT COALESCE(MAX(StintId), 0) FROM dbo.MergedLapData)


	-- Insert new rows
	INSERT INTO dbo.MergedLapData (
		SessionId
		,Driver
		,LapId
		,TimeStart
		,TimeEnd
		,PitOutTime
		,PitInTime
		,LapTime
		,NumberOfLaps
		,LapsInStint
		,IsPersonalBest
		,Compound
		,TyreAge
		,TrackStatus
		,CleanLap
		,WeatherId
		,StintNumber
		,StintId
	)
	SELECT *
		,SUM(CASE WHEN LapsInStint = 1 THEN 1 ELSE 0 END) OVER(PARTITION BY Driver ORDER BY NumberOfLaps ASC) AS StintNumber
		,SUM(CASE WHEN LapsInStint = 1 THEN 1 ELSE 0 END) OVER(ORDER BY Driver, NumberOfLaps ASC) + @ExistingMaxStintId AS StintId

	FROM (

		SELECT SessionId
			,Driver
			,Lap.LapId
			,TimeStart
			,TimeEnd
			,PitOutTime
			,PitInTime
			,LapTime
			,NumberOfLaps
			,COUNT(Lap.LapId) OVER(PARTITION BY Driver, CompId ORDER BY NumberOfLaps ASC) AS LapsInStint
			,IsPersonalBest
			,UPPER(LEFT(Compound, 1)) + LOWER(RIGHT(Compound, LEN(Compound) - 1)) AS Compound
			,COUNT(Lap.LapId) OVER(PARTITION BY Driver, CompId ORDER BY NumberOfLaps ASC) + TyreAgeWhenFitted AS TyreAge
			,TrackStatus
			,CASE
				WHEN TrackStatus <> 'AllClear' THEN 0
				WHEN LapTime IS NULL THEN 0
				WHEN LapTime > MIN(LapTime) OVER(PARTITION BY Driver, Compound) * @CleanLapTimeThreshold THEN 0
				WHEN COALESCE(PitOutTime, PitInTime) IS NOT NULL THEN 0
				WHEN LapTime = MIN(LapTime) OVER(PARTITION BY Driver) AND IsPersonalBest = 0 THEN 0
				ELSE 1
			END AS CleanLap
			,WeatherId

		FROM (

			SELECT L.*
				,ROW_NUMBER() OVER(PARTITION BY L.Driver, L.LapId ORDER BY Compound.[Time] DESC) AS RNCompound
				,Compound.Compound
				,Compound.TyreAgeWhenFitted
				,Compound.id AS CompId
				,Track.TrackStatus

			FROM (

				SELECT L.SessionId
					,L.Driver
					,L.id AS LapId
					,COALESCE(
						LAG(L.[Time]) OVER(PARTITION BY L.Driver ORDER BY L.[Time] ASC)
						,L.PitOutTime
					) AS TimeStart
					,L.[Time] AS TimeEnd
					,L.PitOutTime
					,L.PitInTime
					,L.LapTime
					,L.NumberOfLaps
					,L.IsPersonalBest

				FROM dbo.Lap AS L

				WHERE L.SessionId = @SessionId

			) AS L

			LEFT JOIN (
				SELECT Driver
					,[Time]
					,Compound
					,COALESCE(TotalLaps, 0) AS TyreAgeWhenFitted
					,id
				FROM dbo.TimingData
				WHERE Compound IS NOT NULL
				AND SessionId = @SessionId
			) AS Compound
			ON L.Driver = Compound.Driver
			AND L.TimeEnd >= Compound.[Time]

			LEFT JOIN (
				SELECT [Time] AS TimeStart
					,LEAD([Time]) OVER(PARTITION BY SessionId ORDER BY [Time] ASC) AS TimeEnd
					,[Status]
					,[Message] AS TrackStatus
				FROM dbo.TrackStatus
				WHERE SessionId = @SessionId
			) AS Track
			ON (L.TimeStart <= Track.TimeEnd OR Track.TimeEnd IS NULL)
			AND L.TimeEnd > Track.TimeStart

		) AS Lap

		LEFT JOIN (
			SELECT L.id AS LapId
				,W.id AS WeatherId
				,ROW_NUMBER() OVER(PARTITION BY L.id ORDER BY W.[Time] DESC) AS RNWeather

			FROM dbo.Lap AS L

			LEFT JOIN dbo.WeatherData AS W
			ON L.[Time] >= W.[Time]

			WHERE L.SessionId = @SessionId
			AND W.SessionId = @SessionId
		) AS Weather
		ON Lap.LapId = Weather.LapId
		AND Weather.RNWeather = 1

		WHERE RNCompound = 1

	) AS A

END
GO


DROP PROCEDURE IF EXISTS dbo.Merge_UpdateTelemetryTimes
GO
CREATE PROCEDURE dbo.Merge_UpdateTelemetryTimes @SessionId INT
AS
BEGIN

	/*
		Telemetry data [Time] fields are not accurate - the same value is repeated for a window of multiple samples.
		The [Date] field, however, is understood to be accurate, but cannot be related back to lap data (which only includes [Time]...!).
		To attempt to slice telemetry into laps, will use [Time] to offset session data as a whole while using [Date] to get correct deltas etc.
		This procedure requires MergedLapData to be updated beforehand.
	*/

	-- Get @SessionZeroDate
	-- A bit crude, may need to revisit if telemetry doesn't visually line up with lap times to a certain degree; but never expected to align perfectly.
	-- Looks like car data starts returning a time marginally later than position data - maybe just use position data to get zero?
	-- Convert to ms to avoid int overflow. Data is loaded as ns so will have to convert back again...

	DECLARE @CarDataZeroDate DATETIME2(3)
		,@PositionDataZeroDate DATETIME2(3)
		,@SessionZeroDate DATETIME2(3)

	SET @CarDataZeroDate = (
		SELECT DATEADD(MILLISECOND
				,-MIN([Time]) / 1000000
				,MIN([Date])
			)
		FROM dbo.CarData
		WHERE SessionId = @SessionId
	)

	SET @PositionDataZeroDate = (
		SELECT DATEADD(MILLISECOND
				,-MIN([Time]) / 1000000
				,MIN([Date])
			)
		FROM dbo.PositionData
		WHERE SessionId = @SessionId
	)

	SET @SessionZeroDate = (SELECT DATEADD(MILLISECOND, DATEDIFF(MILLISECOND, @CarDataZeroDate, @PositionDataZeroDate) / 2, @CarDataZeroDate))


	-- Update [Time] field in both telemetry tables

	UPDATE dbo.CarData
	SET [Time] = DATEDIFF(MILLISECOND, @SessionZeroDate, [Date]) * CAST(1000000 AS FLOAT)
	WHERE SessionId = @SessionId
	AND [Time] IS NOT NULL

	UPDATE dbo.PositionData
	SET [Time] = DATEDIFF(MILLISECOND, @SessionZeroDate, [Date]) * CAST(1000000 AS FLOAT)
	WHERE SessionId = @SessionId
	AND [Time] IS NOT NULL

END
GO


DROP PROCEDURE IF EXISTS dbo.Merge_TrackMap
GO
CREATE PROCEDURE dbo.Merge_TrackMap @EventId INT
AS
BEGIN

	/*
		Use position data to draw a rough picture of racing line.
		Use data from first session of event so that comparisons can be made between sessions at same event.
		Should also be possible to identify sectors using sector time data from fastest lap.
	*/

	DECLARE @SessionId INT
		,@ExistingRowCount INT
		,@LapId INT
		,@Driver INT
		,@TimeStart FLOAT
		,@TimeEnd FLOAT

	-- If a track map already exists for this event, exit this procedure
	SET @ExistingRowCount = (
		SELECT COUNT(*)
		FROM dbo.TrackMap
		WHERE EventId = @EventId
	)

	IF @ExistingRowCount > 0
	BEGIN
		RETURN
	END


	-- Get a clean lap of samples from fastest lap in first session of event that has at least one clean lap
	-- Split samples into sectors at same time

	SET @SessionId = (
		SELECT SessionId

		FROM (
			SELECT S.id AS SessionId
				,ROW_NUMBER() OVER(ORDER BY S.SessionOrder ASC) AS RN

			FROM dbo.Event AS E

			INNER JOIN dbo.Session AS S
			ON E.id = S.EventId

			INNER JOIN dbo.MergedLapData AS L
			ON S.id = L.SessionId

			WHERE E.id = @EventId
			AND L.CleanLap = 1

			GROUP BY S.id
				,S.SessionOrder

		) AS A

		WHERE RN = 1
	)

	-- Get lap details
	;WITH O AS (
		SELECT *
			,ROW_NUMBER() OVER(ORDER BY LapTime ASC) AS RN

		FROM dbo.MergedLapData

		WHERE SessionId = @SessionId
		AND LapTime IS NOT NULL
		AND CleanLap = 1
		AND IsPersonalBest = 1
	)
	SELECT @LapId = LapId
		,@Driver = Driver
		,@TimeStart = TimeStart
		,@TimeEnd = TimeEnd

	FROM O

	WHERE RN = 1


	-- Link samples to sectors and insert them into dbo.TrackMap
	;WITH P AS(
		SELECT *
			,[Time] - @TimeStart AS LapTimeCumulative

		FROM dbo.PositionData AS P

		WHERE SessionId = @SessionId
		AND Driver = @Driver
		AND [Time] >= @TimeStart
		AND [Time] < @TimeEnd
	)
	,S AS(
		SELECT SectorNumber
			,SUM(SectorTime) OVER(ORDER BY SectorNumber ASC) AS SectorTimeCumulative

		FROM dbo.Sector

		WHERE LapId = @LapId
	)
	,J AS(
		SELECT *
			,ROW_NUMBER() OVER(PARTITION BY P.[Time] ORDER BY S.SectorNumber ASC) AS RN

		FROM P

		INNER JOIN S
		ON P.LapTimeCumulative < S.SectorTimeCumulative
	)
	INSERT INTO dbo.TrackMap(
		EventId
		,SampleId
		,X
		,Y
		,Z
		,SectorNumber
	)
	SELECT @EventId
		,ROW_NUMBER() OVER(ORDER BY [Time] ASC) AS SampleId
		,X
		,Y
		,Z
		,SectorNumber
			
	FROM J

	WHERE RN = 1

END
GO



DROP PROCEDURE IF EXISTS dbo.Merge_CarData
GO
CREATE PROCEDURE dbo.Merge_CarData @SessionId INT
AS
BEGIN

	/*
		Create a clean dataset of car telemetry, with lap and sector foreign keys
	*/

	-- Delete any existing records for this session
	DELETE
	FROM dbo.MergedCarData
	WHERE SessionId = @SessionId


	-- Merge raw car data with laps/sectors, insert into dbo.MergedCarData
	INSERT INTO dbo.MergedCarData(
		SessionId
		,Driver
		,LapId
		,SectorNumber
		,[Time]
		,RPM
		,Speed
		,Gear
		,Throttle
		,Brake
		,DRS
	)
	SELECT SessionId
		,Driver
		,LapId
		,SectorNumber
		,[Time]
		,RPM
		,Speed
		,Gear
		,Throttle
		,Brake
		,DRS

	FROM (

		SELECT L.SessionId
			,L.Driver
			,L.[Time]
			,L.LapId
			,L.RPM
			,L.Speed
			,L.Gear
			,L.Throttle
			,L.Brake
			,L.DRS
			,S.SectorNumber
			,ROW_NUMBER() OVER(PARTITION BY L.LapId, L.[Time] ORDER BY S.SectorNumber ASC) AS SRN

		FROM (
			SELECT T.SessionId
				,T.Driver
				,L.LapId
				,T.[Time]
				,T.RPM
				,T.Speed
				,T.Gear
				,T.Throttle
				,T.Brake
				,T.DRS
				,T.[Time] - L.TimeStart AS LapTimeCumulative

			FROM (
				SELECT *

				FROM dbo.CarData

				WHERE SessionId = @SessionId
			) AS T

			INNER JOIN (
				SELECT Driver
					,LapId
					,TimeStart
					,TimeEnd

				FROM dbo.MergedLapData

				WHERE SessionId = @SessionId
			) AS L
			ON T.Driver = L.Driver
			AND T.[Time] >= L.TimeStart
			AND T.[Time] < L.TimeEnd
		) AS L

		INNER JOIN (
			SELECT LapId
				,SectorNumber
				,SUM(SectorTime) OVER(PARTITION BY LapId ORDER BY SectorNumber ASC) AS SectorTimeCumulative

			FROM dbo.Sector

			WHERE SessionId = @SessionId
		) AS S
		ON L.LapId = S.LapId
		AND L.LapTimeCumulative < S.SectorTimeCumulative

	) AS M

	WHERE SRN = 1

END
GO


DROP PROCEDURE IF EXISTS dbo.Merge_CarDataNorms
GO
CREATE PROCEDURE dbo.Merge_CarDataNorms @SessionId INT
AS
BEGIN

	DELETE
	FROM dbo.CarDataNorms
	WHERE SessionId = @SessionId

	INSERT INTO dbo.CarDataNorms(
		SessionId
		,RPMMin
		,RPMMax
		,SpeedMin
		,SpeedMax
		,GearMin
		,GearMax
		,ThrottleMin
		,ThrottleMax
	)
	SELECT @SessionId
		,MIN(T.RPM) AS RPMMin
		,MAX(T.RPM) AS RPMMax
		,MIN(T.Speed) AS SpeedMin
		,MAX(T.Speed) AS SpeedMax
		,MIN(T.Gear) AS GearMin
		,MAX(T.Gear) AS GearMax
		,MIN(T.Throttle) AS ThrottleMin
		,MAX(T.Throttle) AS ThrottleMax

	FROM dbo.MergedCarData AS T

	WHERE T.SessionId = @SessionId

END
GO
