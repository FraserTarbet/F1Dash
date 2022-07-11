USE F1DashStreamline

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

DROP TABLE IF EXISTS dbo.ThreadCheckin
CREATE TABLE dbo.ThreadCheckin(
	id INT IDENTITY(0, 1) PRIMARY KEY
	,CheckinDateTime DATETIME DEFAULT GETDATE()
	,CheckinType VARCHAR(MAX)
	,HostName VARCHAR(MAX)
	,ThreadId VARCHAR(MAX)
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
	,TransformStatus BIT
	,TransformStatusUpdatedDateTime DATETIME
	,AbortedLoadCount INT DEFAULT 0
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
	SessionId INT
	,Driver INT
	,LapId INT
	,SectorNumber INT
	,SectorTime FLOAT
	,SectorSessionTime FLOAT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexSessionIdDriverLapId ON dbo.Sector (SessionId, Driver, LapId)


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
CREATE CLUSTERED INDEX IndexSessionIdDriver ON dbo.CarData (SessionId, Driver)


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
CREATE CLUSTERED INDEX IndexSessionIdDriver ON dbo.PositionData (SessionId, Driver)


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
	,DriverOrder INT
	,TeamOrder INT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexSessionIdDriver ON dbo.DriverInfo (SessionId, RacingNumber)


DROP TABLE IF EXISTS dbo.WeatherData
CREATE TABLE dbo.WeatherData(
	id INT IDENTITY(0, 1)
	,SessionId INT
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
CREATE CLUSTERED INDEX IndexSessionIdId ON dbo.WeatherData (SessionId, Id)


DROP TABLE IF EXISTS dbo.MergedLapData
CREATE TABLE dbo.MergedLapData(
	SessionId INT
	,Driver INT
	,LapId INT
	,TimeStart FLOAT
	,TimeEnd FLOAT
	,PitOutTime FLOAT
	,PitInTime FLOAT
	,LapTime FLOAT
	,NumberOfLaps INT
	,StintNumber INT
	,StintId INT
	,LapsInStint INT
	,IsPersonalBest BIT
	,Compound VARCHAR(MAX)
	,TyreAge INT
	,TrackStatus VARCHAR(MAX)
	,CleanLap BIT
	,WeatherId INT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexSessionIdDriver ON dbo.MergedLapData (SessionId, Driver)


DROP TABLE IF EXISTS dbo.MergedCarData
CREATE TABLE dbo.MergedCarData(
	SessionId INT
	,Driver INT
	,LapId INT
	,SectorNumber INT
	,[Time] FLOAT
	,RPM INT
	,Speed INT
	,Gear INT
	,Throttle INT
	,Brake BIT
	,DRS INT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexSessionIdLapIdSectorNumber ON dbo.MergedCarData (SessionId, LapId, SectorNumber)


DROP TABLE IF EXISTS dbo.TrackMap
CREATE TABLE dbo.TrackMap(
	EventId INT
	,SampleId INT
	,X INT
	,Y INT
	,Z INT
	,SectorNumber INT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)
CREATE CLUSTERED INDEX IndexEventIdSectorNumber ON dbo.TrackMap (EventId, SectorNumber)


DROP TABLE IF EXISTS dbo.CarDataNorms
CREATE TABLE dbo.CarDataNorms(
	SessionId INT PRIMARY KEY
	,RPMMin INT
	,RPMMax INT
	,SpeedMin INT
	,SpeedMax INT
	,GearMin INT
	,GearMax INT
	,ThrottleMin INT
	,ThrottleMax INT
	,CreatedDateTime DATETIME DEFAULT GETDATE()
)

