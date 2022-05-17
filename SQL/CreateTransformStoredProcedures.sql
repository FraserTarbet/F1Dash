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

	INTO #SampleLap

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


	-- Create identifiers for sequence of brakes/gears in each lap, and add DRS start/end fields

	;WITH A AS(
		SELECT *
			,ROW_NUMBER() OVER(ORDER BY [Time] ASC) AS RN
			,CASE WHEN Brake = 1 THEN -1 ELSE Gear END AS BrakeOrGear
			,CASE WHEN DRS IN (0, 8) OR DRS % 2 <> 0 THEN 0 ELSE 1 END AS DRSActive -- Documentation light on meaning of different DRS flags, might need revisiting
		FROM #SampleLap
	)
	,B AS (
		SELECT *
			,CASE WHEN LAG(BrakeOrGear, 1, 0) OVER(PARTITION BY LapId ORDER BY RN ASC) <> BrakeOrGear THEN RN ELSE NULL END AS BrakeOrGearStart
			,CASE WHEN LAG(DRSActive, 1, NULL) OVER(ORDER BY RN ASC) <> DRSActive AND DRSActive = 1 THEN 1 ELSE 0 END AS DRSOpen
			,CASE WHEN LAG(DRSActive, 1, NULL) OVER(ORDER BY RN ASC) <> DRSActive AND DRSActive = 0 THEN 1 ELSE 0 END AS DRSClose
		FROM A
	)
	,C AS (
		SELECT *
			,COUNT(BrakeOrGearStart) OVER(ORDER BY RN ASC) AS BrakeOrGearId
		FROM B
	)
	SELECT *

	INTO #InsertRecords

	FROM C


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
		,BrakeOrGearId
		,BrakeOrGear
		,DRSOpen
		,DRSClose
		,DRSActive
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
		,BrakeOrGearId
		,BrakeOrGear
		,DRSOpen
		,DRSClose
		,DRSActive

	FROM #InsertRecords

	ORDER BY [Time] ASC


	-- Update NearestNonSourceId (running after insert in order to use incremental PK)

	;WITH A AS (
		SELECT id
			,[Source]
			,[Time]
			,ROW_NUMBER() OVER(ORDER BY [Time] ASC) AS RN

		FROM dbo.MergedTelemetry

		WHERE SessionId = @SessionId
		AND Driver = @Driver
	)
	,B AS (
		SELECT *
			,CASE
				WHEN LAG([Source], 1, '') OVER(ORDER BY RN ASC) <> [Source] THEN RN
				ELSE NULL
			END AS GroupStart
		FROM A
	)
	,C AS (
		SELECT *
			,MAX(GroupStart) OVER(ORDER BY RN ASC) AS GroupNumber
		FROM B
	)
	,D AS (
		SELECT *
			,COUNT(RN) OVER(PARTITION BY GroupNumber) AS GroupSize
			,COUNT(RN) OVER(PARTITION BY GroupNumber ORDER BY RN ASC) AS GroupSeq
		FROM C
	)
	,E AS (
		SELECT *
			,[Time] - LAG([Time], GroupSeq, NULL) OVER(ORDER BY RN ASC) AS TimeToPre
			,LEAD([Time], GroupSize - GroupSeq + 1, NULL) OVER(ORDER BY RN ASC) - [Time] AS TimeToPost

		FROM D
	)
	SELECT id
		,CASE
			WHEN TimeToPre < TimeToPost OR TimeToPost IS NULL THEN LAG(id, GroupSeq) OVER(ORDER BY RN ASC)
			WHEN TimeToPre > TimeToPost OR TimeToPre IS NULL THEN LEAD(id, GroupSize - GroupSeq + 1, NULL) OVER(ORDER BY RN ASC)
		END AS NearestNonSourceId

	INTO #NearestNonSourceId

	FROM E


	UPDATE T

	SET T.NearestNonSourceId = I.NearestNonSourceId	
	
	FROM dbo.MergedTelemetry AS T

	INNER JOIN #NearestNonSourceId AS I
	ON T.id = I.id



	DROP TABLE #Car, #Pos, #Times, #SampleMatching, #InsertRecords, #NearestNonSourceId, #SampleLap

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
		Should be possible to cut track into braking zones/straights.
		Aggregating all clean laps might build a better picture, but for now just base on fastest (reasonable to assume the driver did well).
		Should also be possible to crudely identify sectors using sector time data from fastest lap.
	*/

	DECLARE @SessionId INT
		,@RollingWindow INT = 5 -- Specifies size of rolling windows (n preceding and n following)
		,@cmd NVARCHAR(MAX)

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


	;WITH O AS (
		SELECT *
			,ROW_NUMBER() OVER(ORDER BY LapTime ASC) AS RN

		FROM dbo.MergedLapData

		WHERE SessionId = @SessionId
		AND LapTime IS NOT NULL
		AND CleanLap = 1
		AND IsPersonalBest = 1
	)
	,Raw AS (
		SELECT O.LapId
			,ROW_NUMBER() OVER(ORDER BY [Time]) AS SampleId
			,[Time]
			,X
			,Y
			,Z
			,Gear
			,Throttle
			,Brake
			,[Time] - O.TimeStart AS LapTimeCumulative
			,O.LapTime

		FROM O

		INNER JOIN dbo.MergedTelemetry AS T
		ON O.LapId = T.LapId

		WHERE O.RN = 1
		AND T.[Source] = 'pos'
	)
	,S AS (
		SELECT R.*
			,S.SectorTimeCumulative
			,S.SectorNumber
			,ROW_NUMBER() OVER(PARTITION BY R.SampleId ORDER BY S.SectorTimeCumulative ASC) AS RNSector

		FROM Raw AS R

		LEFT JOIN (
			SELECT LapId
				,SectorNumber
				,SUM(SectorTime) OVER(PARTITION BY LapId ORDER BY SectorNumber ASC) AS SectorTimeCumulative

			FROM dbo.Sector
		) AS S
		ON R.LapId = S.LapId
		AND R.LapTimeCumulative < S.SectorTimeCumulative
	)
	SELECT LapId
		,COALESCE(SectorNumber, 3) AS SectorNumber
		,SampleId
		,[Time]
		,X
		,Y
		,Z
		,Gear
		,Throttle
		,Brake

	INTO #Samples

	FROM S

	WHERE RNSector = 1


	-- Group points based on braking and gears
	-- Use rolling averages to smooth out any choppy braking and throttle application
	-- Forced to use dynamic SQL to inject @RollingWindow in ROWS BETWEEN clauses...

	CREATE TABLE #RollingSamples(
		LapId INT
		,SectorNumber INT
		,SampleId INT
		,[Time] FLOAT
		,X INT
		,Y INT
		,Z INT
		,Gear INT
		,Throttle INT
		,Brake BIT
		,AvgGear FLOAT
		,AvgThrottle INT
		,AvgBrake FLOAT
	)

	SET @cmd = '
		INSERT INTO #RollingSamples
		SELECT *
			,AVG(CAST(Gear AS FLOAT)) OVER(ORDER BY SampleId ROWS BETWEEN ' + CAST(@RollingWindow AS VARCHAR(MAX)) + ' PRECEDING AND ' + CAST(@RollingWindow AS VARCHAR(MAX)) + ' FOLLOWING) AS AvgGear
			,AVG(Throttle) OVER(ORDER BY SampleId ROWS BETWEEN ' + CAST(@RollingWindow AS VARCHAR(MAX)) + ' PRECEDING AND ' + CAST(@RollingWindow AS VARCHAR(MAX)) + ' FOLLOWING) AS AvgThrottle
			,AVG(CAST(Brake AS FLOAT)) OVER(ORDER BY SampleId ROWS BETWEEN ' + CAST(@RollingWindow AS VARCHAR(MAX)) + ' PRECEDING AND ' + CAST(@RollingWindow AS VARCHAR(MAX)) + ' FOLLOWING) AS AvgBrake

		FROM #Samples
	'

	EXEC(@cmd)

	-- InputCategory = 0: Braking, 1: Gear < 5, 2: Gear >= 5

	;WITH Inputs AS (
		SELECT *
			,CASE
				WHEN AvgBrake > 0.2 THEN 0
				WHEN AvgGear < 5.0 THEN 1
				WHEN AvgGear >= 5.0 THEN 2
			END AS InputCategory

		FROM #RollingSamples
	)
	,GroupStart AS (
		SELECT *
			,CASE WHEN LAG(InputCategory, 1, -1) OVER(ORDER BY SampleId ASC) <> InputCategory THEN SampleId ELSE NULL END AS GroupStart
		FROM Inputs
	)
	,GroupFill AS (
		SELECT *
			,MAX(GroupStart) OVER(ORDER BY SampleId ASC) AS GroupStartId
		FROM GroupStart
	)
	,Zones AS (
		SELECT A.LapId
			,A.SectorNumber
			,A.SampleId
			,A.X
			,A.Y
			,A.Z
			,A.InputCategory
			,B.GroupId AS ZoneNumber

		FROM GroupFill AS A

		LEFT JOIN (
			SELECT GroupStartId
				,ROW_NUMBER() OVER(ORDER BY GroupStartId ASC) AS GroupId

			FROM (
				-- Don't give Id to tiny zones
				SELECT GroupStartId 
				
				FROM GroupFill 
				
				GROUP BY GroupStartId 
				
				HAVING COUNT(*) >= 5
			) AS S
		) AS B
		ON A.GroupStartId = B.GroupStartId
	)
	-- Fill in any NULL ZoneNumber from tiny zones
	SELECT LapId
		,SectorNumber
		,SampleId
		,X
		,Y
		,Z
		,InputCategory
		,CASE
			WHEN ZoneNumber IS NULL AND LEAD(ZoneNumber, 1, NULL) OVER(ORDER BY SampleId ASC) IS NULL THEN MAX(ZoneNumber) OVER(ORDER BY SampleId ASC)
			WHEN ZoneNumber IS NULL THEN MIN(ZoneNumber) OVER(ORDER BY SampleId DESC)
			ELSE ZoneNumber
		END AS ZoneNumber

	INTO #Records
	FROM Zones



	-- Delete any existing records for this @EventId
	DELETE
	FROM dbo.TrackMap
	WHERE EventId = @EventId


	-- Insert new records
	INSERT INTO dbo.TrackMap(
		EventId
		,SampleId
		,X
		,Y
		,Z
		,SectorNumber
		,ZoneNumber
		,ZoneInputCategory
	)
	SELECT @EventId
		,SampleId
		,X
		,Y
		,Z
		,SectorNumber
		,ZoneNumber
		,InputCategory AS ZoneInputCategory

	FROM #Records


	DROP TABLE #Samples, #RollingSamples, #Records

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
				WHEN ZoneTime IS NULL THEN 0
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