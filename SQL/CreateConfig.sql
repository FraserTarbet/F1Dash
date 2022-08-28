USE F1DashStreamline


DROP TABLE IF EXISTS dbo.Config_App
GO
CREATE TABLE dbo.Config_App(
	[Parameter] VARCHAR(MAX)
	,[Value] VARCHAR(MAX)
)

INSERT INTO dbo.Config_App(
	[Parameter]
	,[Value]
)
VALUES
('RunLightVersion', '0')
,('EnableDatabaseThread', '0')
,('EnableCacheCleanupThread', '0')
,('OldestDateToLoad', '2022-01-01')
,('MaxAbortedLoads', '3')
,('HoursToWaitBeforeLoading', '0')
,('DetectMobileWidth', '800')
,('DetectMobileHeight', '600')
,('MaxFileStoreSizeInGB', '2')
,('CacheFileDeleteDelayInHours', '2')
,('DatabaseThreadSleepInHours', '0.5')
,('CacheThreadSleepInHours', '1')
,('ThreadMaxWakeupDelayInSeconds', '60')
,('HoursToAttemptLoading', '6')