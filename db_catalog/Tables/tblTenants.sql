CREATE TABLE [dbo].[tblTenants]
(
	[TenantUID] uniqueidentifier NOT NULL
		CONSTRAINT PK_tblTenants PRIMARY KEY CLUSTERED WITH(DATA_COMPRESSION = PAGE)
		CONSTRAINT DF_tblTenants_UID DEFAULT (NEWID()),
	[Alias] nvarchar(256) NULL,
	[DBVersion] sysname NOT NULL,
	[State] tinyint NOT NULL CONSTRAINT FK_tblTenants_tblTenantState FOREIGN KEY REFERENCES dbo.tblTenantState ([StateId]) ON DELETE NO ACTION ON UPDATE CASCADE,
	[CreateDateUtc] datetime NOT NULL CONSTRAINT DF_tblTenants_CreateDate DEFAULT (GETUTCDATE()),
	[LastActivityDateUtc] datetime NOT NULL CONSTRAINT DF_tblTenants_LastActivityDate DEFAULT (GETUTCDATE()),
	[UDRServiceID] int NULL,
	[DataSource] sysname NULL,
	[DBName] sysname NOT NULL,
	[LastStateChangeDateUtc] datetime NOT NULL CONSTRAINT DF_tblTenants_LastStateChangeDate DEFAULT (GETUTCDATE()),
	[LastModifyDateUtc] datetime NOT NULL CONSTRAINT DF_tblTenants_LastModifyDateUtc DEFAULT (GETUTCDATE()),
	[ManualStateEndDateUtc] datetime NULL, 
    [VersionLocked] BIT NOT NULL CONSTRAINT DF_tblTenants_VersionLocked DEFAULT (0), 
    [IsTrial] BIT NOT NULL CONSTRAINT DF_tblTenants_IsTrial DEFAULT (1)
	, [AccessToken] varchar(255) NULL
)
GO
CREATE NONCLUSTERED INDEX IX_State_LastStateChange ON [dbo].[tblTenants]
([State] ASC, [LastStateChangeDateUtc] ASC)
INCLUDE([ManualStateEndDateUtc],[IsTrial])
GO
CREATE NONCLUSTERED INDEX IX_State_ManualStateEnd ON [dbo].[tblTenants]
([State] ASC, [ManualStateEndDateUtc] ASC)
WHERE [ManualStateEndDateUtc] IS NOT NULL
GO
-- TODO: Add nonclustered indexes based on actual usage to optimize performance
GO
CREATE TRIGGER TR_TenantStateChange ON [dbo].[tblTenants]
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;

	IF UPDATE([State]) AND NOT UPDATE(LastStateChangeDateUtc)
	BEGIN
		UPDATE [dbo].[tblTenants]
			SET LastStateChangeDateUtc = GETUTCDATE()
		WHERE [TenantUID] IN
			(
				SELECT ins.TenantUID
				FROM inserted AS ins
				INNER JOIN deleted AS del
				ON ins.TenantUID = del.TenantUID
				WHERE ins.[State] <> del.[State]
			)
	END

	SET NOCOUNT OFF;
END