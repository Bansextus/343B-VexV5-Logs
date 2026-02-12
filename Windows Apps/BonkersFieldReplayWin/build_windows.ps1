# Run this on Windows with .NET 8 SDK installed.
# Produces a single-file EXE in ./dist

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$publishDir = Join-Path $root "dist"
if (Test-Path $publishDir) {
  Remove-Item $publishDir -Recurse -Force
}

# Build single-file, self-contained EXE
& dotnet publish -c Release -r win-x64 -p:PublishSingleFile=true -p:SelfContained=true -o $publishDir

Write-Host "Built: $publishDir\BonkersFieldReplayWin.exe"
