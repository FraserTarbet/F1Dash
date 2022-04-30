USE F1Dash


DROP TABLE IF EXISTS dbo.Config_App
GO
CREATE TABLE dbo.Config_App(
	[Key] VARCHAR(MAX)
	,[Value] VARCHAR(MAX)
)

INSERT INTO dbo.Config_App(
	[Key]
	,[Value]
)
VALUES
('ForceTestData', '0')
,('ForceMobileVersion', '0')
,('MobileInitialScale', '1')