param([switch]$Render, [string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'tools/Resolve-Godot.ps1')
$GodotPath = Resolve-ProjectGodot -ProjectRoot $projectRoot -GodotPath $GodotPath
& node (Join-Path $projectRoot 'editor/tests/model.test.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Editor model tests failed.' }
& (Join-Path $PSScriptRoot 'Import-Level.ps1') -Source (Join-Path $projectRoot 'editor/examples/Frontier.mapproject.json') -GodotPath $GodotPath
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot '.tools/userdata'
try {
    & $GodotPath --headless --path $projectRoot --script res://editor/tests/godot_tests.gd
    if ($LASTEXITCODE -ne 0) { throw 'Godot export tests failed.' }
    if ($Render) {
        & $GodotPath --path $projectRoot --script res://editor/tests/godot_tests.gd
        if ($LASTEXITCODE -ne 0) { throw 'Godot render tests failed.' }
    }
} finally { $env:APPDATA = $previousAppData }
