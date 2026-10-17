param(
    [Parameter(Mandatory=$true)][string]$Source,
    [string]$Version = ('level_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),
    [string]$GodotPath = ''
)
$ErrorActionPreference = 'Stop'
$integrationProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if ($Version -notmatch '^[A-Za-z0-9_-]+$') { throw 'Version must use letters, numbers, underscores or hyphens.' }
$integrationOutput = Join-Path $integrationProject "Content/Maps/$Version"
if (Test-Path -LiteralPath $integrationOutput) { throw 'Version already exists; choose a new version to preserve edited content.' }
$integrationSource = (Resolve-Path -LiteralPath $Source).Path
$integrationToolkit = Join-Path $integrationProject '../frontier_toolkit'
& node (Join-Path $integrationToolkit 'editor/tools/Validate-Level.cjs') $integrationSource
if ($LASTEXITCODE -ne 0) { throw 'Configuration validation failed.' }
if (-not $GodotPath) {
    if ($env:GODOT_BIN) { $GodotPath = $env:GODOT_BIN }
    else { $GodotPath = (Get-Command godot -ErrorAction Stop).Source }
}
$integrationOldAppData = $env:APPDATA
$integrationOldLocalData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $integrationProject 'Tests/.runtime/frontier-import/AppData'
    $env:LOCALAPPDATA = Join-Path $integrationProject 'Tests/.runtime/frontier-import/LocalAppData'
    New-Item -ItemType Directory -Path $env:APPDATA,$env:LOCALAPPDATA -Force | Out-Null
    $integrationImport = & $GodotPath --headless --editor --path $integrationProject --import --quit 2>&1
    $integrationImport | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($integrationImport -match 'SCRIPT ERROR|Parse Error')) { throw 'Resource import failed.' }
    $integrationConversion = & $GodotPath --headless --path $integrationProject --script res://Tools/Integration/Frontier/godot/import_level.gd -- "--source=$integrationSource" "--output=res://Content/Maps/$Version" 2>&1
    $integrationConversion | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($integrationConversion -match 'SCRIPT ERROR|Parse Error')) { throw 'Level conversion failed; do not use incomplete output.' }
} finally {
    $env:APPDATA = $integrationOldAppData
    $env:LOCALAPPDATA = $integrationOldLocalData
}
