/*
Post-Deployment Script Template
--------------------------------------------------------------------------------------
 This file contains SQL statements that will be appended to the build script.
 Use SQLCMD syntax to include a file in the post-deployment script.
 Example:      :r .\myfile.sql
 Use SQLCMD syntax to reference a variable in the post-deployment script.
 Example:      :setvar TableName MyTable
               SELECT * FROM [$(TableName)]
--------------------------------------------------------------------------------------
*/
GO
SET NOCOUNT ON;

-- Update or Create global params
MERGE INTO dbo.tblGlobalParams AS Target 
USING (VALUES 
   (N'DBVersion', '1.0.0.0', NULL, N'DB Version')
) 
AS Source (ParamName, ParamValueString, ParamValueInt, ParamDescription) 
ON Target.ParamName = Source.ParamName  
WHEN NOT MATCHED BY TARGET THEN 
INSERT (ParamName, ParamValueString, ParamValueInt, ParamDescription) 
VALUES (ParamName, ParamValueString, ParamValueInt, ParamDescription)
WHEN MATCHED AND EXISTS
(
    SELECT [Source].ParamName, [Source].ParamValueString, [Source].ParamValueInt, [Source].ParamDescription
    EXCEPT
    SELECT [Target].ParamName, [Target].ParamValueString, [Target].ParamValueInt, [Target].ParamDescription
) THEN
    UPDATE SET
        ParamValueString = [Source].ParamValueString,
        ParamValueInt = [Source].ParamValueInt,
        ParamDescription = [Source].ParamDescription
;

GO
PRINT N'Finished deploying DB Version ' + dbo.GetDBVersion()