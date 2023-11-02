CREATE TABLE [dbo].[tblServiceTenantsMappings]
(
	[TenantUID] UNIQUEIDENTIFIER NOT NULL
		CONSTRAINT FK_tblServiceTenantsMappings_TenantUID FOREIGN KEY REFERENCES dbo.tblTenants(TenantUID) ON DELETE CASCADE,
	[ServiceID] INT NOT NULL
		CONSTRAINT FK_tblServiceTenantsMappings_ServiceID FOREIGN KEY REFERENCES dbo.tblService([ServiceID]) ON DELETE CASCADE,
	[LastModifiedUTC] DATETIME NOT NULL
		CONSTRAINT DF_tblServiceTenantsMappings_LastModifiedUTC DEFAULT(GETUTCDATE())
)
GO
CREATE CLUSTERED INDEX IX_tblServiceTenantsMappings_ServiceID_TenantUID ON dbo.tblServiceTenantsMappings
(ServiceID, TenantUID)
GO
CREATE TRIGGER TR_ServiceTenantsMappings ON [dbo].[tblServiceTenantsMappings]
AFTER DELETE, INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;

	INSERT INTO dbo.tblServiceTenantsChangeEvents
	(EventTimestampUTC, ServiceID, TenantsChanged)
	SELECT GETUTCDATE(), ServiceID, COUNT(DISTINCT TenantUID)
	FROM
	(
		SELECT ServiceID, TenantUID
		FROM inserted
		UNION ALL
		SELECT ServiceID, TenantUID
		FROM deleted
	) AS d
	GROUP BY ServiceID
END
GO