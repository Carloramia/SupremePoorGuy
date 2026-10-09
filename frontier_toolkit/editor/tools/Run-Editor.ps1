param([int]$Port = 8765, [string]$NodePath = '')
$ErrorActionPreference = 'Stop'
if (-not $NodePath) {
    $availableNode = Get-Command node -ErrorAction SilentlyContinue
    if ($availableNode) { $NodePath = $availableNode.Source }
    else { throw 'Node.js not found. Open editor/index.html directly, or pass -NodePath.' }
}
$serverScript = Join-Path $PSScriptRoot 'serve.cjs'
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
    Start-Process -FilePath $NodePath -ArgumentList @("`"$serverScript`"", "$Port") -WindowStyle Hidden
    Start-Sleep -Milliseconds 700
}
Start-Process "http://127.0.0.1:$Port/editor/index.html"
