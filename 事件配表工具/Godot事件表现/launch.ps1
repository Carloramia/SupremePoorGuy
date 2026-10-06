param([string]$GodotPath = "", [switch]$Editor)
$ErrorActionPreference = 'Stop'
if (-not $GodotPath) { $GodotPath = $env:GODOT_EXECUTABLE }
if (-not $GodotPath) {
    $taskEngine = Get-Command godot -ErrorAction SilentlyContinue
    if ($taskEngine) { $GodotPath = $taskEngine.Source }
}
if (-not $GodotPath -and (Test-Path -LiteralPath 'E:\codex\Godot_v4.6.2-stable_win64.exe')) {
    $GodotPath = 'E:\codex\Godot_v4.6.2-stable_win64.exe'
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    Write-Host 'Godot not found. Import project.godot in Godot 4, or set GODOT_EXECUTABLE.'
    Read-Host 'Press Enter to exit'
    exit 1
}
$taskArgs = @('--path', ('"' + $PSScriptRoot + '"'))
if ($Editor) { $taskArgs += '--editor' }
Start-Process -FilePath $GodotPath -ArgumentList $taskArgs -WorkingDirectory $PSScriptRoot -WindowStyle Normal
