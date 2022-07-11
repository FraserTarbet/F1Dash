
USE F1DashStreamline

DROP FUNCTION IF EXISTS dbo.Interpolate
GO
CREATE FUNCTION dbo.Interpolate (
	@SampleTime FLOAT
	,@TimePre FLOAT
	,@TimePost FLOAT
	,@ValuePre INT
	,@ValuePost INT
)
RETURNS INT
AS
BEGIN
	/*
		Interpolation of telemetry sample data.
		Source data is all integer, this returns integers for consistency.
	*/

	DECLARE @Interpolation FLOAT = (@SampleTime - @TimePre) / (@TimePost - @TimePre)
	
	IF @ValuePre IS NULL RETURN @ValuePost
	IF @ValuePost IS NULL RETURN @ValuePre

	RETURN ROUND(@ValuePre + (@ValuePost - @ValuePre) * @Interpolation, 0)

END
GO


DROP FUNCTION IF EXISTS dbo.SessionOffsets
GO
CREATE FUNCTION dbo.SessionOffsets (
	@EventId INT
	,@SessionName VARCHAR(MAX)
)
RETURNS TABLE
AS
RETURN

	/*
		Used to concatenate session times for practice sessions at the same event so that they can be displayed together in dashboard.
		Returns a table of session time offsets for each session, to be applied in read_ procedures.
		Calculated based on first 'started' and last 'finalised' row in dbo.SessionStatus.
	*/

	SELECT *
		,SUM(MaxFinalisedTime - MinStartTime) OVER(ORDER BY SessionOrder ASC) - (MaxFinalisedTime - MinStartTime) AS SessionTimeOffset

	FROM (
		SELECT S.id AS SessionId
			,S.SessionOrder
			,MIN(CASE WHEN SS.[Status] = 'Started' THEN SS.[Time] ELSE NULL END) AS MinStartTime
			,MAX(CASE WHEN SS.[Status] = 'Finalised' THEN SS.[Time] ELSE NULL END) AS MaxFinalisedTime

		FROM dbo.Session AS S

		LEFT JOIN dbo.SessionStatus AS SS
		ON S.id = SS.SessionId

		WHERE S.EventId = @EventId
		AND (
			S.SessionName = @SessionName
			OR LEFT(S.SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
		)

		GROUP BY S.id
			,S.SessionOrder
	) AS A

GO


DROP FUNCTION IF EXISTS dbo.OffsetStintNumbers
GO
CREATE FUNCTION dbo.OffsetStintNumbers (
	@EventId INT
	,@SessionName VARCHAR(MAX)
)
RETURNS TABLE
AS
RETURN

	/*
		Returns offset StintNumber for each StintId across multiple sessions (i.e. practices)
	*/

	SELECT StintId
		,ROW_NUMBER() OVER(PARTITION BY Driver ORDER BY SessionOrder ASC, StintNumber ASC) AS OffsetStintNumber

	FROM (

		SELECT DISTINCT S.id AS SessionId
			,S.SessionOrder
			,L.Driver
			,L.StintNumber
			,L.StintId

		FROM dbo.Session AS S

		INNER JOIN dbo.MergedLapData AS L
		ON S.id = L.SessionId

		WHERE S.EventId = @EventId
		AND (
			S.SessionName = @SessionName
			OR LEFT(S.SessionName, 8) = 'Practice' AND @SessionName = 'Practice (all)'
		)

	) AS A

GO