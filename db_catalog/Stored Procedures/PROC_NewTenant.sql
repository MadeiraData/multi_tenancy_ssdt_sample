/*
=============================================
Author:	Eitan Blumin	
Create date: 2022-05-10
Description: Creates a new tenant
=============================================
Example usage:
DECLARE @DataSource sysname, @DBName sysname, @TenantUID uniqueidentifier = NEWID()

EXEC [dbo].[PROC_NewTenant] @Alias = 'Test', @DataSource = @DataSource OUTPUT, @DBName = @DBName OUTPUT, @TenantUID = @TenantUID

SELECT @DataSource, @DBName, @TenantUID
*/
CREATE PROCEDURE [dbo].[PROC_NewTenant]
	@Alias nvarchar(256) = NULL,
	@DBTenantVersion sysname = NULL OUTPUT,
	@State tinyint = NULL,
	@DataSource sysname = NULL OUTPUT,
	@DBName sysname = NULL OUTPUT,
	@TenantUID uniqueidentifier,
	@TenantModel sysname = 'db_tenant_model',
	@AllowReuseForDeletedTenants bit = 1,
	@WhatIf bit = 0
AS
SET NOCOUNT, XACT_ABORT ON;

DECLARE @RC int = 0;

IF @TenantUID IS NULL
BEGIN
	RAISERROR(N'TenantUID must be specified.',16,1);
	RETURN -1;
END

-- Allows overwrite of hard-deleted tenants
IF EXISTS (SELECT NULL FROM dbo.tblTenants WHERE TenantUID = @TenantUID AND [State] <> 3)
BEGIN
	RAISERROR(N'TenantUID already exists.',16,1);
	RETURN -1;
END

IF DB_ID(@DBName) IS NOT NULL
AND NOT EXISTS (SELECT NULL FROM dbo.tblTenants WHERE TenantUID = @TenantUID AND DBName = @DBName AND [State] = 3)
BEGIN
	RAISERROR(N'Tenant database "%s" already exists.',16,1,@DBName);
	RETURN -1;
END

IF @State IS NULL
BEGIN
	SET @State = 0;
END

IF @DBName IS NULL
BEGIN
	EXEC @RC = dbo.[PROC_GenerateTenantDBName] @DBName = @DBName OUTPUT, @TenantUID = @TenantUID;

	IF @RC <> 0 RETURN @RC;
END

DECLARE @CMD nvarchar(max);

IF DB_ID(@TenantModel) IS NULL OR HAS_DBACCESS(@TenantModel) = 0
BEGIN
	RAISERROR(N'Tenant model "%s" is not found or inaccessible',16,1,@TenantModel);
	RETURN -2;
END

IF @DBTenantVersion IS NULL AND HAS_DBACCESS(@DBName) = 1
AND @AllowReuseForDeletedTenants = 1
BEGIN
	SET @CMD = N'SET @DBTenantVersion = ' + QUOTENAME(@DBName) + N'.[dbo].[GetDBVersion]()'
	EXEC sp_executesql @CMD, N'@DBTenantVersion sysname OUTPUT', @DBTenantVersion OUTPUT
END

IF @DBTenantVersion IS NULL AND HAS_DBACCESS(@TenantModel) = 1
AND OBJECT_ID(QUOTENAME(@TenantModel) + N'.[dbo].[GetDBVersion]') IS NOT NULL
BEGIN
	SET @CMD = N'SET @DBTenantVersion = ' + QUOTENAME(@TenantModel) + N'.[dbo].[GetDBVersion]()'
	EXEC sp_executesql @CMD, N'@DBTenantVersion sysname OUTPUT', @DBTenantVersion OUTPUT
END

IF @DBTenantVersion IS NULL
BEGIN
	SET @DBTenantVersion = ISNULL([dbo].[GetDBVersion](), '0');
END

