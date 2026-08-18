param(
    [Parameter(Mandatory = $true)]
    [string]$Source,
    [string]$OutputDirectory = "dist/plugins"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $Source).Path
$manifestPath = Join-Path $root "mwef-plugin.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "mwef-plugin.json is required at the plugin root"
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw "Only schemaVersion 1 is supported" }
if ($manifest.id -notmatch '^[a-z][a-z0-9_-]{0,47}$') { throw "Invalid plugin id" }
if (-not $manifest.version) { throw "Plugin version is required" }
if (-not $manifest.author) { throw "Plugin author is required" }

foreach ($language in @("zh-CN", "en")) {
    $languagePath = Join-Path $root "i18n/$language.json"
    if (Test-Path -LiteralPath $languagePath) {
        $null = Get-Content -Raw -LiteralPath $languagePath | ConvertFrom-Json
    }
}

$workspace = Split-Path -Parent $PSScriptRoot
$output = Join-Path $workspace $OutputDirectory
New-Item -ItemType Directory -Force -Path $output | Out-Null
$archive = Join-Path $output ("{0}-{1}.tar.gz" -f $manifest.id, $manifest.version)

Push-Location $root
try {
    $entries = Get-ChildItem -Force | Select-Object -ExpandProperty Name
    tar -czf $archive @entries
    if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

Get-Item -LiteralPath $archive
