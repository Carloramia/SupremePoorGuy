param([string]$Name = ('frontier-editor-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
$ErrorActionPreference = 'Stop'
if ($Name -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid package name.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$destination = Join-Path $projectRoot "dist/$Name"
$archive = "$destination.zip"
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $archive)) { throw 'Destination exists. Choose a different -Name.' }
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$entries = @('editor/index.html', 'editor/app.js', 'editor/model.js', 'editor/renderer.js', 'editor/styles.css', 'editor/assets', 'editor/examples', 'editor/tools/serve.cjs', 'editor/tools/Run-Editor.ps1', 'editor/tools/Validate-Level.cjs')
foreach ($entry in $entries) {
    $source = Join-Path $projectRoot $entry
    $files = if (Test-Path -LiteralPath $source -PathType Container) { Get-ChildItem -LiteralPath $source -File -Recurse } else { Get-Item -LiteralPath $source }
    foreach ($file in $files) {
        if ($file.Extension -in @('.import', '.log', '.tmp')) { continue }
        $relative = [IO.Path]::GetRelativePath($projectRoot, $file.FullName)
        $target = Join-Path $destination $relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
}
$guide = Join-Path $projectRoot 'editor/docs/STANDALONE_GUIDE.md'
Copy-Item -LiteralPath $guide -Destination (Join-Path $destination 'README.md')
Copy-Item -LiteralPath $guide -Destination (Join-Path $destination 'editor/README.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'editor/docs/STANDALONE_START.html') -Destination (Join-Path $destination '使用说明.html')
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE_NOTICE.md') -Destination (Join-Path $destination 'LICENSE_NOTICE.md')
$launcher = "@echo off`r`nstart `"`" `"%~dp0editor\index.html`"`r`n"
[IO.File]::WriteAllText((Join-Path $destination '启动编辑器.cmd'), $launcher, [Text.Encoding]::ASCII)
$indexPath = Join-Path $destination 'editor/index.html'
$index = [IO.File]::ReadAllText($indexPath).Replace('href="README.md"', 'href="../使用说明.html"')
[IO.File]::WriteAllText($indexPath, $index, [Text.UTF8Encoding]::new($false))
& node (Join-Path $PSScriptRoot 'Verify-Standalone-Editor.cjs') $destination
if ($LASTEXITCODE -ne 0) { throw 'Standalone package validation failed.' }
$manifest = Get-ChildItem -LiteralPath $destination -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
    [ordered]@{ path = [IO.Path]::GetRelativePath($destination, $_.FullName).Replace('\', '/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}
ConvertTo-Json -InputObject @($manifest) -Depth 3 | Set-Content -LiteralPath (Join-Path $destination 'PACKAGE_MANIFEST.json') -Encoding utf8
[IO.Compression.ZipFile]::CreateFromDirectory($destination, $archive, [IO.Compression.CompressionLevel]::Optimal, $true)
"$((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant())  $Name.zip" | Set-Content -LiteralPath "$archive.sha256" -Encoding ascii
Write-Output "Standalone folder: $destination"
Write-Output "Archive: $archive"
