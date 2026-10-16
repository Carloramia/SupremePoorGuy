param([string]$GodotPath = '', [switch]$Standalone)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'tools/Resolve-Godot.ps1')
$GodotPath = Resolve-ProjectGodot -ProjectRoot $projectRoot -GodotPath $GodotPath
$scene = if ($Standalone) { 'res://ui_module/demo/UIModuleDemo.tscn' } else { 'res://ui_module/demo/UIWorldMapDemo.tscn' }
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot '.tools/userdata'
try {
    & $GodotPath --headless --editor --path $projectRoot --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
    & $GodotPath --path $projectRoot $scene
} finally { $env:APPDATA = $previousAppData }
