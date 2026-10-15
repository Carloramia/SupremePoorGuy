param([string]$Source = 'res://world_map/demo/WorldMapDemo.tscn', [string]$Output = 'res://editor/examples/FrontierImported.mapproject.json', [string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'tools/Resolve-Godot.ps1')
$GodotPath = Resolve-ProjectGodot -ProjectRoot $projectRoot -GodotPath $GodotPath
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot '.tools/userdata'
try {
    & $GodotPath --headless --path $projectRoot --script res://editor/godot/import_world.gd -- "--source=$Source" "--output=$Output"
    if ($LASTEXITCODE -ne 0) { throw 'World map import failed.' }
} finally { $env:APPDATA = $previousAppData }
