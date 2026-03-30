# Build and Publish PoultryFarmAPI (backend)
# Output: .\publish folder - ready to deploy to IIS, Azure, or any host

$ErrorActionPreference = "Stop"
$projectDir = $PSScriptRoot
$publishDir = Join-Path $projectDir "publish"
$zipPath = Join-Path $projectDir "publish.zip"

Write-Host "Building PoultryFarmAPI (Release)..." -ForegroundColor Cyan
Set-Location $projectDir
dotnet build -c Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nPublishing to $publishDir..." -ForegroundColor Cyan
dotnet publish -c Release -o $publishDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Optional: create zip for easy upload
if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path "$publishDir\*" -DestinationPath $zipPath
    Write-Host "`nZip created: $zipPath" -ForegroundColor Green
}

Write-Host "`nDone. Deploy folder: $publishDir" -ForegroundColor Green
