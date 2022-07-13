USE F1Dash

DROP PROCEDURE IF EXISTS dbo.Monitor_AppUsage
GO
CREATE PROCEDURE dbo.Monitor_AppUsage
AS
BEGIN

	/*
		Returns a simple summary of the last 24 hours of user activity from the app log.
	*/

	DECLARE @StartDateTime DATETIME
		,@EndDateTime DATETIME
		,@iDateTime DATETIME

	DECLARE @Hours TABLE(
		HourStart DATETIME
	)

	SET @EndDateTime = DATEADD(HOUR, DATEPART(HOUR, GETDATE()) + 1, CAST(CAST(GETDATE() AS DATE) AS DATETIME))
	SET @StartDateTime = DATEADD(HOUR, -24, @EndDateTime)

	SET @iDateTime = @StartDateTime
	WHILE @iDateTime < @EndDateTime
	BEGIN
		INSERT INTO @Hours
		SELECT @iDateTime

		SET @iDateTime = DATEADD(HOUR, 1, @iDateTime)
	END


	SELECT HourStart
		,SUM(CASE WHEN LogType = 'initiate' THEN 1 ELSE 0 END) AS Initiate
		,SUM(CASE WHEN LogType = 'initiate' AND AppVersion = 'Desktop' THEN 1 ELSE 0 END) AS Initiate_Desktop
		,SUM(CASE WHEN LogType = 'initiate' AND AppVersion = 'Mobile' THEN 1 ELSE 0 END) AS Initiate_Mobile
		,SUM(CASE WHEN LogType = 'request_datasets' THEN 1 ELSE 0 END) AS Request
		,SUM(CASE WHEN LogType = 'request_datasets' AND AppVersion = 'Desktop' THEN 1 ELSE 0 END) AS Request_Desktop
		,SUM(CASE WHEN LogType = 'request_datasets' AND AppVersion = 'Mobile' THEN 1 ELSE 0 END) AS Request_Mobile

	FROM @Hours AS H

	LEFT JOIN(
		SELECT LogDateTime
			,LogType
			,CASE
				WHEN RIGHT(ClientInfo, 5) = 'True}' THEN 'Mobile'
				ELSE 'Desktop'
			END AS AppVersion

		FROM dbo.Log_App

		WHERE LogType IN ('initiate', 'request_datasets')
	) AS L
	ON H.HourStart <= L.LogDateTime
	AND DATEADD(HOUR, 1, H.HourStart) > L.LogDateTime

	GROUP BY HourStart

	ORDER BY HourStart DESC

END
GO


DROP PROCEDURE IF EXISTS dbo.Monitor_RecentDataLogs
GO
CREATE PROCEDURE dbo.Monitor_RecentDataLogs
AS
BEGIN

	/*
		Get recent data logs
	*/

	SELECT TOP 200 *

	FROM dbo.Log_Data

	ORDER BY LogDateTime DESC

END
GO


DROP PROCEDURE IF EXISTS dbo.Monitor_RecentAppLogs
GO
CREATE PROCEDURE dbo.Monitor_RecentAppLogs
AS
BEGIN

	/*
		Get recent app logs
	*/

	SELECT TOP 200 *

	FROM dbo.Log_App

	ORDER BY LogDateTime DESC

END
GO