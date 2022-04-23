USE F1Dash

DROP TABLE IF EXISTS dbo.Log_Data
CREATE TABLE dbo.Log_Data(
	id INT IDENTITY(0, 1) PRIMARY KEY
	,LogDateTime DATETIME DEFAULT GETDATE()
	,HostName VARCHAR(MAX)
	,LogMessage NVARCHAR(MAX)
)

DROP TABLE IF EXISTS dbo.Log_App
CREATE TABLE dbo.Log_App(
	id INT IDENTITY(0, 1) PRIMARY KEY
	,LogDateTime DATETIME DEFAULT GETDATE()
	,HostName VARCHAR(MAX)
	,ClientInfo NVARCHAR(MAX)
	,LogType VARCHAR(MAX)
	,LogMessage NVARCHAR(MAX)
)

DROP TABLE IF EXISTS dbo.Event
CREATE TABLE dbo.Event(
	id INT PRIMARY KEY
	,RoundNumber INT
	,Country VARCHAR(MAX)
	,Location VARCHAR(MAX)
	,OfficialEventName VARCHAR(MAX)
	,EventDate DATETIME
	,EventName VARCHAR(MAX)
	,EventFormat VARCHAR(MAX)
	,F1ApiSupport BIT
)

DROP TABLE IF EXISTS dbo.Session
CREATE TABLE dbo.Session(
	id INT PRIMARY KEY
	,EventId INT
	,SessionOrder INT
	,SessionName VARCHAR(MAX)
	,SessionDate DATETIME
	,INDEX IndexEventId(EventId)
)