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
,('ForceMobileLayout', '0')
,('DetectMobileWidth', '800')
,('DetectMobileHeight', '600')
,('MaxFileStoreSizeInGB', '2')