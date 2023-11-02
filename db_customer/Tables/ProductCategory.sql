CREATE TABLE [dbo].[ProductCategory]
(
	[Id] INT NOT NULL IDENTITY(1,1) CONSTRAINT PK_ProductCategory PRIMARY KEY CLUSTERED,
	[Name] nvarchar(128) NOT NULL
)
