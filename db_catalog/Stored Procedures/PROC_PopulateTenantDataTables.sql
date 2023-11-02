/*
=============================================
Author:	Eitan Blumin	
Create date: 2022-05-10
Description: Populates a newly created tenant database
			with static data from the tenant model database.
			The list of tables populated is configurable
			using dbo.tblTenantModelDataTables
=============================================
*/
CREATE PROCEDURE [dbo].[PROC_PopulateTenantDataTables]
	@TenantDatabase sysname,
	@TenantModel sysname = 'db_tenant_model',
	@WhatIf bit = 0
AS
SET NOCOUNT, XACT_ABORT, ARITHABORT ON;

IF @WhatIf = 0 AND (DB_ID(@TenantDatabase) IS NULL OR HAS_DBACCESS(@TenantDatabase) = 0)
BEGIN
	RAISERROR(N'Tenant database "%s" is not found or inaccessible',16,1,@TenantDatabase);
	RETURN -1;
END

DECLARE  @CMD nvarchar(max);

IF DB_ID(@TenantModel) IS NULL OR HAS_DBACCESS(@TenantModel) = 0
BEGIN
	RAISERROR(N'Tenant model "%s" is not found or inaccessible',16,1,@TenantModel);
	RETURN -1;
END

DECLARE @CurrSchema sysname, @CurrTable sysname, @HasIdentity bit, @spExecuteSql nvarchar(1000), @ColumnsList nvarchar(max);
SET @spExecuteSql = QUOTENAME(@TenantDatabase) + N'..sp_executesql'

DECLARE DataTables CURSOR
LOCAL FAST_FORWARD
FOR
SELECT [SchemaName], [TableName]
FROM dbo.tblTenantModelDataTables
ORDER BY [ExecutionOrder] ASC

OPEN DataTables;

WHILE 1=1
BEGIN
	FETCH NEXT FROM DataTables INTO @CurrSchema, @CurrTable;
	IF @@FETCH_STATUS <> 0 BREAK;

	SET @HasIdentity = 0;
	SET @ColumnsList = NULL;

	SET @CMD = N'SET @HasIdentity = CONVERT(int, OBJECTPROPERTY(OBJECT_ID(''' + QUOTENAME(@CurrSchema) + N'.' + QUOTENAME(@CurrTable) + N'''),''TableHasIdentity''))
	SELECT @ColumnsList = ISNULL(@ColumnsList + N'', '', N'''') + QUOTENAME([name])
	FROM sys.columns
	WHERE is_computed = 0
	AND object_id = OBJECT_ID(''' + QUOTENAME(@CurrSchema) + N'.' + QUOTENAME(@CurrTable) + N''')'
	
	IF @WhatIf = 1 AND DB_ID(@TenantDatabase) IS NULL
	BEGIN
		RAISERROR(N'%s',0,1,@CMD) WITH NOWAIT;
	END
	ELSE
	BEGIN
		EXEC @spExecuteSql @CMD, N'@HasIdentity bit OUTPUT, @ColumnsList nvarchar(max) OUTPUT', @HasIdentity OUTPUT, @ColumnsList OUTPUT;
	END

	SET @CMD = CASE WHEN @HasIdentity = 1 THEN N'SET IDENTITY_INSERT ' + QUOTENAME(@CurrSchema) + N'.' + QUOTENAME(@CurrTable) + N' ON;'
	ELSE N'' END + N'
	INSERT INTO ' + QUOTENAME(@CurrSchema) + N'.' + QUOTENAME(@CurrTable) + N'
	(' + @ColumnsList + N')
	SELECT
	 ' + @ColumnsList + N'
	FROM ' + QUOTENAME(@TenantModel) + N'.' + QUOTENAME(@CurrSchema) + N'.' + QUOTENAME(@CurrTable) + N'

	RAISERROR(N''"%s"."%s": populated %d row(s)'',0,1,@CurrSchema,@CurrTable,@@ROWCOUNT) WITH NOWAIT;

	' + CASE WHEN @HasIdentity = 1 THEN N'SET IDENTITY_INSERT ' + QUOTENAME(@CurrSchema) + N'.' + QUOTENAME(@CurrTable) + N' OFF;'
	ELSE N'' END

	IF @WhatIf = 1
	BEGIN
		RAISERROR(N'%s',0,1,@CMD) WITH NOWAIT;
	END
	ELSE
	BEGIN
		EXEC @spExecuteSql @CMD, N'@CurrSchema sysname, @CurrTable sysname', @CurrSchema,@CurrTable;
	END
END

CLOSE DataTables;
DEALLOCATE DataTables;