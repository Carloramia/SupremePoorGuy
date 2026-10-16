param([string]$Name = ('supremepoor-toolkit-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
$ErrorActionPreference = 'Stop'
if ($Name -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Name must contain only letters, digits, underscores or hyphens.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$distRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'dist'))
$destination = [IO.Path]::GetFullPath((Join-Path $distRoot $Name))
$archive = "$destination.zip"
if (-not $destination.StartsWith($distRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Destination escaped dist directory.' }
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $archive)) { throw 'Destination exists. Choose a new -Name; existing releases are not overwritten.' }
& node (Join-Path $PSScriptRoot 'Stage-GitHub-Repository.cjs') $destination
if ($LASTEXITCODE -ne 0) { throw 'Repository staging failed.' }
& node (Join-Path $PSScriptRoot 'Verify-GitHub-Repository.cjs') $destination --manifest
if ($LASTEXITCODE -ne 0) { throw 'Repository verification failed.' }
[IO.Compression.ZipFile]::CreateFromDirectory($destination, $archive, [IO.Compression.CompressionLevel]::Optimal, $true)
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$archiveHash  $Name.zip" | Set-Content -LiteralPath "$archive.sha256" -Encoding ascii
Write-Output "Repository: $destination"
Write-Output "Archive: $archive"
Write-Output "SHA256: $archiveHash"
