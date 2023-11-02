CREATE PROCEDURE [dbo].[PROC_LoadBalanceServiceTenantsAll]
	@FilterByEnableTenantsLoadBalancing BIT = NULL
AS
SET NOCOUNT ON;

RAISERROR(N'Initiating tenant load balancing for all service types.',0,1) WITH NOWAIT;

DECLARE @ServiceTypeId tinyint, @ServiceTypeName sysname, @NumOfActiveServices int

DECLARE ServiceCur CURSOR
LOCAL FAST_FORWARD
FOR
SELECT TypeId, TypeName
FROM dbo.tblServiceTypes
WHERE (@FilterByEnableTenantsLoadBalancing IS NULL OR EnableTenantLoadBalancing = @FilterByEnableTenantsLoadBalancing)

OPEN ServiceCur;

WHILE 1=1
BEGIN
	FETCH NEXT FROM ServiceCur INTO @ServiceTypeId, @ServiceTypeName;
	IF @@FETCH_STATUS <> 0 BREAK;

	SET @NumOfActiveServices = NULL;

	EXEC [dbo].[PROC_LoadBalanceServiceTenants] @ServiceTypeId = @ServiceTypeId, @NumOfActiveServices = @NumOfActiveServices OUTPUT;

	RAISERROR(N'Service Type "%s" processed %d active service(s)',0,1,@ServiceTypeName,@NumOfActiveServices) WITH NOWAIT;
END

CLOSE ServiceCur;
DEALLOCATE ServiceCur;

RAISERROR(N'Done.',0,1) WITH NOWAIT;