BEGIN TRY
	IF @AllowReuseForDeletedTenants = 0 AND DB_ID(@DBName) IS NOT NULL
	BEGIN
		SET @CMD = N'DROP DATABASE ' + QUOTENAME(@DBName)

		PRINT @CMD;
		IF @WhatIf = 0 EXEC (@CMD);
	END

	IF DB_ID(@DBName) IS NULL
	BEGIN
		-- Check if AWS-RDS:
		IF DB_ID('rdsadmin') IS NOT NULL
		BEGIN
			DECLARE @S3ARNSource nvarchar(4000);
			SELECT @S3ARNSource = [ParamValueString]
			FROM dbo.tblGlobalParams
			WHERE ParamName = 'TenantModelDatabase_RDS_S3_ARN_BackupPath'

			IF @S3ARNSource IS NULL
			BEGIN
				RAISERROR(N'Detected RDS instance, but S3 ARN backup source for the tenant model was not found. Unable to restore.',16,1);
				RETURN -1;
			END

			RAISERROR(N'Restoring "%s" from "%s" using RDS native restore',0,1,@DBName,@S3ARNSource) WITH NOWAIT;
			SET @CMD = 'msdb.dbo.rds_restore_database';

			IF @WhatIf = 0
			BEGIN
				DECLARE @TaskStatus table
				(
				task_id int NULL,
				task_type sysname NULL, -- RESTORE_DB | BACKUP_DB
				database_name sysname NULL,
				completedpercent int NULL, -- 100
				duration_mins int NULL, -- > 0
				lifecycle sysname NULL, -- SUCCESS | ERROR | IN_PROGRESS
				task_info nvarchar(MAX) NULL,
				last_updated datetime NULL,
				created_at datetime NULL,
				S3_object_arn nvarchar(4000) NULL,
				overwrite_s3_backup_file tinyint NULL,
				KMS_master_key_arn nvarchar(4000) NULL,
				filepath nvarchar(max) NULL,
				overwrite_file tinyint NULL
				)

				INSERT INTO @TaskStatus
				(task_id, task_type, lifecycle, created_at, last_updated, database_name, S3_object_arn, overwrite_s3_backup_file, KMS_master_key_arn, completedpercent, task_info)
				exec @CMD
					@restore_db_name=@DBName,
					@s3_arn_to_restore_from=@S3ARNSource

				SET @CMD = 'msdb.dbo.rds_task_status'

				WHILE EXISTS (SELECT NULL FROM @TaskStatus
								WHERE database_name = @DBName 
								AND task_type = 'RESTORE_DB'
								AND lifecycle NOT IN ('SUCCESS')
								AND completedpercent < 100)
				BEGIN
					DELETE FROM @TaskStatus;

					INSERT INTO @TaskStatus
					EXEC @CMD @db_name=@DBName;
				END

				DECLARE @taskinfo nvarchar(MAX);

				SELECT @taskinfo = task_info
				FROM @TaskStatus
				WHERE database_name = @DBName 
				AND task_type = 'RESTORE_DB'
				AND lifecycle = 'ERROR'

				IF @taskinfo IS NOT NULL
				BEGIN
					RAISERROR(N'Error during RDS restore: %s',0,1,@taskinfo);
					RETURN -1;
				END
			END
		END
		ELSE
		BEGIN
			RAISERROR(N'Cloning "%s"',0,1,@TenantModel) WITH NOWAIT;
			IF @WhatIf = 0 DBCC CLONEDATABASE(@TenantModel, @DBName);-- WITH VERIFY_CLONEDB;

			-- Enable the cloned database to be writeable
			SET @CMD = N'ALTER DATABASE ' + QUOTENAME(@DBName) + N' SET READ_WRITE WITH NO_WAIT;'
			PRINT @CMD;
			IF @WhatIf = 0 EXEC (@CMD);
		
			-- Populate the cloned database with data
			EXEC @RC = dbo.[PROC_PopulateTenantDataTables] @DBName, @WhatIf = @WhatIf;

			IF @RC <> 0 RETURN @RC;
		END
	END
	ELSE
	BEGIN
		RAISERROR(N'Reusing existing database "%s"',0,1,@DBName);
	END

END TRY
BEGIN CATCH
	DECLARE @ErrId int = ERROR_NUMBER(), @ErrProc sysname = ERROR_PROCEDURE(), @ErrMsg nvarchar(max) = ERROR_MESSAGE();

	IF DB_ID(@DBName) IS NOT NULL AND HAS_DBACCESS(@DBName) = 1
	BEGIN
		SET @CMD = N'DROP DATABASE ' + QUOTENAME(@DBName)

		BEGIN TRY
			EXEC (@CMD);
		END TRY
		BEGIN CATCH
			SET @ErrMsg = ISNULL(@ErrMsg + CHAR(10), N'') + N'Error while dropping database: ' + ERROR_MESSAGE();
		END CATCH
	END

	RAISERROR(N'Error %d in %s while creating tenant database "%s": %s', 16, 1, @ErrId, @ErrProc, @DBName, @ErrMsg);
	RETURN -3;
END CATCH

IF @WhatIf = 0
BEGIN
	-- delete previously deleted tenant record to re-create it
	DELETE FROM dbo.tblTenants WHERE TenantUID = @TenantUID AND [State] BETWEEN 2 AND 3;

	INSERT INTO dbo.tblTenants
	([Alias], [DBVersion], [State], [DataSource], [DBName], TenantUID)
	VALUES
	(@Alias, @DBTenantVersion, @State, @DataSource, @DBName, @TenantUID)
	
END

RETURN @RC;