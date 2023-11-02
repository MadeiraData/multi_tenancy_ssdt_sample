/*
This function is deprecated.
Please use FUNC_GetTenantsForService instead.
*/
CREATE FUNCTION [dbo].[FUNC_GetTenantsForUDRService]
(
	  @UDRServiceID			int = NULL
	, @TenantState			tinyint = 0
)
RETURNS TABLE AS RETURN
(
	SELECT [TenantUID], [Alias], [DBVersion], [State], [ServiceID] AS [UDRServiceID], [DataSource], [DBName]
	FROM [dbo].[FUNC_GetTenantsForService](@UDRServiceID,@TenantState)
	--FROM dbo.tblTenants AS T
	--WHERE ([DataSource] IS NOT NULL OR HAS_DBACCESS(DBName) = 1)
	--AND [State] = @TenantState
	--AND (@UDRServiceID IS NULL OR [UDRServiceID] = @UDRServiceID)
	---- WHERE [LastActivityDateUtc] > DATEADD(dd, -30, GETUTCDATE())
)
GO
CREATE FUNCTION [dbo].[FUNC_GetTenantsForService]
(
	  @ServiceID			int = NULL
	, @TenantState			tinyint = 0
)
RETURNS TABLE AS RETURN
(
	SELECT DISTINCT T.[TenantUID], T.[Alias], T.[DBVersion], T.[State], Mappings.[ServiceID], T.[DataSource], T.[DBName]
	FROM dbo.tblTenants AS T
	LEFT JOIN dbo.tblServiceTenantsMappings AS Mappings ON T.TenantUID = Mappings.TenantUID
	WHERE (T.[DataSource] IS NOT NULL OR HAS_DBACCESS(T.DBName) = 1)
	AND T.[State] = @TenantState
	AND (@ServiceID IS NULL OR Mappings.[ServiceID] = @ServiceID)
	-- WHERE [LastActivityDateUtc] > DATEADD(dd, -30, GETUTCDATE())
)
