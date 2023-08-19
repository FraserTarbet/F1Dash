USE F1DashStreamline
GO

DROP PROCEDURE IF EXISTS dbo.Get_MaxId
GO
CREATE PROCEDURE dbo.Get_MaxId @TableName VARCHAR(MAX)
AS
BEGIN
	DECLARE @sql NVARCHAR(MAX)
	SET @sql = 'SELECT COALESCE(MAX(id), 0) AS MaxId FROM ' + @TableName + ';'
	EXEC (@sql)
END
GO

DROP PROCEDURE IF EXISTS dbo.Get_LastEventDateWithData
GO
CREATE PROCEDURE dbo.Get_LastEventDateWithData
AS
BEGIN
	
	-- Note: Event dates seem to be arbitrary, don't match to session dates

	DECLARE @MaxCompletedSessionDate DATETIME
		,@DeleteFromDate DATETIME

	SET @MaxCompletedSessionDate = (
		SELECT MAX(SessionDate)
		FROM dbo.Session
		WHERE LoadStatus IS NOT NULL
	)

	IF @MaxCompletedSessionDate IS NULL

		SELECT '1900-01-01 00:00:00';

	ELSE 

		SELECT E.EventDate

		FROM dbo.Event AS E

		INNER JOIN dbo.Session AS S
		ON E.id = S.EventId

		WHERE S.SessionDate = @MaxCompletedSessionDate;

END
GO

DROP PROCEDURE IF EXISTS dbo.Get_SessionsToLoad
GO
CREATE PROCEDURE dbo.Get_SessionsToLoad @ForceEventId INT = NULL, @ForceSessionId INT = NULL
AS
BEGIN

	DECLARE @SinceDate DATETIME = (
		SELECT CAST([Value] + ' 00:00:00' AS DATETIME)

		FROM dbo.Config_App

		WHERE Parameter = 'OldestDateToLoad'
	)
	,@MaxAbortedLoads INT = (
		SELECT CAST([Value] AS INT)

		FROM dbo.Config_App

		WHERE Parameter = 'MaxAbortedLoads'
	)
	,@HoursToWaitBeforeLoading INT = (
		SELECT CAST([Value] AS INT)

		FROM dbo.Config_App

		WHERE Parameter = 'HoursToWaitBeforeLoading'
	)
	,@HoursToAttemptLoading INT = (
		SELECT CAST([Value] AS INT)

		FROM dbo.Config_App

		WHERE Parameter = 'HoursToAttemptLoading'
	)

	
	SELECT S.id AS SessionId
		,EventId
		,EventName
		,EventDate
		,SessionName
		,SessionDate

	FROM dbo.Session AS S

	INNER JOIN dbo.Event AS E
	ON S.EventId = E.id

	LEFT JOIN dbo.UTCOffsets AS O
	ON E.Country = O.Country
	AND E.Location = O.Location

	WHERE (
		@ForceEventId IS NULL
		AND @ForceSessionId IS NULL
		AND DATEADD(HOUR, -COALESCE(O.UTCOffset, 0) + @HoursToWaitBeforeLoading, SessionDate) < GETDATE()
		AND (LoadStatus = 0  OR LoadStatus IS NULL)
		AND F1ApiSupport = 1
		AND SessionDate >= @SinceDate
		AND NOT (AbortedLoadCount > @MaxAbortedLoads AND DATEDIFF(HOUR, DATEADD(HOUR, -COALESCE(O.UTCOffset, 0) + @HoursToWaitBeforeLoading, SessionDate), GETDATE()) > @HoursToAttemptLoading)
	)
	OR (
		E.id = @ForceEventId
		AND S.id = @ForceSessionId
		AND F1ApiSupport = 1
	)

END
GO


DROP PROCEDURE IF EXISTS dbo.Get_SessionsToTransform
GO
CREATE PROCEDURE dbo.Get_SessionsToTransform @ForceEventId INT = NULL, @ForceSessionId INT = NULL
AS
BEGIN

	DECLARE @SinceDate DATETIME = (
		SELECT CAST([Value] + ' 00:00:00' AS DATETIME)

		FROM dbo.Config_App

		WHERE Parameter = 'OldestDateToLoad'
	)


	SELECT S.id AS SessionId
		,EventId
		,EventName
		,EventDate
		,SessionName
		,SessionDate

	FROM dbo.Session AS S

	INNER JOIN dbo.Event AS E
	ON S.EventId = E.id

	WHERE (
		@ForceEventId IS NULL
		AND @ForceSessionId IS NULL
		AND TransformStatus IS NULL -- Won't try to run on previously failed loads (0)
		AND LoadStatus = 1 -- Only transform once session is fully loaded
		AND F1ApiSupport = 1
		AND SessionDate >= @SinceDate
	)
	OR (
		E.id = @ForceEventId
		AND S.id = @ForceSessionId
		AND F1ApiSupport = 1
	)
