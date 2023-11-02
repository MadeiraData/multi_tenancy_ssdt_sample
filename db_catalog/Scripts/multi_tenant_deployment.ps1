<#
Run this manually first to make sure you can run Powershell scripts:
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser

When creating a scheduled task to run such scripts, use the following structure example:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Madeira\my_powershell_script.ps1"

Example usage:

.\multi_tenant_deployment.ps1 -SqlInstance $env:COMPUTERNAME `
-PromptBeforeTenantDeployments -TrustServerCertificate `
-FilesRootPath "C:\Users\EitanBlumin\Madeira\Everyone - Documents\Training Services\Internal Training\Multi-Tenancy\db_multitenancy_sample" `
-CatalogDacPacFilePath "\db_catalog\bin\Debug\db_catalog.dacpac" `
-CatalogPublishXmlFile "\db_catalog\bin\Debug\db_catalog.LOCAL.publish.xml" `
-TenantDacPacFilePath "\db_customer\bin\Debug\db_customer.dacpac" `
-TenantPublishXmlFile "\db_customer\bin\Debug\db_tenant_model.LOCAL.publish.xml" `
-UpdateAllTenantStates `
-logFileFolderPath "C:\Madeira\log" #-SqlUserName "db_admin" -SqlPassword "P@ssw0rd"

#>
<#
.DESCRIPTION
This script publishes the dacpacs to all tenants in the sql server instance.

