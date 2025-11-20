param(
    [string]$ConnectionString,
    [int]$TargetVersion,
    [string]$MigrationPath,
    [string]$ConfigFile = "migration.properties"
)

# Improve error display
$ErrorActionPreference = "Stop"

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

# 1. Load Configuration
$config = Get-PropertiesFromFile $ConfigFile

# 2. Resolve Parameters (Command Line > Config File > Defaults)
if (-not $ConnectionString) { $ConnectionString = $config["ConnectionString"] }

if (-not $PSBoundParameters.ContainsKey('TargetVersion') -and $config.ContainsKey("TargetVersion")) { 
    $TargetVersion = [int]$config["TargetVersion"] 
}

if (-not $MigrationPath) { 
    $MigrationPath = if ($config["MigrationPath"]) { $config["MigrationPath"] } else { ".\migrations" } 
}

# Validate
if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
    Write-Error "ConnectionString is required. Provide it via -ConnectionString or in $ConfigFile"
    exit 1
}

if (-not $PSBoundParameters.ContainsKey('TargetVersion') -and -not $config.ContainsKey("TargetVersion")) {
    Write-Error "TargetVersion is required. Provide it via -TargetVersion or in $ConfigFile"
    exit 1
}

Write-Host "--------------------------------------------------" -ForegroundColor Gray
Write-Host " MSSQL Migration Runner" -ForegroundColor Cyan
Write-Host "--------------------------------------------------" -ForegroundColor Gray
Write-Host " Config File:    $ConfigFile"
Write-Host " Migration Path: $MigrationPath"
Write-Host " Target Version: $TargetVersion"
Write-Host "--------------------------------------------------" -ForegroundColor Gray

# Helper: Execute SQL Batch (used for initialization)
function Invoke-SqlBatchSimple {
    param([string]$ConnectionString, [string]$Query)
    $conn = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    try {
        $conn.Open()
        $batches = $Query -split "(?m)^\s*GO\s*$"
        foreach ($batch in $batches) {
            if (-not [string]::IsNullOrWhiteSpace($batch)) {
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $batch
                $cmd.ExecuteNonQuery() | Out-Null
            }
        }
    }
    finally { $conn.Dispose() }
}

# Helper: Execute Migration Transactionally
function Invoke-MigrationStep {
    param(
        [string]$ConnectionString,
        [string]$Query,
        [string]$VersionSql
    )
    
    $conn = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $conn.Open()
    $trans = $conn.BeginTransaction()
    
    try {
        # Run user migration script (split by GO)
        $batches = $Query -split "(?m)^\s*GO\s*$"
        foreach ($batch in $batches) {
            if (-not [string]::IsNullOrWhiteSpace($batch)) {
                $cmd = $conn.CreateCommand()
                $cmd.Transaction = $trans
                $cmd.CommandText = $batch
                $cmd.CommandTimeout = 0 # No timeout for migrations
                $cmd.ExecuteNonQuery() | Out-Null
            }
        }
        
        # Update version table
        $cmdVer = $conn.CreateCommand()
        $cmdVer.Transaction = $trans
        $cmdVer.CommandText = $VersionSql
        $cmdVer.ExecuteNonQuery() | Out-Null
        
        $trans.Commit()
    }
    catch {
        $trans.Rollback()
        throw $_
    }
    finally {
        $conn.Dispose()
    }
}

# 3. Initialize Migration Table
try {
    $initSql = @"
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = '__Migrations')
    BEGIN
        CREATE TABLE dbo.__Migrations (
            Id INT IDENTITY(1,1) PRIMARY KEY,
            MigrationId NVARCHAR(255) NOT NULL,
            VersionNumber INT NOT NULL,
            AppliedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        )
    END
"@
    Invoke-SqlBatchSimple -ConnectionString $ConnectionString -Query $initSql
}
catch {
    Write-Error "Failed to connect or initialize database. Check connection string."
    Write-Error $_
    exit 1
}

# 4. Get Current Version
try {
    $conn = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT TOP 1 VersionNumber FROM dbo.__Migrations ORDER BY Id DESC"
    $result = $cmd.ExecuteScalar()
    $CurrentVersion = if ($result -ne $null) { [int]$result } else { 0 }
}
finally { $conn.Dispose() }

Write-Host " Current Version: $CurrentVersion" -ForegroundColor Yellow
Write-Host ""

# 5. Scan Migrations
if (-not (Test-Path $MigrationPath)) {
    Write-Error "Migration directory not found at $MigrationPath"
    exit 1
}

$migrationFolders = Get-ChildItem $MigrationPath | Where-Object { $_.PSIsContainer } | Sort-Object Name
$migrations = @()

foreach ($folder in $migrationFolders) {
    if ($folder.Name -match "^(\d+)_") {
        $ver = [int]$matches[1]
        $migrations += [PSCustomObject]@{
            Version = $ver
            Path = $folder.FullName
            Name = $folder.Name
        }
    }
}

if ($migrations.Count -eq 0) {
    Write-Warning "No migration folders found in $MigrationPath"
    exit 0
}

# 6. Execute Logic
if ($TargetVersion -eq $CurrentVersion) {
    Write-Host "Database is up to date." -ForegroundColor Green
    exit 0
}

if ($TargetVersion -gt $CurrentVersion) {
    # UP
    $toApply = $migrations | Where-Object { $_.Version -gt $CurrentVersion -and $_.Version -le $TargetVersion } | Sort-Object Version
    
    if ($toApply.Count -eq 0) {
        Write-Warning "Target version $TargetVersion is higher than current, but no intermediate migrations were found."
        exit 0
    }

    foreach ($m in $toApply) {
        $file = Join-Path $m.Path "up.sql"
        if (-not (Test-Path $file)) { 
            Write-Error "Missing 'up.sql' in $($m.Name)"
            exit 1 
        }
        
        Write-Host " -> Applying UP: $($m.Name) ... " -NoNewline -ForegroundColor Cyan
        
        $sqlContent = Get-Content $file -Raw
        $verSql = "INSERT INTO dbo.__Migrations (MigrationId, VersionNumber) VALUES ('$($m.Name)', $($m.Version))"
        
        try {
            Invoke-MigrationStep -ConnectionString $ConnectionString -Query $sqlContent -VersionSql $verSql
            Write-Host "OK" -ForegroundColor Green
        }
        catch {
            Write-Host "FAILED" -ForegroundColor Red
            Write-Error "Migration failed: $_"
            exit 1
        }
    }
}
else {
    # DOWN
    $toRollback = $migrations | Where-Object { $_.Version -le $CurrentVersion -and $_.Version -gt $TargetVersion } | Sort-Object Version -Descending
    
    foreach ($m in $toRollback) {
        $file = Join-Path $m.Path "down.sql"
        if (-not (Test-Path $file)) { 
            Write-Error "Missing 'down.sql' in $($m.Name)"
            exit 1 
        }
        
        Write-Host " -> Applying DOWN: $($m.Name) ... " -NoNewline -ForegroundColor Magenta
        
        $sqlContent = Get-Content $file -Raw
        $verSql = "DELETE FROM dbo.__Migrations WHERE VersionNumber = $($m.Version)"
        
        try {
            Invoke-MigrationStep -ConnectionString $ConnectionString -Query $sqlContent -VersionSql $verSql
            Write-Host "OK" -ForegroundColor Green
        }
        catch {
            Write-Host "FAILED" -ForegroundColor Red
            Write-Error "Rollback failed: $_"
            exit 1
        }
    }
}

Write-Host ""
Write-Host "Done. Database is now at version $TargetVersion." -ForegroundColor Green

