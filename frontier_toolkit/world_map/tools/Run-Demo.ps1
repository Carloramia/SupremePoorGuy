param([string]$GodotPath = "", [switch]$Editor)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'tools/Resolve-Godot.ps1')
$GodotPath = Resolve-ProjectGodot -ProjectRoot $projectRoot -GodotPath $GodotPath
# Keep this portable demo's editor data and user:// saves inside its own workspace.
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot '.tools\userdata'
try {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.godot\global_script_class_cache.cfg'))) {
        & $GodotPath --headless --editor --path $projectRoot --import --quit
        if ($LASTEXITCODE -ne 0) { throw 'Initial Godot import failed' }
    }
    if ($Editor) { & $GodotPath --editor --path $projectRoot }
    else { & $GodotPath --path $projectRoot }
} finally { $env:APPDATA = $previousAppData }
