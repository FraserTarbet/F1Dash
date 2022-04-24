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
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)

DROP TABLE IF EXISTS dbo.Session
CREATE TABLE dbo.Session(
	id INT PRIMARY KEY
	,EventId INT
	,SessionOrder INT
	,SessionName VARCHAR(MAX)
	,SessionDate DATETIME
	,CreatedDateTime DATETIME DEFAULT GETDATE()
	,LoadStatus BIT
	,LoadStatusUpdatedDateTime DATETIME
	,INDEX IndexEventId(EventId)
)

DROP TABLE IF EXISTS dbo.Lap
CREATE TABLE dbo.Lap(
	id INT PRIMARY KEY
	,SessionId INT
	,Driver INT
	,[Time] FLOAT
	,LapTime FLOAT
	,NumberOfLaps INT
	,NumberOfPitStops INT
	,PitOutTime FLOAT
	,PitInTime FLOAT
	,IsPersonalBest BIT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
	,INDEX IndexSessionId(SessionId)
	,INDEX IndexDriverIf(Driver)
)

DROP TABLE IF EXISTS dbo.Sector
CREATE TABLE dbo.Sector(
	id INT IDENTITY(0, 1) PRIMARY KEY
	,LapId INT
	,SectorNumber INT
	,SectorTime FLOAT
	,SectorSessionTime FLOAT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
	,INDEX IndexLapId(LapId)
)

DROP TABLE IF EXISTS dbo.SpeedTrap
CREATE TABLE dbo.SpeedTrap(
	id INT IDENTITY(0, 1) PRIMARY KEY
	,LapId INT
	,SpeedTrapPoint VARCHAR(2)
	,Speed INT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
	,INDEX IndexLapId(LapId)
)

DROP TABLE IF EXISTS dbo.TimingData
CREATE TABLE dbo.TimingData(
	id INT IDENTITY(0, 1) PRIMARY KEY
	,SessionId INT
	,LapNumber INT
	,Driver INT
	,LapTime FLOAT
	,Stint INT
	,TotalLaps INT
	,Compound VARCHAR(MAX)
	,New BIT
	,TyresNotChanged BIT
	,[Time] FLOAT
	,LapFlags FLOAT
	,LapCountTime FLOAT
	,StartLaps FLOAT
	,OutLap FLOAT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
	,INDEX IndexSessionId(SessionId)
)

DROP TABLE IF EXISTS dbo.CarData
CREATE TABLE dbo.CarData(
	SessionId INT
	,Driver INT
	,[Time] FLOAT
	,[Date] DATETIME2(3)
	,RPM INT
	,Speed INT
	,Gear INT
	,Throttle INT
	,Brake BIT
	,DRS INT
	,[Source] VARCHAR(MAX)
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexEventIdDriver on dbo.CarData (SessionId, Driver)