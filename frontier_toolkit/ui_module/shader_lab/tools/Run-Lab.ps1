param([string]$GodotPath = '', [switch]$Tests, [switch]$Capture)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $projectRoot 'tools/Resolve-Godot.ps1')
$GodotPath = Resolve-ProjectGodot -ProjectRoot $projectRoot -GodotPath $GodotPath
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot '.tools/userdata'
try {
    if ($Tests -or $Capture) {
        $argsList = @('--path', $projectRoot, '--script', 'res://ui_module/shader_lab/tests/acceptance.gd')
        if ($Capture) { $argsList += @('--', '--capture') }
        else { $argsList = @('--headless') + $argsList }
        $output = & $GodotPath @argsList 2>&1 | Out-String
        Write-Output $output
        # Windows sandbox can deny the OS certificate store during headless runs.
        # That unrelated startup diagnostic is the only ignored ERROR.
        $checkOutput = $output -replace 'ERROR: Failed to read the root certificate store\.', ''
        if ($LASTEXITCODE -ne 0 -or $checkOutput -match 'SCRIPT ERROR:|SHADER ERROR:|Parse Error|ERROR:' -or $output -notmatch 'SHADER_LAB checks=\d+ failures=0') {
            throw 'Shader lab verification failed. Inspect the output above.'
        }
    } else {
        & $GodotPath --path $projectRoot --resolution 1280x720 res://ui_module/shader_lab/demo/ShaderLab.tscn
    }
} finally {
    $env:APPDATA = $previousAppData
}
