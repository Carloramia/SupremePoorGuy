param([string]$GodotPath = '', [switch]$Tests, [switch]$Capture, [switch]$NativePreview)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$hostRoot = Split-Path $projectRoot -Parent
$candidates = @($GodotPath, $env:GODOT_BIN, (Join-Path $hostRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'))
$engine = $null
foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $engine = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}
if (-not $engine) {
    foreach ($name in @('godot', 'godot4')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue
        if ($command) { $engine = $command.Source; break }
    }
}
if (-not $engine) { throw 'Godot 4.7.2 not found. Pass -GodotPath or set GODOT_BIN.' }
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $projectRoot 'Tests/.runtime/userdata'
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'Tests/.runtime'), (Join-Path $projectRoot 'Tests/TA/screenshots') -Force | Out-Null
$results = [System.Collections.Generic.List[object]]::new()
function Invoke-Check([string[]]$Arguments, [string]$Expected = '') {
    $output = & $engine @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    Write-Output $output
    $checked = $output -replace 'ERROR: Failed to read the root certificate store\.', ''
    if ($exitCode -ne 0 -or $checked -match 'SCRIPT ERROR:|SHADER ERROR:|ERROR:|Parse Error' -or ($Expected -and $output -notmatch $Expected)) {
        throw "Verification failed: $($Arguments -join ' ')"
    }
    if ($output -match '(?<suite>[A-Z0-9_]+) checks=(?<checks>\d+) failures=(?<failures>\d+)') {
        $results.Add([ordered]@{suite=$Matches.suite; checks=[int]$Matches.checks; failures=[int]$Matches.failures})
    }
}
try {
    Invoke-Check -Arguments @('--headless','--editor','--path',$projectRoot,'--import','--quit')
    if ($Tests) {
        # The original isolation scan also checks the TA test's output URI.
        # Generate the real output before scanning a clean checkout; never ship .runtime.
        Invoke-Check -Arguments @('--headless','--path',$projectRoot,'--script','res://Tests/ValidateTAShaders.gd') -Expected 'TA_SHADER_VALIDATION checks=\d+ failures=0'
        Copy-Item -LiteralPath (Join-Path $projectRoot 'Tests/.runtime/ta_shader_results.json') -Destination (Join-Path $projectRoot 'Tests/TA/validation_headless.json')
        & (Join-Path $projectRoot 'Tests/ValidateIsolation.ps1')
        foreach ($suite in @('ValidateSummonV2','ValidateRitualPresentation','ValidateComponentContracts','ValidateEventPanel','ValidateEventLifecycle','ValidateTasks','ValidateFilterTabs','ValidateScrollPresentation','ValidateNestedModal','ValidateLocationHint')) {
            Invoke-Check -Arguments @('--headless','--path',$projectRoot,'--script',"res://Tests/$suite.gd") -Expected 'checks=\d+ failures=0'
        }
    }
    if ($Capture) {
        # A2Motion always waits for frame_post_draw, even without --capture.
        # It requires a real renderer; do not dispatch it to headless dummy.
        Invoke-Check -Arguments @('--path',$projectRoot,'--script','res://Tests/ValidateA2Motion.gd') -Expected 'A2_MOTION_VALIDATION checks=\d+ failures=0'
        Invoke-Check -Arguments @('--path',$projectRoot,'--script','res://Tests/ValidateTAShaders.gd','--','--capture') -Expected 'TA_SHADER_VALIDATION checks=\d+ failures=0'
        Copy-Item -LiteralPath (Join-Path $projectRoot 'Tests/.runtime/ta_shader_results.json') -Destination (Join-Path $projectRoot 'Tests/TA/validation_gpu.json')
    }
    if ($Tests -or $Capture) {
        $resultName = if ($Tests -and $Capture) { 'build_results.json' } elseif ($Tests) { 'headless_results.json' } else { 'capture_results.json' }
        $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot "Tests/.runtime/$resultName") -Encoding utf8
    } else {
        $scene = if ($NativePreview) { 'res://TA/Scenes/NativeSkinPreview.tscn' } else { 'res://TA/Scenes/ShaderComparison.tscn' }
        & $engine --path $projectRoot --resolution 1280x720 $scene
        if ($LASTEXITCODE -ne 0) { throw 'Preview failed.' }
    }
} finally {
    $env:APPDATA = $previousAppData
}