END
GO


DROP PROCEDURE IF EXISTS dbo.Logging_Data
GO
CREATE PROCEDURE dbo.Logging_Data @HostName NVARCHAR(MAX), @Message NVARCHAR(MAX)
AS
BEGIN
	INSERT INTO dbo.log_data(HostName, LogMessage)
	VALUES (@HostName, @Message)
END
GO


DROP PROCEDURE IF EXISTS dbo.Logging_App
GO
CREATE PROCEDURE dbo.Logging_App @HostName NVARCHAR(MAX), @ClientInfo NVARCHAR(MAX), @Type VARCHAR(MAX), @Message NVARCHAR(MAX)
AS
BEGIN
	INSERT INTO dbo.Log_App(HostName, ClientInfo, LogType, LogMessage)
	VALUES (@HostName, @ClientInfo, @Type, @Message)
END
GO


DROP PROCEDURE IF EXISTS dbo.Truncate_Schedule
GO
CREATE PROCEDURE dbo.Truncate_Schedule @ClearAll BIT
AS
BEGIN

	-- Check for most recent EVENT with data for any session
	-- i.e. Once an event starts receiving data, the schedule is crystalised

	DECLARE @MaxCompletedSessionDate DATETIME
		,@DeleteFromDate DATETIME

	SET @MaxCompletedSessionDate = (
		SELECT MAX(SessionDate)
		FROM dbo.Session
		WHERE LoadStatus IS NOT NULL
	)

	SET @DeleteFromDate = (
		SELECT MAX(SessionDate)
		FROM dbo.Session AS E
		INNER JOIN (
			SELECT EventId
			FROM dbo.Session
			WHERE SessionDate = @MaxCompletedSessionDate
		) AS S
		ON E.EventId = S.EventId
	)

	DELETE E
	FROM dbo.Event AS E
	INNER JOIN dbo.Session AS S
	ON E.id = S.EventId
	WHERE S.SessionDate > @DeleteFromDate
	OR @DeleteFromDate IS NULL
	OR @ClearAll = 1

	DELETE
	FROM dbo.Session
	WHERE SessionDate > @DeleteFromDate
	OR @DeleteFromDate IS NULL
	OR @ClearAll = 1

END
GO


DROP PROCEDURE IF EXISTS dbo.Get_TelemetryRowCounts
GO
CREATE PROCEDURE dbo.Get_TelemetryRowCounts @SessionId INT
AS
BEGIN

	SELECT S.id AS SessionId
		,COALESCE(Lap.Records, 0) AS Laps
		,COALESCE(Sector.Records, 0) AS Sectors
		,COALESCE(TimingData.Records, 0) AS TimingData
		,COALESCE(CarData.Records, 0) AS CarData
		,COALESCE(PositionData.Records, 0) AS PositionData
		,COALESCE(TrackStatus.Records, 0) AS TrackStatus
		,COALESCE(SessionStatus.Records, 0) AS SessionStatus
		,COALESCE(DriverInfo.Records, 0) AS DriverInfo
		,COALESCE(WeatherData.Records, 0) AS WeatherData

	FROM dbo.Session AS S

	LEFT JOIN (SELECT SessionId, COUNT(*) AS Records FROM dbo.Lap WHERE SessionId = @SessionId GROUP BY SessionId) AS Lap
	ON S.id = Lap.SessionId

	LEFT JOIN (SELECT SessionId, COUNT(*) AS Records FROM dbo.Sector WHERE SessionId = @SessionId GROUP BY SessionId) AS Sector
	ON S.id = Sector.SessionId

	LEFT JOIN (SELECT SessionId, COUNT(*) AS Records FROM dbo.TimingData WHERE SessionId = @SessionId GROUP BY SessionId) AS TimingData
	ON S.id = TimingData.SessionId

	LEFT JOIN (SELECT SessionId, COUNT(*) AS Records FROM dbo.CarData WHERE SessionId = @SessionId GROUP BY SessionId) AS CarData
	ON S.id = CarData.SessionId

	LEFT JOIN (SELECT SessionId, COUNT(*) AS Records FROM dbo.PositionData WHERE SessionId = @SessionId GROUP BY SessionId) AS PositionData
	ON S.id = PositionData.SessionId

	LEFT JOIN (SELECT SessionId, COUNT(*) AS Records FROM dbo.TrackStatus WHERE SessionId = @SessionId GROUP BY SessionId) AS TrackStatus
	ON S.id = TrackStatus.SessionId

	LEFT JOIN (SELECT SessionId, COUNT(*) AS Records FROM dbo.SessionStatus WHERE SessionId = @SessionId GROUP BY SessionId) AS SessionStatus
	ON S.id = SessionStatus.SessionId

	LEFT JOIN (SELECT SessionId, COUNT(*) AS Records FROM dbo.DriverInfo WHERE SessionId = @SessionId GROUP BY SessionId) AS DriverInfo
	ON S.id = DriverInfo.SessionId

	LEFT JOIN (SELECT SessionId, COUNT(*) AS Records FROM dbo.WeatherData WHERE SessionId = @SessionId GROUP BY SessionId) AS WeatherData
	ON S.id = WeatherData.SessionId

	WHERE S.id = @SessionId

