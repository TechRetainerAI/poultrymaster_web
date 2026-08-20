<#
.SYNOPSIS
  Wires up local development configuration for PoultryFarmAPI + LoginAPI (User.Management.API).

.DESCRIPTION
  Neither API ships with a working local connection string -- by design, so credentials
  never land in git. This script fills that gap:

    * PoultryFarmAPI  -> .NET User Secrets      (ConnectionStrings:PoultryConn, JWT:Secret)
    * LoginAPI        -> appsettings.Local.json (gitignored, loaded last in Development)

  Both APIs get the SAME JWT:Secret. That is mandatory: the browser gets its token from
  the Login API and sends it to the Farm API. Different keys => every Farm call is 401.

  Your password is never written to a git-tracked file, and never echoed to the console.

.EXAMPLE
  .\setup-local-dev.ps1 -DbPassword 'yourPostgresPassword'

.EXAMPLE
  .\setup-local-dev.ps1 -DbPassword 'yourPostgresPassword' -DbName poultrycore -DbUser postgres
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DbPassword,

    # Leave empty to auto-detect the database that contains the "farms" table.
    [string]$DbName = '',

    [string]$DbUser = 'postgres',
    [string]$DbHost = 'localhost',
    [int]$DbPort = 5432,

    # Shared HS256 signing key. Must be >= 32 characters and identical for both APIs.
    [string]$JwtSecret = '6OENMJ6gid/2oz2y1kBk5Yn29sRMlyIH2blkzySUJdfq2y6lhStqgQdPuR9naoIz'
)

$ErrorActionPreference = 'Stop'
$root      = $PSScriptRoot
$farmProj  = Join-Path $root 'PoultryFarmAPI\PoultryFarmAPI.csproj'
$loginDir  = Join-Path $root 'LoginAPI\User.Management.API'
$loginProj = Join-Path $loginDir 'User.Management.API.csproj'
$localJson = Join-Path $loginDir 'appsettings.Local.json'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok  ($msg) { Write-Host "    OK   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    WARN $msg" -ForegroundColor Yellow }

if ($JwtSecret.Length -lt 32) {
    throw "JwtSecret must be at least 32 characters (HS256). Got $($JwtSecret.Length)."
}

# ---------------------------------------------------------------- locate psql
Write-Step 'Locating psql'
$psql = Get-Command psql -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $psql) {
    $psql = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $psql) { throw 'psql.exe not found. Install the PostgreSQL client tools or add them to PATH.' }
Write-Ok $psql

# PGPASSWORD goes through the environment so psql never opens an interactive prompt.
# An interactive prompt is the classic way a script like this hangs forever.
$env:PGPASSWORD = $DbPassword

function Invoke-Psql {
    param([string]$Database, [string]$Sql)
    # -A -t -q => unaligned, tuples-only, quiet: a single parseable value.
    $out = & $psql -h $DbHost -p $DbPort -U $DbUser -d $Database -v ON_ERROR_STOP=1 -A -t -q -c $Sql 2>&1
    return @{ Ok = ($LASTEXITCODE -eq 0); Out = ($out -join "`n").Trim() }
}

# ------------------------------------------------------- verify the credentials
Write-Step "Testing connection to ${DbHost}:${DbPort} as '$DbUser'"
$ping = Invoke-Psql -Database 'postgres' -Sql 'select 1'
if (-not $ping.Ok) {
    Write-Host $ping.Out -ForegroundColor Red
    throw "Could not connect. Check the password, and that role '$DbUser' exists."
}
Write-Ok 'Authenticated'

# ------------------------------------------------------------- pick a database
Write-Step 'Selecting database'
$dbList = Invoke-Psql -Database 'postgres' -Sql "select datname from pg_database where datistemplate = false and datname <> 'postgres' order by datname"
$databases = @($dbList.Out -split "`n" | Where-Object { $_ -ne '' })

