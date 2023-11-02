/*
=============================================
Author:	Eitan Blumin	
Create date: 2022-05-17
Description: Automatically re-distribute active tenant
		databases across management services of a given type.

		Mappings of services to tenants are managed in the table tblServiceTenantsMappings.
		Any change in this mappings table activates a trigger which inserts
		new records into the table tblServiceTenantsChangeEvents.
		Based on these new records, the services would be able to detect any changes
		and thus know that their list of tenants needs to be refreshed.
=============================================
*/
CREATE PROCEDURE [dbo].[PROC_LoadBalanceServiceTenants]
	 @ServiceTypeId tinyint = NULL /* NULL = ALL, 1 = UDR, 2 = IDSWeb, 3 = IDS */
	,@HeartbeatThresholdSeconds int = NULL --120 (2 minutes)
	,@NumOfActiveServices int = NULL OUTPUT
	,@TenantActivityThresholdMinutes int = NULL --360 (6 hours)
AS
SET NOCOUNT ON;

IF @ServiceTypeId IS NULL
BEGIN
	EXEC [dbo].[PROC_LoadBalanceServiceTenantsAll];
	RETURN;
END

DECLARE @EnableTenantLoadBalancing BIT

SELECT
	  @EnableTenantLoadBalancing = EnableTenantLoadBalancing
	, @HeartbeatThresholdSeconds = ISNULL(@HeartbeatThresholdSeconds, ServiceHeartbeatThresholdSeconds)
	, @TenantActivityThresholdMinutes = ISNULL(@TenantActivityThresholdMinutes, TenantActivityThresholdMinutes)
FROM dbo.tblServiceTypes WITH(NOLOCK)
WHERE TypeId = @ServiceTypeId

IF @EnableTenantLoadBalancing IS NULL
BEGIN
	RAISERROR(N'Service Type Id %d is not valid',16,1,@ServiceTypeId);
	RETURN -1;
END

SET @NumOfActiveServices = NULL;

IF OBJECT_ID('tempdb..#ActiveServices') IS NOT NULL DROP TABLE #ActiveServices;
CREATE TABLE #ActiveServices
(
Numerator int NOT NULL IDENTITY(0,1) PRIMARY KEY CLUSTERED,
ServiceId int NOT NULL
)

-- TODO:
-- Services could optionally be assigned a "weight" based on how many tenants
-- they can take on themselves relative to other services
-- (for example, based on the number of CPU cores and RAM they have)
-- and then such services could be "duplicated" in the temp table based on that weight
-- in order to increase the number of tenants that could be matched to them with modulu.
-- This could be done using CROSS APPLY and TOP that generates dummy records. For example:
-- CROSS APPLY (SELECT TOP (tblService.Weight) 1 AS num FROM sys.all_columns) AS w
INSERT INTO #ActiveServices (ServiceId)
SELECT [ServiceID]
FROM dbo.tblService WITH(NOLOCK)
WHERE [Enabled] = 1
AND [HostPID] IS NOT NULL
AND [ServiceTypeId] = @ServiceTypeId
AND [LastHeartbeatUTC] >= DATEADD(second, -@HeartbeatThresholdSeconds, GETUTCDATE())

SET @NumOfActiveServices = @@ROWCOUNT;

RAISERROR(N'Active services found: %d',0,1,@NumOfActiveServices);

IF @NumOfActiveServices = 0
BEGIN
	-- If no services are active, remove service mappings from all tenants
	DELETE Mappings
	FROM [dbo].[tblServiceTenantsMappings] AS Mappings
	INNER JOIN dbo.tblService AS Srv WITH(NOLOCK) ON Mappings.ServiceID = Srv.[ServiceID]
	WHERE Srv.ServiceTypeId = @ServiceTypeId

	RAISERROR(N'No active services found. Deleted all service-tenant mappings: %d',0,1,@@ROWCOUNT);
END
ELSE
BEGIN
	-- delete mappings for tenants which are inactive (suspended/deleted),
	-- or have no recent activity, or the services are inactive
	DELETE Mappings
	FROM [dbo].[tblServiceTenantsMappings] AS Mappings
	INNER JOIN dbo.tblService AS Srv WITH(NOLOCK) ON Mappings.ServiceID = Srv.[ServiceID]
	LEFT JOIN dbo.tblTenants AS Tenants WITH(NOLOCK) ON Mappings.TenantUID = Tenants.TenantUID
		AND Tenants.[State] = 0
		AND Tenants.LastActivityDateUtc > DATEADD(minute, -@TenantActivityThresholdMinutes, GETUTCDATE())
	WHERE Srv.ServiceTypeId = @ServiceTypeId
	AND
	(
	Tenants.TenantUID IS NULL -- tenant no longer valid
	OR Mappings.ServiceID NOT IN (SELECT ServiceID FROM #ActiveServices) -- service no longer valid
	OR Srv.StopTimeUTC IS NOT NULL
	)
	RAISERROR(N'Deleted invalid service-tenant mappings: %d',0,1,@@ROWCOUNT);

	IF @EnableTenantLoadBalancing = 1
	BEGIN
		-- upsert new service-tenant mappings
		;WITH Mappings AS
		(
			-- Get all existing mappings for services of the relevant type
			SELECT *
			FROM [dbo].[tblServiceTenantsMappings] WITH (UPDLOCK, HOLDLOCK)
			WHERE ServiceID IN (SELECT [ServiceID] FROM dbo.tblService WITH(NOLOCK) WHERE ServiceTypeId = @ServiceTypeId)
		), Tenants AS
		(
			-- use modulu to distribute active tenants with recent activity
			-- across all active services
			SELECT
				  Tenants.TenantUID
				, Numerator = (ROW_NUMBER() OVER (ORDER BY Tenants.[TenantUID])) % @NumOfActiveServices
			FROM dbo.tblTenants AS Tenants  WITH(NOLOCK)
			WHERE Tenants.[State] = 0
			AND LastActivityDateUtc > DATEADD(minute, -@TenantActivityThresholdMinutes, GETUTCDATE())
		)
		MERGE INTO Mappings
		USING (
				SELECT T.TenantUID, svc.ServiceId
				FROM Tenants AS T WITH(NOLOCK)
				INNER JOIN #ActiveServices AS svc
				ON T.Numerator = svc.Numerator
			) AS Src
			ON Mappings.TenantUID = Src.TenantUID AND Mappings.ServiceId = Src.ServiceId
		-- tenant should be mapped to this service but currently isn't
		WHEN NOT MATCHED BY TARGET THEN
			INSERT (TenantUID, ServiceID)
			VALUES (TenantUID, ServiceId)
		-- tenant should not be mapped to this service but it currently is
		WHEN NOT MATCHED BY SOURCE THEN
			DELETE
		;
		-- The above also takes care of cases where a tenant should have a service different from what it currently has
		
		RAISERROR(N'Updated service-tenant mappings: %d',0,1,@@ROWCOUNT);
	END
	ELSE
	BEGIN
		RAISERROR(N'Load balancing is skipped for Service Type %d',0,1,@ServiceTypeId);
	END
END
