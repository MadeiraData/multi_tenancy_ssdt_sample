CREATE FUNCTION [dbo].[GetDBVersion]()
RETURNS varchar(50)
AS
BEGIN
	DECLARE @RV varchar(50)

	SELECT @RV = [ParamValueString]
	FROM dbo.tblGlobalParams
	WHERE ParamName = 'DBVersion'

	RETURN @RV;
END
