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
		,X
		,Y
		,Z
		,SectorNumber
	)
	SELECT @EventId
		,X
		,Y
		,Z
		,SectorNumber
			
	FROM J

	WHERE RN = 1

END
GO


DROP PROCEDURE IF EXISTS dbo.Update_TelemetryTrackMapping
GO
CREATE PROCEDURE dbo.Update_TelemetryTrackMapping @SessionId INT, @Driver INT
AS
BEGIN
	
	DECLARE @EventId INT
		,@XMin INT
		,@YMin INT
		,@XMax INT
		,@YMax INT
		,@cmd NVARCHAR(MAX)
		,@i INT
		,@NullCount INT
		,@SearchRadius INT
		,@TotalZones INT

	SET @EventId = (
		SELECT EventId

		FROM dbo.Session

		WHERE id = @SessionId
	)

	-- Get min/max coordinates for index bounding box
	SELECT @XMin = MIN(X)
		,@YMin = MIN(Y)
		,@XMax = MAX(X)
		,@YMax = MAX(Y)

	FROM (
		SELECT X
			,Y

		FROM dbo.MergedTelemetry

		WHERE SessionId = @SessionId

		UNION ALL
		SELECT X
			,Y

		FROM dbo.TrackMap

		WHERE EventId = @EventId
	) AS U


	-- Create tables of points
	-- Telemetry
	CREATE TABLE #Tel(
		id INT PRIMARY KEY
		,LapId INT
		,[Time] FLOAT
		,X INT
		,Y INT
		,Point GEOMETRY
	)
	INSERT INTO #Tel
	SELECT id
		,LapId
		,[Time]
		,X
		,Y
		,GEOMETRY::STGeomFromText('POINT(' + CAST(X AS VARCHAR(MAX)) + ' ' + CAST(Y AS VARCHAR(MAX)) + ')', 0) AS Point

	FROM dbo.MergedTelemetry

	WHERE SessionId = @SessionId
	AND Driver = @Driver
	AND LapId IS NOT NULL


	SET @cmd = '
		CREATE SPATIAL INDEX IndexPoint 
		ON #Tel (Point)
		WITH (
			BOUNDING_BOX=(xmin=' + CAST(@XMin AS VARCHAR) + ', ymin=' + CAST(@YMin AS VARCHAR) + ', xmax=' + CAST(@XMax AS VARCHAR) + ', ymax=' + CAST(@YMax AS VARCHAR) + ')
		)
	'
	EXEC(@cmd)

	-- Map
	CREATE TABLE #Map(
		id INT IDENTITY(0, 1) PRIMARY KEY
		,X INT
		,Y INT
		,SectorNumber INT
		,ZoneNumber INT
		,ZoneInputCategory INT
		,Point GEOMETRY
	)
	INSERT INTO #Map (
		X
		,Y
		,SectorNumber
		,ZoneNumber
		,ZoneInputCategory
		,Point
	)
	SELECT X
		,Y
		,SectorNumber
		,ZoneNumber
		,ZoneInputCategory
		,GEOMETRY::STGeomFromText('POINT(' + CAST(X AS VARCHAR(MAX)) + ' ' + CAST(Y AS VARCHAR(MAX)) + ')', 0) AS Point

	FROM dbo.TrackMap

	WHERE EventId = @EventId

	SET @cmd = '
		CREATE SPATIAL INDEX IndexPoint 
		ON #Map (Point)
		WITH (
			BOUNDING_BOX=(xmin=' + CAST(@XMin AS VARCHAR) + ', ymin=' + CAST(@YMin AS VARCHAR) + ', xmax=' + CAST(@XMax AS VARCHAR) + ', ymax=' + CAST(@YMax AS VARCHAR) + ')
		)
	'
	EXEC(@cmd)


	-- Iterate through increasing initial join until all telemetry records have at least one match
	-- Ensures that all samples are matched up to a max of 100m, will speed up query at bit too

	CREATE TABLE #MatchedRows(
		id INT
		,LapId INT
		,[Time] FLOAT
		,X INT
		,Y INT
		,Distance FLOAT
		,DistanceRank INT
		,SectorNumber INT
		,ZoneNumber INT
		,ZoneInputCategory INT
	)

	SET @NullCount = (SELECT COUNT(*) FROM #Tel)
	SET @SearchRadius = 100

	WHILE @NullCount > 0 AND @SearchRadius <= 1000
	BEGIN

		-- Match and insert
		INSERT INTO #MatchedRows (
			id
			,LapId
			,[Time]
			,X
			,Y
			,Distance
			,DistanceRank
			,SectorNumber
			,ZoneNumber
			,ZoneInputCategory
		)
		SELECT T.id
			,T.LapId
			,T.[Time]
			,T.X
			,T.Y
			,T.Point.STDistance(M.Point) AS Distance
			,ROW_NUMBER() OVER(PARTITION BY T.id ORDER BY T.Point.STDistance(M.Point) ASC) AS DistanceRank
			,M.SectorNumber
			,M.ZoneNumber
			,M.ZoneInputCategory
		
		FROM #Tel AS T

		INNER JOIN #Map AS M
		ON T.X > M.X - @SearchRadius
		AND T.X < M.X + @SearchRadius
		AND T.Y > M.Y - @SearchRadius
		AND T.Y < M.Y + @SearchRadius

		-- Delete matches from original table
		DELETE T
		FROM #Tel AS T
		INNER JOIN #MatchedRows AS MR
		ON T.id = MR.id

		-- Update loop variables
		SET @NullCount = (SELECT COUNT(*) FROM #Tel)
		SET @SearchRadius = @SearchRadius + 100

	END



	-- Correct samples at start/end of lap (e.g. sometimes first sample of lap is geometrically closer to last point of final zone/sector)

	SET @TotalZones = (SELECT MAX(ZoneNumber) FROM #MatchedRows)

	;WITH TimeDiff AS (
		SELECT *
			,ABS([Time] - MIN([Time]) OVER(PARTITION BY LapId)) AS TimeToFirstSample
			,ABS([Time] - MAX([Time]) OVER(PARTITION BY LapId)) AS TimeToLastSample

		FROM #MatchedRows

		WHERE ZoneNumber IN (1, @TotalZones)
	)
	SELECT id
		,CASE
			WHEN SectorNumber = 1 AND TimeToFirstSample > TimeToLastSample THEN 3
			WHEN SectorNumber = 3 AND TimeToFirstSample < TimeToLastSample THEN 1
			ELSE SectorNumber
		END AS SectorNumber
		,CASE
			WHEN ZoneNumber = 1 AND TimeToFirstSample > TimeToLastSample THEN @TotalZones
			WHEN ZoneNumber = @TotalZones AND TimeToFirstSample < TimeToLastSample THEN 1
			ELSE ZoneNumber
		END AS ZoneNumber

	INTO #Overrides

	FROM TimeDiff

	WHERE DistanceRank = 1
	AND (
		(SectorNumber = 1 AND TimeToFirstSample > TimeToLastSample)
		OR (SectorNumber = 3 AND TimeToFirstSample < TimeToLastSample)
		OR (ZoneNumber = 1 AND TimeToFirstSample > TimeToLastSample)
		OR (ZoneNumber = @TotalZones AND TimeToFirstSample < TimeToLastSample)
	)



	-- Update merged telemetry data
	UPDATE T

	SET T.SectorNumber = COALESCE(O.SectorNumber, M.SectorNumber)
		,T.ZoneNumber = COALESCE(O.ZoneNumber, M.ZoneNumber)
		,T.ZoneInputCategory = M.ZoneInputCategory

	FROM dbo.MergedTelemetry AS T

	INNER JOIN (
		SELECT *
	
		FROM #MatchedRows 
	
		WHERE DistanceRank = 1
	) AS M
	ON T.id = M.id

	LEFT JOIN #Overrides AS O
	ON T.id = O.id




	DROP TABLE #Tel, #Map, #MatchedRows, #Overrides

END
GO

-- Replacing this version with following proc

--DROP PROCEDURE IF EXISTS dbo.Merge_Zone
--GO
--CREATE PROCEDURE dbo.Merge_Zone @SessionId INT
--AS
--BEGIN

--	/*
--		Creates zone time records in same shape as sector times.
--		Zone time calculated using first sample time in zone and first sample in following zone.
--		Jitter in sample data means these times should be treated with caution, and will be particularly erratic for short zones.

--		Run after telemetry has been merged with track zones etc.
--	*/

--	-- Clear existing records for this session
--	DELETE Z
--	FROM dbo.Zone AS Z
--	INNER JOIN dbo.MergedLapData AS L
--	ON Z.LapId = L.LapId
--	WHERE L.SessionId = @SessionId

--	-- Insert new records
--	INSERT INTO dbo.Zone(
--		LapId
--		,ZoneNumber
--		,ZoneTime
--		,ZoneSessionTime
--	)
--	SELECT LapId
--		,ZoneNumber
--		,LEAD(MinZoneTime, 1, MaxZoneTime) OVER(PARTITION BY Driver ORDER BY NumberOfLaps ASC, ZoneNumber ASC) - MinZoneTime AS ZoneTime
--		,LEAD(MinZoneTime, 1, MaxZoneTime) OVER(PARTITION BY Driver ORDER BY NumberOfLaps ASC, ZoneNumber ASC) AS ZoneSessionTime

--	FROM (

--		SELECT L.LapId
--			,L.Driver
--			,L.NumberOfLaps
--			,T.ZoneNumber
--			,MIN([Time]) AS MinZoneTime
--			,MAX([Time]) AS MaxZoneTime

--		FROM dbo.MergedTelemetry AS T

--		INNER JOIN dbo.MergedLapData AS L
--		ON T.LapId = L.LapId

--		WHERE T.SessionId = @SessionId

--		GROUP BY L.LapId
--			,L.Driver
--			,L.NumberOfLaps
--			,T.ZoneNumber

--	) AS A

--END
--GO


DROP PROCEDURE IF EXISTS dbo.Merge_Zone
GO
CREATE PROCEDURE dbo.Merge_Zone @SessionId INT
AS
BEGIN

	/*
		Creates zone time records in same shape as sector times.
		Use zone start/end samples and then interpolate the time at which each driver reached that point on track.
		Not hugely precise, but should be a better guide than using the first/last raw samples which are every ~250ms, +/- jitter.

		Run after telemetry has been merged with track zones etc.
	*/

	DECLARE @EventId INT
		,@ZoneCount INT
		,@DistanceThreshold INT = 1000 -- Max 100m search for nearest samples
		,@SearchRadius INT
		,@NullCount INT


	SET @EventId = (
		SELECT EventId

		FROM dbo.Session

		WHERE id = @SessionId
	)


	SET @ZoneCount = (SELECT MAX(ZoneNumber) FROM dbo.TrackMap WHERE EventId = @EventId)


	-- Get divisions between zones from track map
	;WITH ZoneStarts AS (
		SELECT *
			,ROW_NUMBER() OVER(PARTITION BY ZoneNumber ORDER BY SampleId ASC) AS ZoneRN
			,ATN2(
				LEAD(X, 1) OVER(ORDER BY SampleId ASC) - X
				,LEAD(Y, 1) OVER(ORDER BY SampleId ASC) -Y
			) AS Theta
			 
		FROM dbo.TrackMap

		WHERE EventId = @EventId
	)
	, ZoneBreaks AS (
		SELECT ZoneNumber
			,X
			,Y
			,DEGREES(
				CASE
					WHEN Theta < 0 THEN Theta + 2 * PI()
					ELSE Theta
				END
			) AS HeadingDegrees
		FROM ZoneStarts
		WHERE ZoneRN = 1
	)
	SELECT *
	INTO #ZoneBreaks
	FROM ZoneBreaks


	/*
		Get position samples immediately before and after zone breaks.
		Watch out for last sample of lap actually being assigned to next lap in merged data and vice versa... Might happen?
	*/

	-- Table to track samples still to find
	CREATE TABLE #LapZones(
		Driver INT
		,LapId INT
		,LapNumber INT
		,ZoneNumber INT
		,X INT
		,Y INT
		,HeadingDegrees FLOAT
		,SampleBefore INT
		,SampleAfter INT
		,TimeBefore FLOAT
		,TimeAfter FLOAT
		,DistanceBefore FLOAT
		,DistanceAfter FLOAT
	)
	INSERT INTO #LapZones(
		Driver
		,LapId
		,LapNumber
		,ZoneNumber
		,X
		,Y
		,HeadingDegrees
	)
	SELECT DISTINCT T.Driver
		,T.LapId
		,L.NumberOfLaps
		,T.ZoneNumber
		,Z.X
		,Z.Y
		,Z.HeadingDegrees
	FROM dbo.MergedTelemetry AS T

	INNER JOIN dbo.Lap AS L
	ON T.LapId = L.id

	INNER JOIN #ZoneBreaks AS Z
	ON T.ZoneNumber = Z.ZoneNumber

	WHERE T.SessionId = @SessionId
	AND T.[Source] = 'pos'
	AND T.LapId IS NOT NULL 

	CREATE CLUSTERED INDEX IndexLapIdZoneNumber ON #LapZones (LapId, ZoneNumber)


	-- Incrementally increase search radius for nearest point before and after
	SET @NullCount = (SELECT COUNT(*) FROM #LapZones WHERE SampleBefore IS NULL OR SampleAfter IS NULL)
	SET @SearchRadius = 100

	WHILE @NullCount > 0 AND @SearchRadius <= @DistanceThreshold
	BEGIN

		;WITH Search AS (
			SELECT LZ.LapId
				,LZ.ZoneNumber
				,T.id AS SampleId
				,T.[Time]
				,CASE 
					WHEN T.X = LZ.X AND T.Y = LZ.Y THEN NULL
					ELSE CAST(ABS(DEGREES(ATN2(T.X - LZ.X, T.Y - LZ.Y)) - LZ.HeadingDegrees) AS INT) % 360
				END AS HeadingDegreesFromBreakHeading
				,SQRT(POWER(T.X - LZ.X, 2) + POWER(T.Y - LZ.Y, 2)) AS Distance

			FROM #LapZones AS LZ

			INNER JOIN dbo.MergedTelemetry AS T
			ON LZ.Driver = T.Driver
			AND LZ.LapId = T.LapId
			AND LZ.X > T.X - @SearchRadius
			AND LZ.X < T.X + @SearchRadius
			AND LZ.Y > T.Y - @SearchRadius
			AND LZ.Y < T.Y + @SearchRadius

			WHERE T.LapId IS NOT NULL
			AND T.SessionId = @SessionId
			AND T.[Source] = 'pos'
			AND (LZ.SampleBefore IS NULL OR LZ.SampleAfter IS NULL)

		)
		,Direction AS (
			SELECT *
				,CASE
					WHEN HeadingDegreesFromBreakHeading IS NULL THEN 'After'
					WHEN HeadingDegreesFromBreakHeading >= 90 AND HeadingDegreesFromBreakHeading < 270 THEN 'Before'
					ELSE 'After'
				END AS BeforeOrAfter
			FROM Search
		)
		,Nearest AS (
			SELECT D.*
				,ROW_NUMBER() OVER(PARTITION BY D.LapId, D.ZoneNumber, D.BeforeOrAfter ORDER BY D.Distance ASC) AS RN

			FROM Direction AS D

			INNER JOIN dbo.MergedLapData AS L
			ON D.LapId = L.LapId

			-- Filter out incorrect connections at very start/end of lap by comparing to lap start/end session times
			WHERE NOT (D.ZoneNumber = 1 AND ABS(D.[Time] - L.TimeStart) > ABS(D.[Time] - L.TimeEnd))
			AND NOT (D.ZoneNumber = @ZoneCount AND ABS(D.[Time] - L.TimeStart) < ABS(D.[Time] - L.TimeEnd))
		)
		SELECT *
		INTO #Nearest
		FROM Nearest


		UPDATE LZ

		SET LZ.SampleBefore = N.SampleId
			,LZ.TimeBefore = N.[Time]
			,LZ.DistanceBefore = N.Distance

		FROM #LapZones AS LZ

		LEFT JOIN #Nearest AS N
		ON LZ.LapId = N.LapId
		AND LZ.ZoneNumber = N.ZoneNumber

		WHERE LZ.SampleBefore IS NULL
		AND N.BeforeOrAfter = 'Before'
		AND N.RN = 1


		UPDATE LZ

		SET LZ.SampleAfter = N.SampleId
			,LZ.TimeAfter = N.[Time]
			,LZ.DistanceAfter = N.Distance

		FROM #LapZones AS LZ

		LEFT JOIN #Nearest AS N
		ON LZ.LapId = N.LapId
		AND LZ.ZoneNumber = N.ZoneNumber

		WHERE LZ.SampleAfter IS NULL
		AND N.BeforeOrAfter = 'After'
		AND N.RN = 1



		DROP TABLE #Nearest

		SET @NullCount = (SELECT COUNT(*) FROM #LapZones WHERE SampleBefore IS NULL OR SampleAfter IS NULL)
		SET @SearchRadius = @SearchRadius + 100
	END


	-- Catch null samples before first zone / after last zone, use last / first sample of previous / next lap

	UPDATE LZ

	SET LZ.SampleBefore = T.PreviousSampleId
		,LZ.TimeBefore = T.PreviousSampleTime
		,LZ.DistanceBefore = SQRT(POWER(T.PreviousSampleX - LZ.X, 2) + POWER(T.PreviousSampleY - LZ.Y, 2))

	FROM #LapZones AS LZ

	INNER JOIN (
		SELECT LZ.Driver
			,LZ.LapId
			,LZ.ZoneNumber
			,T.id AS PreviousSampleId
			,T.[Time] AS PreviousSampleTime
			,T.X AS PreviousSampleX
			,T.Y AS PreviousSampleY
			,ROW_NUMBER() OVER(PARTITION BY LZ.LapId, LZ.ZoneNumber ORDER BY T.[Time] DESC) AS RN

		FROM #LapZones AS LZ

		INNER JOIN dbo.MergedLapData AS L
		ON LZ.Driver = L.Driver
		AND LZ.LapNumber = L.NumberOfLaps + 1

		INNER JOIN dbo.MergedTelemetry AS T
		ON L.LapId = T.LapId

		WHERE LZ.SampleBefore IS NULL
		AND LZ.ZoneNumber = 1
		AND T.SessionId = @SessionId
		AND T.[Source] = 'pos'
	) AS T
	ON LZ.LapId = T.LapId
	AND LZ.ZoneNumber = T.ZoneNumber

	WHERE T.RN = 1


	UPDATE LZ

	SET LZ.SampleBefore = T.NextSampleId
		,LZ.TimeBefore = T.NextSampleTime
		,LZ.DistanceBefore = SQRT(POWER(T.NextSampleX - LZ.X, 2) + POWER(T.NextSampleY - LZ.Y, 2))

	FROM #LapZones AS LZ

	INNER JOIN (
		SELECT LZ.Driver
			,LZ.LapId
			,LZ.ZoneNumber
			,T.id AS NextSampleId
			,T.[Time] AS NextSampleTime
			,T.X AS NextSampleX
			,T.Y AS NextSampleY
			,ROW_NUMBER() OVER(PARTITION BY LZ.LapId, LZ.ZoneNumber ORDER BY T.[Time] ASC) AS RN

		FROM #LapZones AS LZ

		INNER JOIN dbo.MergedLapData AS L
		ON LZ.Driver = L.Driver
		AND LZ.LapNumber = L.NumberOfLaps - 1

		INNER JOIN dbo.MergedTelemetry AS T
		ON L.LapId = T.LapId

		WHERE LZ.SampleAfter IS NULL
		AND LZ.ZoneNumber = @ZoneCount
		AND T.SessionId = @SessionId
		AND T.[Source] = 'pos'
	) AS T
	ON LZ.LapId = T.LapId
	AND LZ.ZoneNumber = T.ZoneNumber

	WHERE T.RN = 1


	-- Clear existing records for this session
	DELETE Z
	FROM dbo.Zone AS Z
	INNER JOIN dbo.MergedLapData AS L
	ON Z.LapId = L.LapId
	WHERE L.SessionId = @SessionId


	-- Use sample times either side to estimate time at which car passed zone break from track map
	-- Insert into table
	;WITH Interpolate AS (
		SELECT * 
			,ROUND(TimeBefore + (TimeAfter - TimeBefore) * (DistanceBefore / (DistanceBefore + DistanceAfter)), -6) AS InterpolatedTime

		FROM #LapZones
	)
	,Times AS (
		SELECT LapId
			,ZoneNumber
			,LEAD(InterpolatedTime, 1) OVER(PARTITION BY Driver ORDER BY LapNumber ASC, ZoneNumber ASC) - InterpolatedTime AS ZoneTime
			,LEAD(InterpolatedTime, 1) OVER(PARTITION BY Driver ORDER BY LapNumber ASC, ZoneNumber ASC) AS ZoneSessionTime

		FROM Interpolate
	)


	INSERT INTO dbo.Zone(
		LapId
		,ZoneNumber
		,ZoneTime
		,ZoneSessionTime
	)
	SELECT LapId
		,ZoneNumber
		,ZoneTime
		,ZoneSessionTime

	FROM Times


	DROP TABLE #ZoneBreaks, #LapZones

END
GO


DROP PROCEDURE IF EXISTS dbo.Update_ZoneSenseCheck
GO
CREATE PROCEDURE dbo.Update_ZoneSenseCheck @SessionId INT
AS
BEGIN

	/* 
		Update Zone table SenseCheck field.
		Sense check zone times by comparing to each driver's clean lap times on that compound.
		Use Z-scoring i.e. number of standard deviations from the mean.
		Positive scores could just mean the driver made a mistake on that lap.
		Look for largely negative scores, since these are much more likely to be a data issue than a driver suddenly doing one phenomenal lap.
		When such a score is found with a positive outlier adjacent, mark both as suspect. Probably a problem with the samples at the zone break point.
	*/

	DECLARE @NegativeZScoreThreshold FLOAT = -3.0
		,@PositiveZScoreThreshold FLOAT = 2.0


	;WITH Scoring AS (
		SELECT L.LapId
			,L.Driver
			,L.NumberOfLaps
			,L.CleanLap
			,L.Compound
			,Z.ZoneNumber
			,Z.ZoneTime
			,PERCENTILE_CONT(0.5)
				WITHIN GROUP(ORDER BY ZoneTime ASC)
				OVER(PARTITION BY L.Compound, Z.ZoneNumber)
			AS MedianZoneTime
			,CASE
				WHEN STDEVP(ZoneTime) OVER(PARTITION BY L.Driver, L.Compound, Z.ZoneNumber) = 0 THEN NULL
				ELSE (Z.ZoneTime - AVG(ZoneTime) OVER(PARTITION BY L.Driver, L.Compound, Z.ZoneNumber)) / STDEVP(ZoneTime) OVER(PARTITION BY L.Driver, L.Compound, Z.ZoneNumber) 
			END AS ZScore

		FROM dbo.Zone AS Z

		INNER JOIN dbo.MergedLapData AS L
		ON Z.LapId = L.LapId

		WHERE L.SessionId = @SessionId
		AND L.CleanLap = 1
	)
	,Adjacents AS (
		SELECT *
			,LAG(ZScore, 1, 0) OVER(PARTITION BY Driver ORDER BY NumberOfLaps ASC, ZoneNumber ASC) AS PreviousZScore
			,LEAD(ZScore, 1, 0) OVER(PARTITION BY Driver ORDER BY NumberOfLaps ASC, ZoneNumber ASC) AS NextZScore

		FROM Scoring
	)
	,SenseCheck AS (
		SELECT *
			,CASE
				WHEN ZoneTime IS NULL OR ZoneTime <= 0 THEN 0
				WHEN LAG(NumberOfLaps, 1, 0) OVER(PARTITION BY Driver ORDER BY NumberOfLaps ASC, ZoneNumber ASC) < NumberOfLaps - 1 THEN 1
				WHEN LEAD(NumberOfLaps, 1, 999) OVER(PARTITION BY Driver ORDER BY NumberOfLaps ASC, ZoneNumber ASC) > NumberOfLaps + 1 THEN 1
				WHEN ZScore < @NegativeZScoreThreshold AND (PreviousZScore > @PositiveZScoreThreshold OR NextZScore > @PositiveZScoreThreshold) THEN 0
				WHEN ZScore > @PositiveZScoreThreshold AND (PreviousZScore < @NegativeZScoreThreshold OR NextZScore < @NegativeZScoreThreshold) THEN 0
				ELSE 1
			END AS SenseCheck

		FROM Adjacents

	)

	UPDATE Z

	SET Z.SenseCheck = C.SenseCheck

	FROM dbo.Zone AS Z

	INNER JOIN dbo.MergedLapData AS L
	ON Z.LapId = L.LapId

	LEFT JOIN SenseCheck AS C
	ON Z.LapId = C.LapId
	AND Z.ZoneNumber = C.ZoneNumber

	WHERE L.SessionId = @SessionId


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

	FROM dbo.MergedTelemetry AS T

	WHERE T.SessionId = @SessionId
	AND T.[Source] = 'car'
	AND T.LapId IS NOT NULL

END
GO