END
GO

DROP PROCEDURE IF EXISTS dbo.Delete_Telemetry 
GO
CREATE PROCEDURE dbo.Delete_Telemetry @SessionId INT
AS
BEGIN
	DELETE S FROM dbo.Sector AS S
	INNER JOIN dbo.Lap AS L
	ON S.LapId = L.id
	WHERE L.SessionId = @SessionId;

	DELETE FROM dbo.Lap
	WHERE SessionId = @SessionId

	DELETE FROM dbo.TimingData
	WHERE SessionId = @SessionId

	DELETE FROM dbo.CarData
	WHERE SessionId = @SessionId

	DELETE FROM dbo.PositionData
	WHERE SessionId = @SessionId

	DELETE FROM dbo.TrackStatus
	WHERE SessionId = @SessionId

	DELETE FROM dbo.SessionStatus
	WHERE SessionId = @SessionId

	DELETE FROM dbo.DriverInfo
	WHERE SessionId = @SessionId

	DELETE FROM dbo.WeatherData
	WHERE SessionId = @SessionId

END
GO

DROP PROCEDURE IF EXISTS dbo.Update_SessionLoadStatus
GO
CREATE PROCEDURE dbo.Update_SessionLoadStatus @SessionId INT, @Status BIT
AS
BEGIN
	UPDATE dbo.Session
	SET LoadStatus = @Status
		,LoadStatusUpdatedDateTime = GETDATE()
	WHERE id = @SessionId
END
GO


DROP PROCEDURE IF EXISTS dbo.Update_SessionTransformStatus
GO
CREATE PROCEDURE dbo.Update_SessionTransformStatus @SessionId INT, @Status BIT
AS
BEGIN
	UPDATE dbo.Session
	SET TransformStatus = @Status
		,TransformStatusUpdatedDateTime = GETDATE()
	WHERE id = @SessionId
END
GO


DROP PROCEDURE IF EXISTS dbo.Update_SetNullTimes
GO
CREATE PROCEDURE dbo.Update_SetNullTimes @SessionId INT
AS
BEGIN
	-- This function exists because numpy deltatime NaT values seem to appear in SQL as negatives - should be nulls
	UPDATE dbo.Lap SET LapTime = NULL WHERE LapTime < 0 AND SessionId = @SessionId
	UPDATE dbo.Lap SET PitOutTime = NULL WHERE PitOutTime < 0 AND SessionId = @SessionId
	UPDATE dbo.Lap SET PitInTime = NULL WHERE PitInTime < 0 AND SessionId = @SessionId

	UPDATE dbo.CarData SET [Time] = NULL WHERE [Time] < 0 AND SessionId = @SessionId
	UPDATE dbo.PositionData SET [Time] = NULL WHERE [Time] < 0 AND SessionId = @SessionId

	UPDATE dbo.TimingData SET [LapTime] = NULL WHERE [LapTime] < 0 AND SessionId = @SessionId
	UPDATE dbo.TimingData SET [Time] = NULL WHERE [Time] < 0 AND SessionId = @SessionId

END
GO


