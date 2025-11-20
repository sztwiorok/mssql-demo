# This script runs the setup_user.sql using your current Windows Credentials
# Run this LOCALLY where you have access

$ErrorActionPreference = "Stop"
$TargetFile = "setup_user.sql"

# Use the original connection string (Windows Auth) to create the new user
$ConnectionString = "Server=localhost;Database=master;Trusted_Connection=True;TrustServerCertificate=True;"

if (-not (Test-Path $TargetFile)) {
    Write-Error "$TargetFile not found."
    exit 1
}

Write-Host "Connecting to SQL Server to create 'MigrationUser'..." -ForegroundColor Cyan

try {
    $conn = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $conn.Open()

    $sqlQuery = Get-Content $TargetFile -Raw
    
    # Split by GO for execution
    $batches = $sqlQuery -split "(?m)^\s*GO\s*$"
    
    foreach ($batch in $batches) {
        if (-not [string]::IsNullOrWhiteSpace($batch)) {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $batch
            $cmd.ExecuteNonQuery() | Out-Null
        }
    }

    Write-Host "Success! User 'MigrationUser' has been created/configured." -ForegroundColor Green
}
catch {
    Write-Error "Failed to create user. Ensure you are running this locally as an Administrator."
    Write-Error $_
}
finally {
    if ($conn) { $conn.Dispose() }
}

