CREATE TABLE [dbo].[tblTenantModelDataTables]
(
	[ExecutionOrder] smallint NOT NULL CONSTRAINT DF_tblTenantModelDataTables_ExecOrder DEFAULT (0),
	[SchemaName] sysname NOT NULL,
	[TableName] sysname NOT NULL,
	CONSTRAINT PK_tblTenantModelDataTables PRIMARY KEY NONCLUSTERED([SchemaName], [TableName])
)
GO
CREATE UNIQUE CLUSTERED INDEX IX_tblTenantModelDataTables_ExecutionOrder ON [dbo].[tblTenantModelDataTables]
(ExecutionOrder, [SchemaName], [TableName])
GO