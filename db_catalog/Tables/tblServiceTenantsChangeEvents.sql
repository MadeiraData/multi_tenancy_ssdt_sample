CREATE TABLE [dbo].[tblServiceTenantsChangeEvents]
(
	[EventTimestampUTC] datetime NOT NULL
		CONSTRAINT DF_tblServiceTenantsChangeEvents_EventTimestampUTC DEFAULT (GETUTCDATE()),
	ServiceID int NOT NULL,
	TenantsChanged int NOT NULL,
	INDEX IX_tblServiceTenantsChangeEvents CLUSTERED
	(ServiceID ASC, [EventTimestampUTC] ASC)
	WITH (DATA_COMPRESSION = PAGE)
)