if ($DbName) {
    if ($databases -notcontains $DbName) {
        Write-Warn "Database '$DbName' is not in the server list: $($databases -join ', ')"
    }
} else {
    Write-Host "    Candidates: $($databases -join ', ')"
    # The farms table is the marker. Both APIs join farms.id, and sp_createfarm --
    # called by the Login API during registration -- lives on that same database.
    foreach ($candidate in $databases) {
        $probe = Invoke-Psql -Database $candidate -Sql "select count(*) from information_schema.tables where table_name = 'farms'"
        if ($probe.Ok -and $probe.Out -eq '1') { $DbName = $candidate; break }
    }
    if (-not $DbName) {
        throw ("No database contains a 'farms' table. Re-run with -DbName <name>. Found: " + ($databases -join ', '))
    }
}
Write-Ok "Using database '$DbName'"

# ---------------------------------------------------------- report schema state
Write-Step 'Checking schema'
$farms = Invoke-Psql -Database $DbName -Sql "select count(*) from information_schema.tables where table_name = 'farms'"
$ident = Invoke-Psql -Database $DbName -Sql "select count(*) from information_schema.tables where lower(table_name) = 'aspnetusers'"
$spcf  = Invoke-Psql -Database $DbName -Sql "select count(*) from pg_proc where proname = 'sp_createfarm'"
Write-Host "    farms table       : $(if ($farms.Out -eq '1') { 'present' } else { 'MISSING' })"
Write-Host "    AspNetUsers table : $(if ($ident.Out -eq '1') { 'present' } else { 'missing (EF creates it on first Login API run)' })"
Write-Host "    sp_createfarm     : $(if ($spcf.Out -ne '0') { 'present' } else { 'MISSING -- farm registration will fail' })"

$connString = "Host=$DbHost;Port=$DbPort;Database=$DbName;Username=$DbUser;Password=$DbPassword"

# --------------------------------------------- PoultryFarmAPI via User Secrets
# WebApplication.CreateBuilder auto-loads User Secrets when ASPNETCORE_ENVIRONMENT
# is Development, so no code change is needed for these to be picked up.
Write-Step 'Configuring PoultryFarmAPI (User Secrets)'
& dotnet user-secrets --project $farmProj init | Out-Null
& dotnet user-secrets --project $farmProj set 'ConnectionStrings:PoultryConn' $connString | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'dotnet user-secrets failed for PoultryFarmAPI.' }
& dotnet user-secrets --project $farmProj set 'JWT:Secret' $JwtSecret | Out-Null
Write-Ok 'ConnectionStrings:PoultryConn and JWT:Secret stored'

# ------------------------------------------ LoginAPI via appsettings.Local.json
# Program.cs (~line 32) adds appsettings.Local.json AFTER user secrets in Development,
# so this file is the last word. .gitignore already covers **/appsettings.Local.json.
Write-Step 'Configuring LoginAPI (appsettings.Local.json)'
$payload = [ordered]@{
    ConnectionStrings = [ordered]@{ ConnStr = $connString }
    JWT               = [ordered]@{ Secret  = $JwtSecret }
}
$payload | ConvertTo-Json -Depth 5 | Set-Content -Path $localJson -Encoding UTF8
Write-Ok $localJson

# ---------------------------------------------------------------------- verify
Write-Step 'Verifying both projects build'
foreach ($p in @($farmProj, $loginProj)) {
    & dotnet build $p -v q --nologo | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $p" }
    Write-Ok (Split-Path $p -Leaf)
}

$env:PGPASSWORD = $null

Write-Host @"

------------------------------------------------------------------
Done. Start the two APIs in separate terminals:

  dotnet run --project "PoultryFarmAPI\PoultryFarmAPI.csproj"
      -> https://localhost:7190/swagger   (http://localhost:5142)

  dotnet run --project "LoginAPI\User.Management.API\User.Management.API.csproj"
      -> https://localhost:7010/swagger   (http://localhost:5010)

First login (seeded by DatabaseBootstrap in Development):
  POST /api/Authentication/login
  { "username": "systemadmin", "password": "DevSystemAdmin!23", "rememberMe": true }

Frontend: copy poultrycore-main\.env.example to .env.local and keep the
localhost:7190 / localhost:7010 values.
------------------------------------------------------------------
"@ -ForegroundColor Cyan
