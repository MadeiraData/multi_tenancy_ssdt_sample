/*
=============================================
Author:	Eitan Blumin	
Create date: 2022-05-02
Description: Run on each tenant a basic dynamic SQL command
=============================================
*/
CREATE PROCEDURE [dbo].[PROC_ForEachTenant]
	  @command				nvarchar(max)
	, @ServiceID			int = NULL
	, @TenantState			tinyint = 0
AS
BEGIN
	SET XACT_ABORT, ARITHABORT, NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	DECLARE @CurrentTenant sysname, @spExecuteSql nvarchar(4000)

	DECLARE Tenants CURSOR
	LOCAL FAST_FORWARD
	FOR
	SELECT DISTINCT DBName
	FROM [dbo].[FUNC_GetTenantsForService](@ServiceID, @TenantState)

	OPEN Tenants

	WHILE 1=1
	BEGIN
		FETCH NEXT FROM Tenants INTO @CurrentTenant;
		IF @@FETCH_STATUS <> 0 BREAK; -- stop loop if reached EOF
		SET @spExecuteSql = QUOTENAME(@CurrentTenant) + N'..sp_executesql'

		EXEC @spExecuteSql @command
	END

	CLOSE Tenants
	DEALLOCATE Tenants
END