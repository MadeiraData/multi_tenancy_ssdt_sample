CREATE TABLE [dbo].[tblGlobalParams]
(
	[ID] INT IDENTITY (1, 1) NOT NULL CONSTRAINT PK_tblGlobalParams PRIMARY KEY CLUSTERED WITH(DATA_COMPRESSION = PAGE), 
    [ParamName] NVARCHAR(50) NOT NULL, 
    [ParamValueString] NVARCHAR(256) NULL, 
    [ParamValueInt] INT NULL, 
	[ParamValueDate] DATETIME NULL, 
    [TimeCreated] DATETIME NULL DEFAULT(GETUTCDATE()), 
    [TimeModified] DATETIME NULL DEFAULT(GETUTCDATE()), 
    [ParamDescription] NVARCHAR(MAX) NULL
)
GO
-- Avoid multiple keys with same name
-- Also improves query performance by param name
CREATE UNIQUE NONCLUSTERED INDEX UQ_tblGlobalParams_ParamNamePerTenant ON [dbo].[tblGlobalParams]
(
    [ParamName] ASC
)
INCLUDE ([ParamValueString], [ParamValueInt], [ParamValueDate])
WITH(DATA_COMPRESSION = PAGE)
