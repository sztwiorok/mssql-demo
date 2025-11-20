param(
    [string]$ConfigFile = "migration.properties"
)

$ErrorActionPreference = "Stop"

# Helper: Parse properties file key=value
function Get-PropertiesFromFile {
    param([string]$filePath)
    $props = @{}
    if (Test-Path $filePath) {
        Get-Content $filePath | Where-Object { $_ -match '=' -and $_ -notmatch '^\s*#' } | ForEach-Object {
            $parts = $_ -split '=', 2
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            $props[$key] = $value
        }
    }
    return $props
}

Write-Host "--------------------------------------------------" -ForegroundColor Gray
Write-Host " Database Initialization (Create Migration Table)" -ForegroundColor Cyan
Write-Host "--------------------------------------------------" -ForegroundColor Gray

# 1. Load Configuration
$config = Get-PropertiesFromFile $ConfigFile
$ConnectionString = $config["ConnectionString"]

if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
    Write-Error "ConnectionString is required in $ConfigFile"
    exit 1
}

# 2. Initialize Database
try {
    $conn = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $conn.Open()
    
    $sql = @"
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = '__Migrations')
    BEGIN
        CREATE TABLE dbo.__Migrations (
            Id INT IDENTITY(1,1) PRIMARY KEY,
            MigrationId NVARCHAR(255) NOT NULL,
            VersionNumber INT NOT NULL,
            AppliedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        )
        PRINT 'Table [__Migrations] created.'
    END
    ELSE
    BEGIN
        PRINT 'Table [__Migrations] already exists.'
    END
"@
    
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.ExecuteNonQuery() | Out-Null
    
    Write-Host "Success: Migration table check completed." -ForegroundColor Green
}
catch {
    Write-Error "Failed to initialize database. Ensure the database exists and connection string is correct."
    Write-Error $_
    exit 1
}
finally {
    if ($conn) { $conn.Dispose() }
}

