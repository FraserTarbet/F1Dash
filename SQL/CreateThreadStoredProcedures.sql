
DROP PROCEDURE IF EXISTS dbo.Thread_Checkin
GO
CREATE PROCEDURE dbo.Thread_Checkin @CheckinType VARCHAR(MAX), @HostName VARCHAR(MAX), @WorkerIdentifier VARCHAR(MAX)
AS BEGIN

	/*
		Checks for recently active threads
		Used to determine whether calling thread should pick up process
	*/
	
	DECLARE @TimeAllowance DATETIME
		,@LastHostName VARCHAR(MAX)
		,@LastWorkerIdentifier VARCHAR(MAX)

	SET @TimeAllowance = (
		SELECT  (CAST([Value] AS FLOAT) / 24) * 2 -- Allow twice the thread sleep time before taking over

		FROM dbo.Config_App

		WHERE (@CheckinType = 'Database' AND [Parameter] = 'DatabaseThreadSleepInHours')
		OR (@CheckinType = 'Cache' AND [Parameter] = 'CacheThreadSleepInHours')
	)


	SELECT @LastHostName = HostName
		,@LastWorkerIdentifier = WorkerIdentifier

	FROM (
	
		SELECT CheckinDateTime
			,HostName
			,WorkerIdentifier
			,ROW_NUMBER() OVER(ORDER BY CheckinDateTime DESC) AS RN

		FROM dbo.ThreadCheckin
		
		WHERE CheckinType = @CheckinType
		AND CheckinDateTime >= GETDATE() - @TimeAllowance

	) AS A

	WHERE RN = 1


	IF (@LastHostName = @HostName AND @LastWorkerIdentifier = @WorkerIdentifier) OR @LastHostName IS NULL
	BEGIN

		INSERT INTO dbo.ThreadCheckin(
			CheckinType
			,HostName
			,WorkerIdentifier
		)
		VALUES
		(@CheckinType
		,@HostName
		,@WorkerIdentifier
		)

		SELECT 1 AS Result
	END
	ELSE
	BEGIN
		SELECT 0 AS Result
	END

END