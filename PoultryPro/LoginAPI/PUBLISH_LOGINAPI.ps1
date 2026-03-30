$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$apiProject = Join-Path $root "User.Management.API\User.Management.API.csproj"
$publishDir = Join-Path $root "publish\User.Management.API"

Write-Host "Restoring packages..."
dotnet restore $apiProject --disable-parallel

Write-Host "Publishing Release build..."
dotnet publish $apiProject -c Release -o $publishDir --no-restore

Write-Host "Publish completed at: $publishDir"
