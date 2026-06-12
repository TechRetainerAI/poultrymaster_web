# =============================================================================
# Apply ALL migrations 001..086 to PoultryMaster (prod) in numeric order.
# Idempotent — already-applied ones become no-ops.
#
# Halts on first non-zero sqlcmd exit.
# =============================================================================

[CmdletBinding()]
param(
    [string] $Server   = '34.39.109.13',
    [string] $Database = 'PoultryMaster',
    [string] $User     = 'sqlserver',
    [string] $Password = 'Techretainer@77',
    [string] $MigrationsDir = (Join-Path $PSScriptRoot '..\..\poultrycore\PoultryFarmAPI\Migrations')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }

$files = Get-ChildItem -Path $MigrationsDir -Filter '*.sql' -File `
    | Where-Object { $_.Name -match '^\d{3}_' } `
    | Sort-Object { [int]($_.Name.Substring(0,3)) }, Name

Write-Host "Server:   $Server"
Write-Host "Database: $Database"
Write-Host "Files:    $($files.Count) migrations to apply"
Write-Host ""

$startTime = Get-Date
$applied   = @()
$failed    = $null

foreach ($f in $files) {
    $name = $f.Name
    $tStart = Get-Date

    $logFile = Join-Path $env:TEMP "mig_$($name).log"
    & sqlcmd `
        -S $Server -d $Database -U $User -P $Password -C -l 30 `
        -b -I -i $f.FullName *> $logFile

    $code = $LASTEXITCODE
    $elapsed = '{0:N1}s' -f ((Get-Date) - $tStart).TotalSeconds

    if ($code -eq 0) {
        Write-Host ("  [OK]  {0,-65} {1}" -f $name, $elapsed)
        $applied += $name
    } else {
        Write-Host ("  [FAIL] {0,-65} {1} (exit {2})" -f $name, $elapsed, $code) -ForegroundColor Red
        Write-Host "  --- sqlcmd output: ---" -ForegroundColor Red
        Get-Content $logFile | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        $failed = $name
        break
    }
}

$total = '{0:N1}s' -f ((Get-Date) - $startTime).TotalSeconds
Write-Host ""
if ($failed) {
    Write-Host "HALTED at $failed after $($applied.Count) successful files (total $total)." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All $($applied.Count) migrations applied without error (total $total)." -ForegroundColor Green
    exit 0
}
