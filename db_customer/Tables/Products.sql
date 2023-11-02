CREATE TABLE [dbo].[Products]
(
	[Id] int NOT NULL IDENTITY(1,1) CONSTRAINT PK_Products PRIMARY KEY CLUSTERED,
	[Name] nvarchar(128) NOT NULL,
	[ProductSubCategoryId] int NOT NULL CONSTRAINT FK_Products_ProductSubCategory FOREIGN KEY REFERENCES dbo.ProductSubCategory ([Id]),
	[Price] money NULL
)
