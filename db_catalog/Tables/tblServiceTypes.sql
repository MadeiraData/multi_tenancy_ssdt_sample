CREATE TABLE [dbo].[tblServiceTypes]
(
	[TypeId] tinyint NOT NULL CONSTRAINT PK_tblServiceTypes PRIMARY KEY CLUSTERED,
	[TypeName] sysname NOT NULL, 
	[TypeDescription] nvarchar(4000) NULL,
    [EnableTenantLoadBalancing] bit NOT NULL /* if enabled, all active tenants will automatically be balanced across all active services */
		CONSTRAINT DF_tblServiceTypes_EnableTenantLoadBalancing DEFAULT (1),
	[ServiceHeartbeatThresholdSeconds] int NOT NULL /* how long since the service's last activity to consider it inactive */
		CONSTRAINT DF_tblServiceTypes_ServiceHeartbeatThresholdSeconds DEFAULT (120),
	[TenantActivityThresholdMinutes] int NULL /* how long since last tenant activity to render it inactive for this service type */
		CONSTRAINT DF_tblServiceTypes_TenantActivityThresholdMinutes DEFAULT (360),
	[ServiceHeartbeatFrequencySeconds] int NULL /* number of seconds between each heartbeat that the service needs to run */
		CONSTRAINT DF_tblServiceTypes_ServiceHeartbeatFrequencySeconds DEFAULT (10),
	[ServiceInactivityToDeleteMinutes] int NOT NULL /* how long since last service heartbeat to delete it from the Service table */
		CONSTRAINT DF_tblServiceTypes_ServiceInactivityToDeleteMinutes DEFAULT (1440),
	[ServiceTenantChangeEventsRetentionMinutes] int NULL /* how long before deleting old data from tblServiceTenantsChangeEvents */
		CONSTRAINT DF_tblServiceTypes_ServiceTenantChangeEventsRetentionMinutes DEFAULT (1440)
)
