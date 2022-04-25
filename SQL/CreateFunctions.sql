
USE F1Dash

DROP FUNCTION IF EXISTS dbo.InterpolateSamples
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