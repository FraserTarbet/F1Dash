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
	-- TODO: Write procedure
	SELECT '1900-01-01 00:00:00'
END
GO

DROP PROCEDURE IF EXISTS dbo.Get_SessionsToUpdate
GO
CREATE PROCEDURE dbo.Get_SessionsToUpdate @ForceEventId INT = NULL, @ForceSessionId INT = NULL
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

	-- TODO: Change to check for most recent race with data
	-- Return number of deleted rows

	SELECT id
	INTO #Deletes
	FROM dbo.Event
	WHERE EventDate > GETDATE()
	OR @ClearAll = 1

	DELETE 
	FROM dbo.Event
	WHERE id IN (SELECT id FROM #Deletes)

	DELETE
	FROM dbo.Session
	WHERE EventId in (SELECT id FROM #Deletes)

	DROP TABLE #Deletes

END
GO

DROP PROCEDURE IF EXISTS dbo.Get_TelemetryRowCounts
GO
CREATE PROCEDURE dbo.Get_TelemetryRowCounts @SessionId INT
AS
BEGIN
	SELECT S.id AS SessionId
		,COALESCE(COUNT(Lap.id), 0) AS Laps
		,COALESCE(COUNT(Sector.id), 0) AS Sectors
		,COALESCE(COUNT(SpeedTrap.id), 0) AS SpeedTraps
		,COALESCE(COUNT(TimingData.id), 0) AS TimingData
		,COALESCE(COUNT(CarData.SessionId), 0) AS CarData

	FROM dbo.Session AS S

	LEFT JOIN dbo.Lap AS Lap
	ON S.id = Lap.SessionId

	LEFT JOIN dbo.Sector AS Sector
	ON Lap.id = Sector.LapId

	LEFT JOIN dbo.SpeedTrap AS SpeedTrap
	ON Lap.id = SpeedTrap.LapId

	LEFT JOIN dbo.TimingData AS TimingData
	ON S.id = TimingData.SessionId

	LEFT JOIN dbo.CarData AS CarData
	ON S.id = CarData.SessionId

	WHERE S.id = @SessionId

	GROUP BY S.id
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
END

DROP PROCEDURE IF EXISTS dbo.Update_SessionLoadStatus
GO
CREATE PROCEDURE dbo.Update_SessionLoadStatus @SessionId INT, @Status BIT
AS
BEGIN
	UPDATE dbo.Session
	SET LoadStatus = @Status
		,LoadStatusUpdatedDateTime = GETDATE()
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

END
GO