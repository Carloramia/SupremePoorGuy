param([string]$GodotPath = "", [switch]$Render)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'tools/Resolve-Godot.ps1')
$GodotPath = Resolve-ProjectGodot -ProjectRoot $projectRoot -GodotPath $GodotPath
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot '.tools\userdata'
try {
    & $GodotPath --headless --editor --path $projectRoot --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
    & $GodotPath --headless --path $projectRoot --script res://world_map/debug/data_validation.gd
    if ($LASTEXITCODE -ne 0) { throw 'Data validation failed' }
    & $GodotPath --headless --path $projectRoot --script res://world_map/debug/acceptance_tests.gd
    if ($LASTEXITCODE -ne 0) { throw 'Acceptance tests failed. See world_map/debug/test_results.json.' }
    & $GodotPath --headless --path $projectRoot --script res://world_map/debug/road_tests.gd
    if ($LASTEXITCODE -ne 0) { throw 'Road tests failed. See world_map/debug/road_test_results.json.' }
    & $GodotPath --headless --path $projectRoot --script res://integration/scenario_overlay_tests.gd
    if ($LASTEXITCODE -ne 0) { throw 'Scenario overlay tests failed. See integration/scenario_overlay_test_results.json.' }
    if ($Render) {
        & $GodotPath --path $projectRoot --script res://integration/scenario_overlay_tests.gd
        if ($LASTEXITCODE -ne 0) { throw 'Scenario overlay render verification failed.' }
        & $GodotPath --path $projectRoot --script res://world_map/debug/hex_debug_render_test.gd
        if ($LASTEXITCODE -ne 0) { throw 'Hex debug render regression failed.' }
        & $GodotPath --path $projectRoot --script res://world_map/debug/road_render_preview.gd
        if ($LASTEXITCODE -ne 0) { throw 'Road render verification failed.' }
    }
} finally { $env:APPDATA = $previousAppData }
