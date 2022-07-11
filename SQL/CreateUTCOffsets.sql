
/*
	Session times from API are in local time, so aren't that helpful for scheduled refreshes.
	For the time being, maintain a table of UTC offsets for each locale in the event schedule.
*/


USE F1DashStreamline

DROP TABLE IF EXISTS dbo.UTCOffsets
GO
CREATE TABLE dbo.UTCOffsets(
	Country VARCHAR(MAX)
	,Location VARCHAR(MAX)
	,UTCOffset INT
)

INSERT INTO dbo.UTCOffsets
VALUES
('Abu Dhabi', 'Yas Island', 4)
,('Australia', 'Melbourne', 10)
,('Austria', 'Spielberg', 2)
,('Azerbaijan', 'Baku', 4)
,('Bahrain', 'Bahrain', 3)
,('Bahrain', 'Sakhir', 3)
,('Belgium', 'Spa', 2)
,('Belgium', 'Spa-Francorchamps', 2)
,('Brazil', 'São Paulo', -3)
,('Canada', 'Montreal', -4)
,('Canada', 'Montréal', -4)
,('China', 'Shanghai', 8)
,('France', 'Le Castellet', 1)
,('Germany', 'Hockenheim', 2)
,('Germany', 'Nürburg', 2)
,('Great Britain', 'Silverstone', 0)
,('Hungary', 'Budapest', 2)
,('Italy', 'Imola', 2)
,('Italy', 'Monza', 2)
,('Italy', 'Mugello', 1)
,('Japan', 'Suzuka', 9)
,('Mexico', 'Mexico City', -5)
,('Monaco', 'Monte Carlo', 1)
,('Monaco', 'Monte-Carlo', 1)
,('Netherlands', 'Zandvoort', 1)
,('Portugal', 'Portimão', 0)
,('Qatar', 'Al Daayen', 3)
,('Russia', 'Sochi', 3)
,('Saudi Arabia', 'Jeddah', 3)
,('Singapore', 'Marina Bay', 8)
,('Spain', 'Barcelona', 1)
,('Spain', 'Montmeló', 1)
,('Spain', 'Spain', 1)
,('Turkey', 'Istanbul', 3)
,('UAE', 'Abu Dhabi', 4)
,('UK', 'Silverstone', 0)
,('United States', 'Austin', -6)
,('United States', 'Miami', -5)
,('USA', 'Austin', -6)