CREATE TABLE [dbo].[tblService]
(
	[ServiceID] INT NOT NULL IDENTITY(1,1) CONSTRAINT PK_tblService PRIMARY KEY CLUSTERED,
	[HostName] sysname NOT NULL CONSTRAINT DF_tblService_HostName DEFAULT (HOST_NAME()),
	[HostPID] int NULL CONSTRAINT DF_tblService_HostPID DEFAULT (HOST_ID()),
	[AppName] sysname NULL CONSTRAINT DF_tblService_AppName DEFAULT (APP_NAME()),
	[Description] nvarchar(1000) NULL,
	[LastHeartbeatUTC] datetime NULL CONSTRAINT DF_tblService_LastHeartbeat DEFAULT (GETUTCDATE()),
	[LastInitializationUTC] datetime NULL CONSTRAINT DF_tblService_LastInit DEFAULT (GETUTCDATE()),
	[ServiceAccountName] sysname NULL CONSTRAINT DF_tblService_ServiceAccount DEFAULT (SUSER_SNAME()),
	[ServiceTypeId] tinyint NOT NULL CONSTRAINT FK_tblService_ServiceType FOREIGN KEY REFERENCES dbo.tblServiceTypes(TypeId) ON UPDATE CASCADE ON DELETE NO ACTION,
	[Enabled] bit NOT NULL CONSTRAINT DF_tblService_Enabled DEFAULT (1), 
    [Details] XML NULL,
    [ServiceIP] VARCHAR(25) COLLATE SQL_Latin1_General_CP1_CI_AS /* COLLATE Latin1_General_100_CI_AI_SC_UTF8 */ NULL CONSTRAINT DF_tblService_IP DEFAULT (CONVERT(varchar(25),CONNECTIONPROPERTY('client_net_address'))),
	[LastSPID] int NULL CONSTRAINT DF_tblService_SPID DEFAULT (@@SPID),
	[ServiceVersion] varchar(25) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[StopTimeUTC] datetime NULL
)
GO
CREATE UNIQUE NONCLUSTERED INDEX UQ_ServiceHost ON dbo.tblService
(
	[ServiceTypeId] ASC, [HostName] ASC, [HostPID] ASC
)
INCLUDE([Enabled])
WHERE [HostPID] IS NOT NULL