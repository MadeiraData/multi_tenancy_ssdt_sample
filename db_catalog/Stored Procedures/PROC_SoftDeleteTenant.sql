/*
Author: Eitan Blumin
Date Created: 2022-06-21
Description:
This procedure soft-deletes a specified tenant (sets its state to 2),
and optionally can also hard-delete the tenant after a specified number of seconds (@HardDeleteAfterNumOfSeconds)
*/
CREATE PROCEDURE [dbo].[PROC_SoftDeleteTenant]
	@TenantUID uniqueidentifier,
	@ExecuteLoadBalancing bit = 1,
	@RetainDatabase bit = 0,
	@PurgeMetadata bit = 1,
	@HardDeleteAfterNumOfSeconds int = NULL -- 20
AS
SET NOCOUNT ON;
DECLARE @HardDeleteAfterDelay datetime

UPDATE dbo.tblTenants
	SET [State] = 2 -- Deleted
	, [LastStateChangeDateUtc] = GETUTCDATE()
	, [ManualStateEndDateUtc] = NULL
WHERE [State] <> 2
AND TenantUID = @TenantUID

IF @ExecuteLoadBalancing = 1 AND @HardDeleteAfterNumOfSeconds IS NULL
BEGIN
	-- Execute load balancing for all service mappings
	EXEC dbo.PROC_LoadBalanceServiceTenantsAll
END
ELSE IF @HardDeleteAfterNumOfSeconds IS NOT NULL
BEGIN
	SET @HardDeleteAfterDelay = DATEADD(second, @HardDeleteAfterNumOfSeconds, 0);
	WAITFOR DELAY @HardDeleteAfterDelay;

	EXEC dbo.PROC_DeleteTenant
		  @TenantUID = @TenantUID
		, @RetainDatabase = @RetainDatabase
		, @PurgeMetadata = @PurgeMetadata
		, @ExecuteLoadBalancing = @ExecuteLoadBalancing
END