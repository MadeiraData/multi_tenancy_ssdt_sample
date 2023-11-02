-- =============================================
-- Author:	Eitan Blumin	
-- Create date: 2022-05-22
-- Description:	Hard-deletes a tenant database
--
-- =============================================
/* -- sample execution
SELECT * FROM dbo.tblTenants

EXEC [dbo].[PROC_DeleteTenant] @TenantUID = 'ABAE6224-B910-4911-838F-297F3DE9AEC8'
*/
CREATE PROCEDURE [dbo].[PROC_DeleteTenant]
	@TenantUID uniqueidentifier,
	@RetainDatabase bit = 0,
	@PurgeMetadata bit = 1,
	@WhatIf bit = 0,
	@ExecuteLoadBalancing bit = 1
AS
SET NOCOUNT ON;
DECLARE @CMD nvarchar(max);
DECLARE @DBName sysname

SELECT @DBName = DBName
FROM dbo.tblTenants
WHERE TenantUID = @TenantUID

IF DB_ID(@DBName) IS NOT NULL AND @RetainDatabase = 0
BEGIN

	SET @CMD = N'ALTER DATABASE ' + QUOTENAME(@DBName) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE ' + QUOTENAME(@DBName) + N';'

	PRINT @CMD;

	IF @WhatIf = 0
	BEGIN
		EXEC (@CMD);
	END
END
ELSE IF DB_ID(@DBName) IS NULL
BEGIN
	SET @CMD = N'Database "' + ISNULL(@DBName, '(null)') + N'" does not exist.'
	RAISERROR(N'Database "%s" does not exist.',0,1,@DBName);
END
ELSE IF @RetainDatabase = 1
BEGIN
	SET @CMD = N'Database "' + ISNULL(@DBName, '(null)') + N'" was not deleted.'
	RAISERROR(N'Database "%s" was not deleted.',0,1,@DBName);
END

IF @PurgeMetadata = 1 AND @WhatIf = 0
BEGIN
	DECLARE @TenantHeader AS TABLE
	(
		[TenantUID] uniqueidentifier NOT NULL,
		[Alias] nvarchar(256) NULL,
		[DBVersion] sysname NOT NULL,
		[CreateDateUtc] datetime NOT NULL,
		[LastActivityDateUtc] datetime NOT NULL,
		[DataSource] sysname NULL,
		[DBName] sysname NOT NULL,
		[LastStateChangeDateUtc] datetime NOT NULL,
		[LastModifyDateUtc] datetime NOT NULL
	)

	DELETE T
	OUTPUT deleted.TenantUID, deleted.Alias, deleted.DBVersion, deleted.CreateDateUtc
		, deleted.LastActivityDateUtc, deleted.DataSource, deleted.DBName
		, deleted.LastStateChangeDateUtc, deleted.LastModifyDateUtc
	INTO @TenantHeader
	FROM dbo.tblTenants AS T
	WHERE TenantUID = @TenantUID;

	IF @RetainDatabase = 1
	BEGIN
		INSERT INTO dbo.tblTenants
		(TenantUID, Alias, DBVersion, CreateDateUtc, LastActivityDateUtc, DataSource, DBName, LastStateChangeDateUtc, LastModifyDateUtc, [State])
		SELECT
		 TenantUID, Alias, DBVersion, CreateDateUtc, LastActivityDateUtc, DataSource, DBName, LastStateChangeDateUtc, LastModifyDateUtc, 3 -- Hard-Deleted
		FROM @TenantHeader
	END
END
ELSE IF @PurgeMetadata = 0 AND @RetainDatabase = 0 AND @WhatIf = 0
BEGIN
	UPDATE dbo.tblTenants
		SET [State] = 3 -- Hard-deleted
	WHERE TenantUID = @TenantUID;
END

-- Execute load balancing for all service mappings
IF @ExecuteLoadBalancing = 1
	EXEC dbo.PROC_LoadBalanceServiceTenantsAll