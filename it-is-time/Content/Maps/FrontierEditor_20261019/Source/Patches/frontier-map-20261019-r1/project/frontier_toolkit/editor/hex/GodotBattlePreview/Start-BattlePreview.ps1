[CmdletBinding()]
param(
    [string]$GodotPath = 'godot',
    [string]$PythonPath = 'python',
    [string]$Output = '',
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
if (-not $Output) { $Output = Join-Path $PSScriptRoot 'generated-preview' }
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PYTHONIOENCODING = 'utf-8'
$env:OPENBLAS_NUM_THREADS = '1'
& $PythonPath (Join-Path $PSScriptRoot 'prepare_battle_preview.py') --output $Output --portable
if ($LASTEXITCODE -ne 0) { throw 'Preview preparation failed; see the project README.' }
if (-not $PrepareOnly) {
    Start-Process -FilePath $GodotPath -WindowStyle Hidden -ArgumentList @('--path', ('"' + $Output + '"'))
}
