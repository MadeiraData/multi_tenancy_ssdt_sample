CREATE PROCEDURE [dbo].[PROC_ServiceStop]
	 @ServiceTypeId tinyint = NULL
	,@ServiceTypeName sysname = NULL
	,@HostName sysname = NULL
	,@HostPID int = NULL
	,@ServiceId int = NULL OUTPUT
	,@ServiceIP varchar(25) = NULL
	,@ServiceVersion varchar(25) = NULL
AS
BEGIN

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SET @HostName = ISNULL(@HostName, HOST_NAME());
SET @HostPID = ISNULL(@HostPID, HOST_ID());
SET @ServiceIP = ISNULL(@ServiceIP, CONVERT(varchar(25),CONNECTIONPROPERTY('client_net_address')));

IF @ServiceTypeId IS NULL
BEGIN
	SELECT
	  @ServiceTypeID = [TypeId]
	FROM dbo.tblServiceTypes
	WHERE [TypeName] = @ServiceTypeName
END
ELSE
BEGIN
	SELECT
	  @ServiceTypeName = [TypeName]
	FROM dbo.tblServiceTypes
	WHERE TypeId = @ServiceTypeId
END

IF @ServiceTypeID IS NULL
BEGIN
	RAISERROR(N'Service type "%s" is not valid',16,1,@ServiceTypeName);
	RETURN -1;
END

UPDATE dbo.tblService
	SET
		@ServiceId = [ServiceID],
		[AppName] = DEFAULT,
		[ServiceAccountName] = DEFAULT,
		[LastSPID] = DEFAULT,
		[ServiceIP] = @ServiceIP,
		[ServiceVersion] = @ServiceVersion,
		[StopTimeUTC] = GETUTCDATE(),
		[LastInitializationUTC] = NULL
WHERE [HostPID] IS NOT NULL
AND [HostName] = @HostName
AND [HostPID] = @HostPID
AND [ServiceTypeId] = @ServiceTypeId
AND (@ServiceId IS NULL OR [ServiceID] = @ServiceId)

DELETE
FROM dbo.tblServiceTenantsMappings
WHERE ServiceID = @ServiceId

-- Force load balancing
EXEC dbo.PROC_LoadBalanceServiceTenants @ServiceTypeId = @ServiceTypeId;

END