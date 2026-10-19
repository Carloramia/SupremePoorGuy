param([string]$OutputPath = '')
$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot $manifest.zip_name }
if (Test-Path -LiteralPath $OutputPath) { throw "Output already exists: $OutputPath" }
foreach ($part in $manifest.parts) {
    if ([IO.Path]::GetFileName($part.name) -ne $part.name) { throw 'Invalid part name' }
    $partPath = Join-Path $PSScriptRoot $part.name
    if ((Get-Item -LiteralPath $partPath).Length -ne $part.bytes) { throw "Size mismatch: $($part.name)" }
    if ((Get-FileHash -LiteralPath $partPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $part.sha256) { throw "Checksum mismatch: $($part.name)" }
}
$output = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
try {
    foreach ($part in $manifest.parts) {
        $inputStream = [IO.File]::OpenRead((Join-Path $PSScriptRoot $part.name))
        try { $inputStream.CopyTo($output) } finally { $inputStream.Dispose() }
    }
} finally { $output.Dispose() }
if ((Get-Item -LiteralPath $OutputPath).Length -ne $manifest.zip_bytes) { throw 'Combined ZIP size mismatch' }
if ((Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.zip_sha256) { throw 'Combined ZIP checksum mismatch' }
Write-Output "Verified package: $OutputPath"
