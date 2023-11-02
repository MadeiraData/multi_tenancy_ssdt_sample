/*
=============================================
Author:	Eitan Blumin	
Create date: 2022-05-02
Description: Run on each tenant a parameterized dynamic SQL command
			This procedure should NOT be executed directly.
			Please use PROC_ExecuteProcedureForEachTenantWithParams
=============================================
*/
CREATE PROCEDURE [dbo].[PROC_ForEachTenantParameterized]
	  @CMD					NVARCHAR(MAX)	-- the SQL command to be used for outer sp_executesql.
	, @XmlParams			XML = NULL		-- the XML definition of the parameter values
	, @ServiceID			int = NULL
	, @TenantState			tinyint = 0
AS
BEGIN
	SET XACT_ABORT, ARITHABORT, NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	DECLARE @CurrentTenant sysname, @spExecuteSql nvarchar(4000), @Timestamp nvarchar(25)

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

		SET @Timestamp = CONVERT(nvarchar(25), GETUTCDATE(), 127) -- yyyy-MM-ddThh:mm:ss.fffZ (no spaces)
		RAISERROR(N'%s - %s',0,1,@Timestamp,@CurrentTenant) WITH NOWAIT;
		EXEC @spExecuteSql @CMD, N'@XmlParams xml', @XmlParams
	END

	CLOSE Tenants
	DEALLOCATE Tenants
END