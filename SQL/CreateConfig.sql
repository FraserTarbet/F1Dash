USE F1Dash


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
('ForceTestData', '0')
,('RunLightVersion', '0')
,('EnableDatabaseThread', '0')
,('EnableCacheCleanupThread', '0')
,('OldestDateToLoad', '2022-01-01')
,('MaxAbortedLoads', '3')
,('HoursToWaitBeforeLoading', '2')
,('DetectMobileWidth', '800')
,('DetectMobileHeight', '600')
,('MaxFileStoreSizeInGB', '2')
,('CacheFileDeleteDelayInHours', '2')
,('DatabaseThreadSleepInHours', '1')
,('CacheThreadSleepInHours', '0.5')
,('ThreadMaxWakeupDelayInSeconds', '60')