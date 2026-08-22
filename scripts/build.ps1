param(
    [string]$OutputDirectory = "dist"
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$output = Join-Path $workspace $OutputDirectory
$manifest = Get-Content -Raw -LiteralPath (Join-Path $workspace "manifest.json") | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $output | Out-Null
$archive = Join-Path $output ("mwef-{0}.tar.gz" -f $manifest.version)

Push-Location $workspace
try {
    tar -czf $archive router-overlay builtin-plugins scripts docs schema examples tools manifest.json README.md README_CN.md build.sh LICENSE
} finally {
    Pop-Location
}

Get-Item $archive
