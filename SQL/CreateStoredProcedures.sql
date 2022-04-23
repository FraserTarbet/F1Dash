USE F1Dash
GO

DROP PROCEDURE IF EXISTS dbo.Get_MaxId
GO
CREATE PROCEDURE dbo.Get_MaxId @TableName VARCHAR(MAX)
AS
BEGIN
	DECLARE @sql NVARCHAR(MAX)
	SET @sql = 'SELECT COALESCE(MAX(id), 0) AS MaxId FROM ' + @TableName + ';'
	EXEC (@sql)
END
GO

DROP PROCEDURE IF EXISTS dbo.Truncate_Schedule
GO
CREATE PROCEDURE dbo.Truncate_Schedule @ClearAll BIT
AS
BEGIN

	SELECT id
	INTO #Deletes
	FROM dbo.Event
	WHERE EventDate > GETDATE()
	OR @ClearAll = 1

	DELETE 
	FROM dbo.Event
	WHERE id IN (SELECT id FROM #Deletes)

	DELETE
	FROM dbo.Session
	WHERE EventId in (SELECT id FROM #Deletes)

	DROP TABLE #Deletes

END
GO