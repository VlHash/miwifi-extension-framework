param(
    [string]$OutputDirectory = "dist"
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$output = Join-Path $workspace $OutputDirectory
New-Item -ItemType Directory -Force -Path $output | Out-Null
$archive = Join-Path $output "mwef-0.2.3.tar.gz"

Push-Location $workspace
try {
    tar -czf $archive router-overlay builtin-plugins scripts docs schema examples tools manifest.json README.md LICENSE
} finally {
    Pop-Location
}

Get-Item $archive
