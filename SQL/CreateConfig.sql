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
('ForceTestData', '1')
,('DetectMobileWidth', '800')
,('DetectMobileHeight', '600')
,('MaxFileStoreSizeInGB', '2')
,('CacheFileDeleteDelayInHours', '2')
,('DatabaseThreadSleepInHours', '1')
,('CacheThreadSleepInHours', '1')