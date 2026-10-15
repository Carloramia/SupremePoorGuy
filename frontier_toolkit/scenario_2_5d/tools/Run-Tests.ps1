param([string]$GodotPath = "", [switch]$Render)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'tools/Resolve-Godot.ps1')
$GodotPath = Resolve-ProjectGodot -ProjectRoot $projectRoot -GodotPath $GodotPath
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot '.tools/userdata'
try {
    & $GodotPath --headless --editor --path $projectRoot --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
    & $GodotPath --headless --path $projectRoot --script res://scenario_2_5d/debug/acceptance_tests.gd
    if ($LASTEXITCODE -ne 0) { throw 'Scenario acceptance tests failed' }
    if ($Render) {
        & $GodotPath --path $projectRoot --script res://scenario_2_5d/debug/render_preview.gd
        if ($LASTEXITCODE -ne 0) { throw 'Scenario render tests failed' }
    }
} finally { $env:APPDATA = $previousAppData }
