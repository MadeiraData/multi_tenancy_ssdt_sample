CREATE TABLE [dbo].[tblTenantState]
(
	[StateId] tinyint NOT NULL CONSTRAINT PK_tblTenantState PRIMARY KEY CLUSTERED,
	[Name] sysname NOT NULL
)
