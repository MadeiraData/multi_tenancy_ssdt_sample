/*
=============================================
Author:	Eitan Blumin	
Create date: 2022-05-17
Description: This procedure is to be executed
		periodically by every tenant management service
		this serves to track which service is active
		and saves identifiable information about it.

		If a service is starting up for the first time,
		this procedure should be executed with @Initialize = 1

		Either @ServiceTypeId or @ServiceTypeName must be provided.
=============================================
*/
CREATE PROCEDURE [dbo].[PROC_ServiceHeartbeat]
	 @ServiceTypeId tinyint = NULL
	,@HostName sysname = NULL
	,@HostPID int = NULL
	,@Initialize bit = 0
	,@ServiceId int = NULL OUTPUT
	,@Enabled bit = NULL OUTPUT
	,@NextHeartbeatSeconds int = NULL OUTPUT
	,@ServiceIP varchar(25) = NULL
AS
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SET @HostName = ISNULL(@HostName, HOST_NAME());
SET @HostPID = ISNULL(@HostPID, HOST_ID());
SET @ServiceIP = ISNULL(@ServiceIP, CONVERT(varchar(25),CONNECTIONPROPERTY('client_net_address')));
SET @Enabled = NULL;

UPDATE dbo.tblService
	SET
		@Enabled = [Enabled],
		@ServiceId = [ServiceID],
		[AppName] = DEFAULT,
		[ServiceAccountName] = DEFAULT,
		[LastSPID] = DEFAULT,
		[ServiceIP] = @ServiceIP,
		[LastHeartbeatUTC] = GETUTCDATE(),
		[StopTimeUTC] = 
				CASE
					WHEN @Initialize = 1 OR [LastInitializationUTC] IS NULL
					THEN NULL
					ELSE [StopTimeUTC]
				END,
		[LastInitializationUTC] = 
				CASE
					WHEN @Initialize = 1 OR [LastInitializationUTC] IS NULL 
					THEN GETUTCDATE()
					ELSE [LastInitializationUTC]
				END
WHERE [HostPID] IS NOT NULL
AND [HostName] = @HostName
AND [HostPID] = @HostPID
AND [ServiceTypeId] = @ServiceTypeId

IF @Enabled IS NULL
BEGIN
	-- Add new service instance
	INSERT INTO dbo.tblService
	(ServiceTypeId,HostName,HostPID,ServiceIP)
	VALUES
	(@ServiceTypeId,@HostName,@HostPID,@ServiceIP)

	SET @ServiceId = SCOPE_IDENTITY()
	SET @Enabled = 1

	-- Force load balancing
	EXEC dbo.PROC_LoadBalanceServiceTenants @ServiceTypeId = @ServiceTypeId;
END

SELECT [TenantUID], [DataSource], [DBName]
FROM dbo.[FUNC_GetTenantsForService](@ServiceID, 0)
WHERE @Enabled = 1
