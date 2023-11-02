/*
=============================================
Author:	Eitan Blumin	
Create date: 2022-05-02
Description: This procedure generates a random name for a tenant database.
It does NOT create the database. Only generates a name for it.
=============================================

Example usage:

DECLARE @NewDBName sysname

EXEC [dbo].[PROC_GenerateTenantDBName] @DBName = @NewDBName OUTPUT

SELECT @NewDBName
*/
CREATE PROCEDURE [dbo].[PROC_GenerateTenantDBName]
	  @DBName sysname OUTPUT
	, @length int = 50
	, @seed varbinary(8000) = NULL
	, @TenantUID uniqueidentifier = NULL
	, @Prefix sysname = 'db_tenant_'
WITH ENCRYPTION
AS
BEGIN
	SET @DBName = ISNULL(@Prefix, N'') + LEFT(CONVERT(SYSNAME,
		CASE
		WHEN @TenantUID IS NOT NULL THEN
			CONVERT(sysname, HASHBYTES('SHA2_512', CONVERT(varbinary(MAX), @TenantUID)), 2)
		ELSE 
			CRYPT_GEN_RANDOM(@length, @seed)
		END
	, 2)
	, @length)
END