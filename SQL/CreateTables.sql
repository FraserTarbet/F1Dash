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
)
CREATE NONCLUSTERED INDEX IndexEventId ON dbo.Session (EventId)

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
)
CREATE NONCLUSTERED INDEX IndexSessionId ON dbo.Lap (SessionId)
CREATE NONCLUSTERED INDEX IndexDriver ON dbo.Lap (Driver)

DROP TABLE IF EXISTS dbo.Sector
CREATE TABLE dbo.Sector(
	id INT IDENTITY(0, 1) PRIMARY KEY
	,LapId INT
	,SectorNumber INT
	,SectorTime FLOAT
	,SectorSessionTime FLOAT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE NONCLUSTERED INDEX IndexLapId ON dbo.Sector (LapId)

DROP TABLE IF EXISTS dbo.SpeedTrap
CREATE TABLE dbo.SpeedTrap(
	id INT IDENTITY(0, 1) PRIMARY KEY
	,LapId INT
	,SpeedTrapPoint VARCHAR(2)
	,Speed INT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE NONCLUSTERED INDEX IndexLapId ON dbo.SpeedTrap (LapId)

DROP TABLE IF EXISTS dbo.TimingData
CREATE TABLE dbo.TimingData(
	id INT IDENTITY(0, 1)
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
)
CREATE CLUSTERED INDEX IndexSessionId ON dbo.TimingData (SessionId)

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
CREATE CLUSTERED INDEX IndexSessionId ON dbo.CarData (SessionId)
CREATE NONCLUSTERED INDEX IndexDriver ON dbo.CarData (Driver)


DROP TABLE IF EXISTS dbo.PositionData
CREATE TABLE dbo.PositionData(
	SessionId INT
	,Driver INT
	,[Time] FLOAT
	,[Date] DATETIME2(3)
	,[Status] VARCHAR(MAX)
	,X INT
	,Y INT
	,Z INT
	,[Source] VARCHAR(MAX)
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexSessionId ON dbo.PositionData (SessionId)
CREATE NONCLUSTERED INDEX IndexDriver ON dbo.PositionData (Driver)

DROP TABLE IF EXISTS dbo.TrackStatus
CREATE TABLE dbo.TrackStatus(
	SessionId INT
	,[Time] FLOAT
	,[Status] INT
	,[Message] VARCHAR(MAX)
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexSessionId ON dbo.TrackStatus (SessionId)

DROP TABLE IF EXISTS dbo.SessionStatus
CREATE TABLE dbo.SessionStatus(
	SessionId INT
	,[Time] FLOAT
	,[Status] VARCHAR(MAX)
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexSessionId ON dbo.SessionStatus (SessionId)

DROP TABLE IF EXISTS dbo.DriverInfo
CREATE TABLE dbo.DriverInfo(
	SessionId INT
	,RacingNumber INT
	,BroadcastName VARCHAR(MAX)
	,FullName VARCHAR(MAX)
	,Tla VARCHAR(3)
	,Line INT
	,TeamName VARCHAR(MAX)
	,TeamColour VARCHAR(MAX)
	,FirstName VARCHAR(MAX)
	,LastName VARCHAR(MAX)
	,Reference VARCHAR(MAX)
	,HeadshotUrl NVARCHAR(MAX)
	,CountryCode VARCHAR(3)
	,NameFormat VARCHAR(MAX)
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexSessionId ON dbo.DriverInfo (SessionId)
CREATE NONCLUSTERED INDEX IndexDriver ON dbo.DriverInfo (RacingNumber)

DROP TABLE IF EXISTS dbo.WeatherData
CREATE TABLE dbo.WeatherData(
	SessionId INT
	,[Time] FLOAT
	,AirTemp FLOAT
	,Humidity FLOAT
	,Pressure FLOAT
	,Rainfall BIT
	,TrackTemp FLOAT
	,WindDirection INT
	,WindSpeed FLOAT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexSessionId ON dbo.WeatherData (SessionId)
