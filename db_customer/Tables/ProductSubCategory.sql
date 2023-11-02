CREATE TABLE [dbo].[ProductSubCategory]
(
	[Id] INT NOT NULL IDENTITY(1,1) CONSTRAINT PK_ProductSubCategory PRIMARY KEY CLUSTERED,
	[ParentCategoryId] int NOT NULL CONSTRAINT FK_ProductSubCategory_ProductCategory FOREIGN KEY REFERENCES dbo.ProductCategory([Id]),
	[Name] nvarchar(128) NOT NULL
)
