param([string]$GodotPath = '', [switch]$Render)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'tools/Resolve-Godot.ps1')
$GodotPath = Resolve-ProjectGodot -ProjectRoot $projectRoot -GodotPath $GodotPath
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot '.tools/userdata'
New-Item -ItemType Directory -Path (Join-Path $projectRoot '.tools'), (Join-Path $projectRoot 'ui_module/tests/screenshots') -Force | Out-Null
$results = [System.Collections.Generic.List[object]]::new()
function Invoke-UICheck([string[]]$GodotArguments, [string]$Expected = '') {
    $output = & $GodotPath @GodotArguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    Write-Output $output
    if ($exitCode -ne 0 -or $output -match 'SCRIPT ERROR:|FAILED:|Failed to load script' -or ($Expected -and $output -notmatch $Expected)) {
        throw "UI verification failed: $($GodotArguments -join ' ')"
    }
    if ($output -match '(?<suite>[A-Z_]+) checks=(?<checks>\d+) failures=(?<failures>\d+)') {
        $results.Add([ordered]@{suite=$Matches.suite; checks=[int]$Matches.checks; failures=[int]$Matches.failures})
    }
}
try {
    Invoke-UICheck -GodotArguments @('--headless','--editor','--path',$projectRoot,'--import','--quit')
    foreach ($test in @('ValidateNativeUI','ValidateUILayout','ValidateArtUI')) {
        Invoke-UICheck -GodotArguments @('--headless','--path',$projectRoot,'--script',"res://ui_module/prototype/Tests/$test.gd") -Expected 'failures=0'
    }
    Invoke-UICheck -GodotArguments @('--headless','--path',$projectRoot,'--script','res://ui_module/tests/integration_tests.gd') -Expected 'UI_MODULE_INTEGRATION checks=\d+ failures=0'
    if ($Render) {
        Invoke-UICheck -GodotArguments @('--path',$projectRoot,'--script','res://ui_module/tests/integration_tests.gd','--','--capture') -Expected 'UI_MODULE_INTEGRATION checks=\d+ failures=0'
    }
    $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'ui_module/tests/suite_test_results.json') -Encoding utf8
} finally {
    $env:APPDATA = $previousAppData
}