.LINK
Partly based on: https://github.com/sanderstad/Azure-Devops-Duet
#>
Param
(
[string]$SqlInstance = $env:COMPUTERNAME,
[PSCredential]$SqlCredential,
[string]$SqlUserName,
[string]$SqlPassword,
[switch]$TrustServerCertificate,
[string]$CatalogDatabase = "db_catalog",
[string]$FilesRootPath = "C:\dacpac",
[string]$CatalogDacPacFilePath = "\db_catalog\bin\Debug\db_catalog.dacpac",
[string]$CatalogPublishXmlFile = "\db_catalog\bin\Debug\db_catalog.LOCAL.publish.xml",
[string]$TenantDacPacFilePath = "\db_customer\bin\Debug\db_customer.dacpac",
[string]$TenantPublishXmlFile = "\db_customer\bin\Debug\db_tenant_model.LOCAL.publish.xml",
[string]$TenantModelDBName,
[string]$TenantModelPublishXmlFile,
[switch]$EnableException,
[switch]$PromptBeforeTenantDeployments,
[switch]$SkipDeploymentForCatalog,
[switch]$SkipDeploymentForTenantModel,
[switch]$SkipDeploymentForTenants,
[parameter(Mandatory=$false)]
[ValidateRange(0,3)]
[int]$FilterByTenantState = 0,
[switch]$UpdateAllTenantStates,
[string]$logFileFolderPath = "C:\Madeira\log",
[string]$logFilePrefix = "db_deployments_",
[string]$logFileDateFormat = "yyyyMMdd_HHmmss",
[int]$logFileRetentionDays = 30
)
Process {
#region initialization
if ($logFileFolderPath -ne "")
{
    if (!(Test-Path -PathType Container -Path $logFileFolderPath)) {
        Write-Output "Creating directory $logFileFolderPath" | Out-Null
        New-Item -ItemType Directory -Force -Path $logFileFolderPath | Out-Null
    } else {
        $DatetoDelete = $(Get-Date).AddDays(-$logFileRetentionDays)
        Get-ChildItem $logFileFolderPath | Where-Object { $_.Name -like "*$logFilePrefix*" -and $_.LastWriteTime -lt $DatetoDelete } | Remove-Item | Out-Null
    }
    
    $logFilePath = $logFileFolderPath + "\$logFilePrefix" + (Get-Date -Format $logFileDateFormat) + ".LOG"

    # attempt to start the transcript log, but don't fail the script if unsuccessful:
    try 
    {
        Start-Transcript -Path $logFilePath -Append
    }
    catch [Exception]
    {
        Write-Warning "Unable to start Transcript: $($_.Exception.Message)"
        $logFileFolderPath = ""
    }
}
#endregion initialization

#region validations

if (-not $SqlInstance) {
    Write-Error -Message "Please enter a SQL Server instance" -Category InvalidArgument -ErrorAction Stop
    return
}

<# Uncommeting this will force SQL Authentication:

if (-not $SqlCredential -and -not $SqlUserName -and -not $SqlPassword) {
    Write-Error -Message "Please enter a credential" -Category InvalidArgument -ErrorAction Stop
    return
}
#>

if (-not $SqlCredential -and ($SqlUserName -and $SqlPassword)) {
    $password = ConvertTo-SecureString $SqlPassword -AsPlainText -Force;
    $SqlCredential = New-Object System.Management.Automation.PSCredential($SqlUserName, $password);
}

if (-not $SqlCredential) {
    Write-Output "Using Windows Authentication as $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
}

if (-not $CatalogDatabase) {
    Write-Error -Message "Please enter a database name for the multi-tenant catalog" -Category InvalidArgument -ErrorAction Stop
    return
}

if ($FilesRootPath) {
    $CatalogDacPacFilePath = $FilesRootPath + $CatalogDacPacFilePath
    $CatalogPublishXmlFile = $FilesRootPath + $CatalogPublishXmlFile
    $TenantDacPacFilePath = $FilesRootPath + $TenantDacPacFilePath
    $TenantPublishXmlFile = $FilesRootPath + $TenantPublishXmlFile
}

if (-not $CatalogDacPacFilePath) {
    Write-Error -Message "Please enter a DacPac file for the catalog DB" -Category InvalidArgument -ErrorAction Stop
    return
}
elseif (-not (Test-Path -Path $CatalogDacPacFilePath)) {
    Write-Error -Message "Could not find DacPac file for the catalog DB: $CatalogDacPacFilePath" -Category InvalidArgument -ErrorAction Stop
    return
}

if (-not $TenantDacPacFilePath) {
    Write-Error -Message "Please enter a DacPac file for the tenants" -Category InvalidArgument -ErrorAction Stop
    return
}
elseif (-not (Test-Path -Path $TenantDacPacFilePath)) {
    Write-Error -Message "Could not find DacPac file for the tenants: $TenantDacPacFilePath" -Category InvalidArgument -ErrorAction Stop
    return
}


if (-not $CatalogPublishXmlFile) {
    Write-Error -Message "Please enter a publish profile file for the catalog DB" -Category InvalidArgument -ErrorAction Stop
    return
}
elseif (-not (Test-Path -Path $CatalogPublishXmlFile)) {
    Write-Error -Message "Could not find publish profile for the catalog DB: $CatalogPublishXmlFile" -Category InvalidArgument -ErrorAction Stop
    return
}

if (-not $TenantPublishXmlFile) {
    Write-Error -Message "Please enter a publish profile file for the tenants" -Category InvalidArgument -ErrorAction Stop
    return
}
elseif (-not (Test-Path -Path $TenantPublishXmlFile)) {
    Write-Error -Message "Could not find publish profile for the tenants: $TenantPublishXmlFile" -Category InvalidArgument -ErrorAction Stop
    return
}


if (-not $TenantModelPublishXmlFile) {
    $TenantModelPublishXmlFile = $TenantPublishXmlFile
}
elseif (-not (Test-Path -Path $TenantModelPublishXmlFile)) {
    Write-Error -Message "Could not find publish profile for the tenant model: $TenantModelPublishXmlFile" -Category InvalidArgument -ErrorAction Stop
    return
}

#endregion validations

#region install-modules

Write-Progress -Activity "Initialization" -Status "Registering PSGallery" -PercentComplete 0

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (Get-PSRepository -Name "PSGallery") {
    Write-Verbose "PSGallery already registered"
} 
else {
    Write-Information "Registering PSGallery"
    Register-PSRepository -Default
}


# replace the array below with any modules that your script depends on.
# you can remove this region if your script doesn't need importing any modules.
$modules = @("PSFramework", "PSModuleDevelopment", "dbatools")
$i = 1

foreach ($module in $modules) {
    Write-Progress -Activity "Initialization" -Status "Installing module $module" -PercentComplete ($1 * 100 / $modules.Count)

    if (Get-Module -ListAvailable -Name $module) {
        Write-Verbose "$module already installed"
    } 
    else {
        Write-Information "Installing $module"
        Install-Module $module -Force -SkipPublisherCheck -Scope CurrentUser -ErrorAction Stop | Out-Null
        Import-Module $module -Force -Scope Local -PassThru | Out-Null
    }
    $i = $i + 1
}
Write-Progress -Activity "Initialization" -Completed

#endregion install-modules


#region main

Write-Progress -Activity "Deploying Tenant Catalog and Model" -Status "Connecting to $CatalogDatabase" -PercentComplete 0

try {
    $CatalogDBInstance = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database master -TrustServerCertificate:$TrustServerCertificate -NetworkProtocol TcpIp
    Write-PSFMessage -Level Important -Message $CatalogDBInstance.Name
}
catch {
    Write-Error -Message "Could not connect to $CatalogDatabase - $($_)" -Category ConnectionError -ErrorAction Stop
    return
}


# Publish the DACPAC file for the Catalog DB

if ($SkipDeploymentForCatalog) {
    Write-PSFMessage -Level Important -Message "Tenant Catalog deployment was skipped as requested"
} else {
    try {
    
        $params = @{
            SqlInstance   = $CatalogDBInstance
            Database      = $CatalogDatabase
            Path          = $CatalogDacPacFilePath
            PublishXml    = $CatalogPublishXmlFile
        }

        if ($SqlCredential) {
            $params["SqlCredential"] = $SqlCredential
        }

        Write-Progress -Activity "Deploying Tenant Catalog and Model" -Status "Deploying $CatalogDatabase" -PercentComplete 40
        Write-PSFMessage -Level Important -Message "Publishing DacPac to database $($params.Database) in server $($CatalogDBInstance)"
        Publish-DbaDacPackage @params -Verbose -EnableException
    }
    catch {
        Write-Error -Message "Could not publish DacPac to database $($params.Database) in server $($params.SqlInstance) - $($_)" -Category InvalidResult -ErrorAction Stop
        return
    }
}

# Retrieve the tenant model name

if ([string]::IsNullOrEmpty($TenantModelDBName) -or -not $TenantModelDBName) {
    Write-Progress -Activity "Deploying Tenant Catalog and Model" -Status "Retrieving Tenant Model Name" -PercentComplete 60
    $CatalogSqlInstance = Connect-DbaInstance -SqlInstance $CatalogDBInstance -SqlCredential $SqlCredential -Database $CatalogDatabase -TrustServerCertificate:$TrustServerCertificate -NetworkProtocol TcpIp
    $TenantModelName = Invoke-DbaQuery -Query "SELECT ParamValueString FROM dbo.tblGlobalParams WHERE ParamName = 'TenantModelDatabase'" -SqlInstance $CatalogSqlInstance -Database $CatalogDatabase
    $TenantModelDBName = $TenantModelName.ParamValueString
}

if ([string]::IsNullOrEmpty($TenantModelDBName) -or -not $TenantModelDBName) {
    Write-Error -Message "Tenant model database name was not identified ($TenantModelDBName)" -Category InvalidArgument -ErrorAction Stop
    return
} else {
    Write-PSFMessage -Level Important -Message "Identified tenant model database name: $TenantModelDBName"
}

# Publish the DACPAC file for the tenant model

if ($SkipDeploymentForTenantModel) {
    Write-PSFMessage -Level Important -Message "Tenant Model deployment was skipped as requested"
} else {
    try {

        $params = @{
            SqlInstance   = $CatalogDBInstance
            Database      = $TenantModelDBName
            Path          = $TenantDacPacFilePath
            PublishXml    = $TenantModelPublishXmlFile
        }

        if ($SqlCredential) {
            $params["SqlCredential"] = $SqlCredential
        }

        Write-Progress -Activity "Deploying Tenant Catalog and Model" -Status "Deploying $TenantModelDBName" -PercentComplete 100
        Write-PSFMessage -Level Important -Message "Publishing DacPac to database $($params.Database) in server $($params.SqlInstance)"
        Publish-DbaDacPackage @params -Verbose -EnableException
        
        $RdsBackupTaskDetails = Invoke-DbaQuery -SqlInstance $CatalogDBInstance -Database $CatalogDatabase -Query "-- Check if AWS-RDS:
IF DB_ID('rdsadmin') IS NOT NULL
BEGIN
	DECLARE @S3ARNSource nvarchar(4000), @CMD nvarchar(MAX);
	SELECT @S3ARNSource = [ParamValueString]
	FROM dbo.tblGlobalParams
	WHERE ParamName = 'TenantModelDatabase_RDS_S3_ARN_BackupPath'

	IF @S3ARNSource IS NULL
	BEGIN
		RAISERROR(N'Detected RDS instance, but S3 ARN backup path for the tenant model was not found. Unable to backup tenant model.',16,1);
	END
    ELSE
    BEGIN
	    RAISERROR(N'Backing up ''$($TenantModelDBName)'' to ''%s'' using RDS native backup',0,1,@S3ARNSource) WITH NOWAIT;
	    SET @CMD = 'msdb.dbo.rds_backup_database';

	    exec @CMD
		    @source_db_name='$($TenantModelDBName)',
		    @s3_arn_to_backup_to=@S3ARNSource,
		    @overwrite_s3_backup_file=1
    END
END
ELSE
BEGIN
	SELECT task_info = NULL, S3_object_arn = NULL
END"
        if ($RdsBackupTaskDetails[0].task_info)
        {
            Write-Output $RdsBackupTaskDetails[0].task_info
        }
    }
    catch {
        Write-Error -Message "Could not publish DacPac to database $($params.Database) in server $($params.SqlInstance) - $($_)" -Category InvalidResult -ErrorAction Stop
        return
    }
}

Write-Progress -Activity "Deploying Tenant Catalog and Model" -Completed

# Retrieve the tenant model version

if ($SkipDeploymentForTenants) {
    Write-PSFMessage -Level Important -Message "Tenants deployment was skipped as requested"
} else {
    $TenantModelSqlInstance = Connect-DbaInstance -SqlInstance $CatalogDBInstance -SqlCredential $SqlCredential -Database $TenantModelDBName -TrustServerCertificate:$TrustServerCertificate -NetworkProtocol TcpIp
    $TenantModelVersion = Invoke-DbaQuery -Query "SELECT dbo.GetDBVersion() AS DBVersion" -SqlInstance $TenantModelSqlInstance -Database $TenantModelDBName

    Write-PSFMessage -Level Important -Message "Tenant model version is: $($TenantModelVersion.DBVersion)"

    # Get list of tenants that need to be updated
    Write-Progress -Activity "Deploying Tenants" -Status "Retrieving Tenants List" -PercentComplete 0
    
    $tenantsQuery = "SELECT TenantUID, DBVersion, DataSource, DBName FROM dbo.tblTenants WHERE [State] = $FilterByTenantState AND VersionLocked = 0 AND (DataSource IS NOT NULL OR HAS_DBACCESS(DBName) = 1) AND DBVersion <> '$($TenantModelVersion.DBVersion)' ORDER BY [LastActivityDateUtc] ASC"
    $tenantStateText = "state $FilterByTenantState"

    if ($UpdateAllTenantStates) {
        $tenantsQuery = "SELECT TenantUID, DBVersion, DataSource, DBName FROM dbo.tblTenants WHERE VersionLocked = 0 AND (DataSource IS NOT NULL OR HAS_DBACCESS(DBName) = 1) AND DBVersion <> '$($TenantModelVersion.DBVersion)' ORDER BY [State] ASC, [LastActivityDateUtc] ASC"
        $tenantStateText = "ALL states"
    }

    $TenantsToUpdate = @()
    $CatalogSqlInstance = Connect-DbaInstance -SqlInstance $CatalogDBInstance -SqlCredential $SqlCredential -Database $CatalogDatabase -TrustServerCertificate:$TrustServerCertificate -NetworkProtocol TcpIp
    $TenantsToUpdate = $TenantsToUpdate + (Invoke-DbaQuery -Query $tenantsQuery -SqlInstance $CatalogSqlInstance -Database $CatalogDatabase)

    if (-not $TenantsToUpdate)
    {
        Write-PSFMessage -Level Important -Message "All tenants are up-to-date ($tenantStateText)"
    } else {
        Write-PSFMessage -Level Important -Message "Found $($TenantsToUpdate.Count) tenant(s) to update ($tenantStateText)"
    }

    $reply = "Y"
    if ($PromptBeforeTenantDeployments -and $TenantsToUpdate.Count -gt 0) {
        $reply = Read-Host "Are you sure you want to deploy changes to $($TenantsToUpdate.Count) tenant(s)? (Y|N)"

        if ($reply -ne "Y") {
            Write-PSFMessage -Level Important -Message "Skipping tenant deployments"
        }
    }

    ### PUBLISH TO EACH TENANT ###
    if ($reply -eq "Y")
    {
        $tenantCounter = 0

        foreach ($CurrentTenant in $TenantsToUpdate)
        {
            $tenantCounter = $tenantCounter + 1


            try {
                if ([string]::IsNullOrEmpty($CurrentTenant.DataSource) -or [string]::IsNullOrWhiteSpace($CurrentTenant.DataSource) -or -not ($CurrentTenant.DataSource)) {
                    $TenantSqlInstance = $CatalogDBInstance
                } else {
                    $TenantSqlInstance = Connect-DbaInstance -SqlInstance $CurrentTenant.DataSource -SqlCredential $SqlCredential -Database $CurrentTenant.DBName -TrustServerCertificate:$TrustServerCertificate -NetworkProtocol TcpIp
                }
        
                $params = @{
                    SqlInstance   = $TenantSqlInstance
                    Database      = $CurrentTenant.DBName
                    Path          = $TenantDacPacFilePath
                    PublishXml    = $TenantPublishXmlFile
                    EnableException = $EnableException
                }
        
                if ($SqlCredential) {
                    $params["SqlCredential"] = $SqlCredential
                }

                Write-Progress -Activity "Deploying Tenants" -Status "Deploying tenant $tenantCounter out of $($TenantsToUpdate.Count)" -PercentComplete ($tenantCounter * 100 / $TenantsToUpdate.Count)
                Write-PSFMessage -Level Important -Message "Publishing DacPac to database $($params.Database) in server $($params.SqlInstance) (tenant $tenantCounter out of $($TenantsToUpdate.Count))"
                Publish-DbaDacPackage @params -Verbose
                Invoke-DbaQuery -Query "UPDATE dbo.tblTenants SET DBVersion = '$($TenantModelVersion.DBVersion)', LastModifyDateUtc = GETUTCDATE() WHERE TenantUID = '$($CurrentTenant.TenantUID)'" -SqlInstance $CatalogSqlInstance -Database $CatalogDatabase | Out-Null
            }
            catch {
                Write-Error -Message "Could not publish DacPac to database $($CurrentTenant.DBName) in server $($TenantSqlInstance) - $($_)" -Category InvalidResult -ErrorAction Continue
                continue
            }
        }

        Write-Progress -Activity "Deploying Tenants" -Completed
        Write-PSFMessage -Level Important -Message "Finished deploying to $tenantCounter tenants out of $($TenantsToUpdate.Count)"

        $TenantsNotUpdated = Invoke-DbaQuery -Query $tenantsQuery -SqlInstance $CatalogSqlInstance -Database $CatalogDatabase

        if ($TenantsNotUpdated)
        {
            Write-PSFMessage -Level Important -Message "Not all tenants were updated to version $($TenantModelVersion.DBVersion)"
            $TenantsNotUpdated | Format-Table
        }
    }
}
#endregion main


#region finalization
if ($logFileFolderPath -ne "") { try { Stop-Transcript } catch { Write-Output "Unable to stop transcript" } }
#endregion finalization
}