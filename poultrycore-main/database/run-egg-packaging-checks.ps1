# =============================================================================
# Run every egg packaging check (migrations 393-396 + the phase 7 regression)
# against a database. Read-only in effect: every check file runs in its own
# transaction and ends with ROLLBACK, so nothing is kept.
#
#   $env:PGPASSWORD = '<password>'
#   .\run-egg-packaging-checks.ps1 -DbHost 34.175.134.7 -Port 5432 -Database VisibilityCoreDB
#
# Exit code 0 = every check passed.
# =============================================================================

[CmdletBinding()]
param(
    [string] $DbHost   = '127.0.0.1',
    [int]    $Port     = 5433,
    [string] $Database = 'VisibilityCoreDB',
    [string] $User     = 'poultryapp',
    [string] $Psql     = 'C:\Program Files\PostgreSQL\18\bin\psql.exe',
    [string] $ChecksDir = (Join-Path $PSScriptRoot 'checks')
)

$ErrorActionPreference = 'Stop'
if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not $env:PGSSLMODE -and $DbHost -ne '127.0.0.1') { $env:PGSSLMODE = 'require' }

$checks = [ordered]@{
    'egg-packaging.test.sql'                = 'egg packaging: all checks passed'
    'egg-packaged-sales.test.sql'           = 'egg packaged sales: all checks passed'
    'egg-packaged-stock-movements.test.sql' = 'egg packaged stock movements: all checks passed'
    'egg-sales-report-packaging.test.sql'   = 'egg sales report packaging: all checks passed'
    'egg-packaging-regression.test.sql'     = 'egg packaging regression: all checks passed'
}

$failed = 0
foreach ($c in $checks.Keys) {
    $file = Join-Path $ChecksDir $c
    # cmd.exe does the redirection: PowerShell 5.1 turns a psql NOTICE on stderr into an error.
    $line = '"{0}" -h {1} -p {2} -U {3} -d {4} -X -w -q -f "{5}" 2>&1' -f $Psql, $DbHost, $Port, $User, $Database, $file
    $out = & cmd.exe /c $line
    $ok = $LASTEXITCODE -eq 0 -and ($out | Where-Object { $_ -match [regex]::Escape($checks[$c]) })
    $n = ($out | Where-Object { $_ -match 'NOTICE:\s+ok ' }).Count
    if ($ok) {
        Write-Host ("  PASS  {0}  ({1} checks)" -f $c, $n) -ForegroundColor Green
    } else {
        $failed++
        Write-Host ("  FAIL  {0}" -f $c) -ForegroundColor Red
        $out | Where-Object { $_ -match 'ERROR|FAIL|CONTEXT' } | ForEach-Object { Write-Host "        $_" }
    }
}
if ($failed) { Write-Host "$failed check file(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All egg packaging checks passed (nothing kept: every file rolled back).' -ForegroundColor Green