DROP PROCEDURE IF EXISTS dbo.Get_SessionDrivers
GO
CREATE PROCEDURE dbo.Get_SessionDrivers @SessionId INT
AS
BEGIN
	SELECT RacingNumber

	FROM dbo.DriverInfo

	WHERE SessionId = @SessionId
END
GO


DROP PROCEDURE IF EXISTS dbo.Update_SetDriverTeamOrders
GO
CREATE PROCEDURE dbo.Update_SetDriverTeamOrders @SessionId INT
AS
BEGIN

	UPDATE D

	SET D.DriverOrder = O.DriverOrder
		,D.TeamOrder = O.TeamOrder

	FROM dbo.DriverInfo AS D
	INNER JOIN (

		SELECT D.SessionId
			,D.RacingNumber
			,ROW_NUMBER() OVER(PARTITION BY D.TeamName ORDER BY D.Line ASC) AS DriverOrder
			,T.TeamOrder

		FROM dbo.DriverInfo AS D

		INNER JOIN (
			SELECT TeamName
				,ROW_NUMBER() OVER(ORDER BY MIN(Line) ASC) AS TeamOrder

			FROM dbo.DriverInfo

			WHERE SessionId = @SessionId

			GROUP BY TeamName
		) AS T
		ON D.TeamName = T.TeamName

		WHERE D.SessionId = @SessionId

	) AS O
	ON D.SessionId = O.SessionId
	AND D.RacingNumber = O.RacingNumber

END
GO


DROP PROCEDURE IF EXISTS dbo.Insert_MissingSectors
GO
CREATE PROCEDURE dbo.Insert_MissingSectors @SessionId INT
AS
BEGIN

	/*
		Occasionally the first sector time is missing for otherwise valid laps.
		I don't know why this happens.
		Simple enough to calculate the time based on total lap and the other two sectors and insert into sector table.
	*/

	INSERT INTO dbo.Sector(
		LapId
		,SectorNumber
		,SectorTime
		,SectorSessionTime
	)
	SELECT LapId
		,1 AS SectorNumber
		,LapTime - SectorTimeSum AS SectorTime
		,Sector2SessionTime - (LapTime - SectorTimeSum) AS SectorSessionTime

	FROM (

		SELECT L.id AS LapId
			,L.LapTime
			,L.PitInTime
			,L.PitOutTime
			,SUM(S.SectorTime) AS SectorTimeSum
			,SUM(CASE WHEN S.SectorNumber = 2 THEN S.SectorSessionTime ELSE 0 END) AS Sector2SessionTime

		FROM dbo.Lap AS L

		INNER JOIN dbo.Sector AS S
		ON L.id = S.LapId

		WHERE L.LapTime IS NOT NULL
		AND L.SessionId = @SessionId

		GROUP BY L.id
			,L.LapTime
			,L.PitInTime
			,L.PitOutTime

		HAVING COUNT(S.SectorNumber) = 2

	) AS A


END
GO


DROP PROCEDURE IF EXISTS dbo.Update_IncrementAbortedLoadCount
GO
CREATE PROCEDURE dbo.Update_IncrementAbortedLoadCount @SessionId INT
AS
BEGIN
	UPDATE dbo.Session

	SET AbortedLoadCount =  AbortedLoadCount + 1

	WHERE id = @SessionId
END
GO


DROP PROCEDURE IF EXISTS dbo.Cleanup_RawTelemetry
GO
CREATE PROCEDURE dbo.Cleanup_RawTelemetry
AS
BEGIN
	
	/*
		Once the raw telemetry data has been used for transforms, it can be deleted from the database.
		Will prevent the raw tables from getting too large and slowing down loads later on.
		Don't delete immediately, in case there's something that needs investigating. Only delete once the next event starts being loaded.
	*/

	DECLARE @CurrentEvent INT
	DECLARE @SessionsToDelete TABLE(
			id INT
		)

	SET @CurrentEvent = (SELECT MAX(EventId) FROM dbo.Session WHERE LoadStatus = 1)


	INSERT INTO @SessionsToDelete 

	SELECT id

	FROM dbo.Session

	WHERE EventId < @CurrentEvent
	AND LoadStatus = 1
	AND TransformStatus = 1


	DELETE FROM dbo.CarData WHERE SessionId IN (SELECT id FROM @SessionsToDelete)
	DELETE FROM dbo.PositionData WHERE SessionId IN (SELECT id FROM @SessionsToDelete)

END
GO