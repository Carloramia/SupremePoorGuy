param([Parameter(Mandatory=$true)][string]$Source, [string]$Output = 'res://editor/exports', [string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$resolvedSource = (Resolve-Path -LiteralPath $Source).Path
& node (Join-Path $PSScriptRoot 'Validate-Level.cjs') $resolvedSource
if ($LASTEXITCODE -ne 0) { throw 'Fix configuration errors before importing.' }
. (Join-Path $projectRoot 'tools/Resolve-Godot.ps1')
$GodotPath = Resolve-ProjectGodot -ProjectRoot $projectRoot -GodotPath $GodotPath
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot '.tools/userdata'
try {
    & $GodotPath --headless --editor --path $projectRoot --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot resource import failed.' }
    & $GodotPath --headless --path $projectRoot --script res://editor/godot/import_level.gd -- "--source=$resolvedSource" "--output=$Output"
    if ($LASTEXITCODE -ne 0) { throw 'Level import failed.' }
} finally { $env:APPDATA = $previousAppData }
