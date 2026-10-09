param([string]$Name = ('frontier-toolkit-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
$ErrorActionPreference = 'Stop'
if ($Name -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Name must contain only letters, digits, underscores or hyphens.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$distRoot = Join-Path $projectRoot 'dist'
$destination = Join-Path $distRoot $Name
$archive = "$destination.zip"
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $archive)) { throw 'Destination already exists. Choose another -Name; existing packages are never overwritten.' }
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$entries = @('project.godot', 'README.md', 'BUILD.md', '.gitignore', '.gitattributes', 'LICENSE_NOTICE.md', 'CONTRIBUTING.md', 'CHANGELOG.md', '.github', 'tools', 'docs', 'world_map', 'scenario_2_5d', 'integration', 'editor')
foreach ($entry in $entries) {
    $source = Join-Path $projectRoot $entry
    if (-not (Test-Path -LiteralPath $source)) { throw "Required entry missing: $entry" }
    $files = if (Test-Path -LiteralPath $source -PathType Container) { Get-ChildItem -LiteralPath $source -Recurse -File -Force } else { Get-Item -LiteralPath $source -Force }
    foreach ($file in $files) {
        $relative = [IO.Path]::GetRelativePath($projectRoot, $file.FullName).Replace('\', '/')
        if ($relative -match '(^|/)(\.git|\.godot|\.tools|node_modules)(/|$)' -or $relative -match '\.(import|log|tmp)$' -or $file.Name -match '(_save|_test_results|test_results|-results)\.json$') { continue }
        $target = Join-Path $destination $relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
}
& node (Join-Path $destination 'tools/Verify-Package.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Package verification failed.' }
$manifest = Get-ChildItem -LiteralPath $destination -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
    [ordered]@{ path = [IO.Path]::GetRelativePath($destination, $_.FullName).Replace('\', '/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}
ConvertTo-Json -InputObject @($manifest) -Depth 3 | Set-Content -LiteralPath (Join-Path $destination 'PACKAGE_MANIFEST.json') -Encoding utf8
# ZipFile includes dotfiles such as .github, .gitignore and .gitattributes.
[IO.Compression.ZipFile]::CreateFromDirectory($destination, $archive, [IO.Compression.CompressionLevel]::Optimal, $true)
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$archiveHash  $Name.zip" | Set-Content -LiteralPath "$archive.sha256" -Encoding ascii
Write-Output "Repository: $destination"
Write-Output "Archive: $archive"
Write-Output "SHA256: $archiveHash"
