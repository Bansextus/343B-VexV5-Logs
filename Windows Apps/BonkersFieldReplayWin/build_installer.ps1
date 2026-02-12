# Build an MSI installer using WiX Toolset v4
# Prereqs on Windows:
#   - .NET 8 SDK
#   - WiX Toolset v4 (wix.exe on PATH)
# Run from PowerShell.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$wix = Get-Command wix -ErrorAction SilentlyContinue
if (-not $wix) {
  Write-Error "WiX Toolset v4 not found. Install with: winget install WiXToolset.WiXToolset"
}

$publishDir = Join-Path $root "dist"
$exeName = "BonkersFieldReplayWin.exe"
$exePath = Join-Path $publishDir $exeName

if (-not (Test-Path $exePath)) {
  Write-Host "Publishing app..."
  dotnet publish -c Release -r win-x64 -p:PublishSingleFile=true -p:SelfContained=true -o $publishDir
}

$installerDir = Join-Path $root "installer"
$msiOut = Join-Path $installerDir "BonkersFieldReplayWin.msi"

Write-Host "Building MSI..."
& wix build (Join-Path $installerDir "Package.wxs") -o $msiOut -dSourceDir=$publishDir -dExeName=$exeName

Write-Host "Built: $msiOut"
