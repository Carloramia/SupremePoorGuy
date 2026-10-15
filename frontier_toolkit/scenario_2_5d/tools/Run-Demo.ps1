param([string]$GodotPath = "", [switch]$Editor)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'tools/Resolve-Godot.ps1')
$GodotPath = Resolve-ProjectGodot -ProjectRoot $projectRoot -GodotPath $GodotPath
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot '.tools/userdata'
try {
    & $GodotPath --headless --editor --path $projectRoot --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
    if ($Editor) { & $GodotPath --editor --path $projectRoot res://scenario_2_5d/demo/Scenario25DDemo.tscn }
    else { & $GodotPath --path $projectRoot res://scenario_2_5d/demo/Scenario25DDemo.tscn }
} finally { $env:APPDATA = $previousAppData }
