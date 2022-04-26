USE F1Dash
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
		AND SessionDate < GETDATE()
		AND (LoadStatus = 0  OR LoadStatus IS NULL)
		AND F1ApiSupport = 1
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
		AND SessionDate < GETDATE()
		AND TransformStatus IS NULL -- Won't try to run on previously failed loads (0)
		AND LoadStatus = 1 -- Only transform once session is fully loaded
		AND F1ApiSupport = 1
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
		,COALESCE(SpeedTrap.Records, 0) AS SpeedTraps
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

	LEFT JOIN (
		SELECT L.SessionId, COUNT(S.id) AS Records 
		FROM dbo.Lap AS L
		INNER JOIN dbo.Sector AS S
		ON L.id = S.LapId
		WHERE SessionId = @SessionId
		GROUP BY L.SessionId
	) AS Sector
	ON S.id = Sector.SessionId

	LEFT JOIN (
		SELECT L.SessionId, COUNT(T.id) AS Records 
		FROM dbo.Lap AS L
		INNER JOIN dbo.SpeedTrap AS T
		ON L.id = T.LapId
		WHERE SessionId = @SessionId
		GROUP BY L.SessionId
	) AS SpeedTrap
	ON S.id = SpeedTrap.SessionId

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

	DELETE S FROM dbo.SpeedTrap AS S
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