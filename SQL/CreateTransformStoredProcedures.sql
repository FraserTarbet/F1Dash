USE F1Dash

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

	-- Use 107% rule to identify laps too slow to be clean
	DECLARE @CleanLapTimeThreshold FLOAT

	SET @CleanLapTimeThreshold = (
		SELECT MIN(LapTime) * 1.07

		FROM dbo.Lap

		WHERE SessionId = @SessionId
	)

	-- Clear out existing data for this session from dbo.MergedLapData
	DELETE
	FROM dbo.MergedLapData
	WHERE SessionId = @SessionId


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
	)
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
		,Compound
		,COUNT(Lap.LapId) OVER(PARTITION BY Driver, CompId ORDER BY NumberOfLaps ASC) + TyreAgeWhenFitted AS TyreAge
		,TrackStatus
		,CASE
			WHEN TrackStatus <> 'AllClear' THEN 0
			WHEN LapTime > @CleanLapTimeThreshold THEN 0
			WHEN COALESCE(PitOutTime, PitInTime) IS NOT NULL THEN 0
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

	ORDER BY TimeStart ASC

END
GO


DROP PROCEDURE IF EXISTS dbo.Merge_Telemetry
GO
CREATE PROCEDURE dbo.Merge_Telemetry @SessionId INT, @Driver INT
AS
BEGIN

	/*
		Telemetry data [Time] fields are not accurate - the same value is repeated for a window of multiple samples.
		The [Date] field, however, is understood to be accurate, but cannot be related back to lap data (which only includes [Time]...!).
		To attempt to slice telemetry into laps, will use [Time] to offset session data as a whole while using [Date] to get correct deltas etc.

		This procedure requires MergedLapData to be updated beforehand.
		Needs to be run per-driver for now, since it is quite heavy and this is all being tested.
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


	-- Select session telemetry data into temp tables with adjusted [Time] fields
	-- Keeping originals for debugging later

	SELECT SessionId
		,Driver
		,[Time] AS DiscardedTime
		,[Date] AS DiscardedDate
		,DATEDIFF(MILLISECOND, @SessionZeroDate, [Date]) * CAST(1000000 AS FLOAT) AS [Time]
		,RPM
		,Speed
		,Gear
		,Throttle
		,Brake
		,DRS
		,[Source]

	INTO #Car

	FROM dbo.CarData

	WHERE [Time] IS NOT NULL
	AND SessionId = @SessionId
	AND Driver = @Driver


	SELECT SessionId
		,Driver
		,[Time] AS DiscardedTime
		,[Date] AS DiscardedDate
		,DATEDIFF(MILLISECOND, @SessionZeroDate, [Date]) * CAST(1000000 AS FLOAT) AS [Time]
		,[Status]
		,X
		,Y
		,Z
		,[Source]

	INTO #Pos

	FROM dbo.PositionData

	WHERE [Time] IS NOT NULL
	AND SessionId = @SessionId
	AND Driver = @Driver

	-- Index the temp tables to speed up some costly joins coming up
	CREATE CLUSTERED INDEX IndexTime ON #Car ([Time])
	CREATE CLUSTERED INDEX IndexTime ON #Pos ([Time])

	-----------
	-- Interpolate based on surrounding rows in opposite dataset
	-- RPM, positions etc. will be linear, gear/brake/DRS carried forward
	-----------

	-- Get times of records in opposite dataset immediately before/after current

	SELECT ROW_NUMBER() OVER(ORDER BY [Time] ASC) AS id
		,*
	INTO #Times
	FROM (
		SELECT SessionId
			,Driver
			,[Time]
			,[Source]
		FROM #Car
		UNION ALL
		SELECT SessionId
			,Driver
			,[Time]
			,[Source]
		FROM #Pos
	) AS U
	ORDER BY [Time] ASC


	;WITH A AS (
		SELECT *
			,CASE 
				WHEN LAG([Source], 1, NULL) OVER(ORDER BY id ASC) <> [Source] THEN id 
				WHEN LAG([Source], 1, NULL) OVER(ORDER BY id ASC) IS NULL THEN id
				ELSE NULL 
			END AS GroupStart
		FROM #Times
	)
	,B AS (
		SELECT *
			,MAX(GroupStart) OVER(ORDER BY id ASC) AS GroupNumber
		FROM A
	)
	,C AS (
		SELECT *
			,COUNT(id) OVER(PARTITION BY GroupNumber) AS GroupSize
			,COUNT(id) OVER(PARTITION BY GroupNumber ORDER BY id ASC) AS GroupSeq
		FROM B
	)
	SELECT *
		,LAG([Time], GroupSeq, NULL) OVER(ORDER BY id ASC) AS TimePre
		,LEAD([Time], GroupSize - GroupSeq + 1, NULL) OVER(ORDER BY id ASC) AS TimePost

	INTO #SampleMatching
	FROM C


	-- Join to identified records and interpolate, union and join to get lap key/pitlane

	SELECT T.*
		,T.[Time] - LAG(T.[Time], 1, NULL) OVER(ORDER BY [Time] ASC) AS TimeSinceLastSample
		,L.LapId
		,CASE WHEN P.PitInTime IS NOT NULL THEN 1 ELSE 0 END AS InPits

	INTO #InsertRecords

	FROM (

		SELECT C.SessionId
			,C.Driver
			,C.DiscardedTime
			,C.DiscardedDate
			,C.[Time]
			,C.[Source]
			,CASE
				WHEN Pre.[Time] IS NULL THEN Post.[Status]
				ELSE Pre.[Status]
			END AS [Status]
			,dbo.Interpolate(C.[Time], Pre.[Time], Post.[Time], Pre.X, Post.X) AS X
			,dbo.Interpolate(C.[Time], Pre.[Time], Post.[Time], Pre.Y, Post.Y) AS Y
			,dbo.Interpolate(C.[Time], Pre.[Time], Post.[Time], Pre.Z, Post.Z) AS Z
			,C.RPM
			,C.Speed
			,C.Gear
			,C.Throttle
			,C.Brake
			,C.DRS
	
		FROM #Car AS C

		LEFT JOIN #SampleMatching AS M
		ON C.[Time] = M.[Time]
		AND C.[Source] = 'car'

		LEFT JOIN #Pos AS Pre
		ON M.Driver = Pre.Driver
		AND M.TimePre = Pre.[Time]

		LEFT JOIN #Pos AS Post
		ON M.Driver = Post.Driver
		AND M.TimePost = Post.Time

		UNION ALL
		SELECT T.SessionId
			,T.Driver
			,T.DiscardedTime
			,T.DiscardedDate
			,T.[Time]
			,T.[Source]
			,T.[Status]
			,T.X
			,T.Y
			,T.Z
			,dbo.Interpolate(T.[Time], Pre.[Time], Post.[Time], Pre.RPM, Post.RPM) AS X
			,dbo.Interpolate(T.[Time], Pre.[Time], Post.[Time], Pre.Speed, Post.Speed) AS X
			,CASE
				WHEN Pre.[Time] IS NULL THEN Post.Gear
				ELSE Pre.Gear
			END AS Gear
			,dbo.Interpolate(T.[Time], Pre.[Time], Post.[Time], Pre.Throttle, Post.Throttle) AS X
			,CASE
				WHEN Pre.[Time] IS NULL THEN Post.Brake
				ELSE Pre.Brake
			END AS Brake
			,CASE
				WHEN Pre.[Time] IS NULL THEN Post.DRS
				ELSE Pre.DRS
			END AS DRS

		FROM #Pos AS T

		LEFT JOIN #SampleMatching AS M
		ON T.[Time] = M.[Time]
		AND M.[Source] = 'pos'

		LEFT JOIN #Car AS Pre
		ON M.Driver = Pre.Driver
		AND M.TimePre = Pre.[Time]

		LEFT JOIN #Car AS Post
		ON M.Driver = Post.Driver
		AND M.TimePost = Post.Time

	) AS T

	LEFT JOIN (
		SELECT LapId
			,TimeStart
			,TimeEnd

		FROM dbo.MergedLapData

		WHERE SessionId = @SessionId
		AND Driver = @Driver
	) AS L
	ON T.[Time] >= L.TimeStart
	AND T.[Time] < L.TimeEnd

	LEFT JOIN (
		SELECT PitOutTime
			,LAG(PitInTime, 1, NULL) OVER(ORDER BY TimeEnd) AS PitInTime

		FROM dbo.MergedLapData

		WHERE SessionId = @SessionId
		AND Driver = @Driver
	) AS P
	ON (T.[Time] >= P.PitInTime OR P.PitInTime IS NULL)
	AND T.[Time] < P.PitOutTime
	AND P.PitOutTime IS NOT NULL


	-- Clear existing session/driver data
	DELETE
	FROM dbo.MergedTelemetry
	WHERE SessionId = @SessionId
	AND Driver = @Driver


	-- Insert new records
	INSERT INTO dbo.MergedTelemetry (
		SessionId
		,Driver
		,LapId
		,InPits
		,[Time]
		,TimeSinceLastSample
		,[Source]
		,[Status]
		,X
		,Y
		,Z
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
		,InPits
		,[Time]
		,TimeSinceLastSample
		,[Source]
		,[Status]
		,X
		,Y
		,Z
		,RPM
		,Speed
		,Gear
		,Throttle
		,Brake
		,DRS

	FROM #InsertRecords


	DROP TABLE #Car, #Pos, #Times, #SampleMatching, #InsertRecords

END
GO