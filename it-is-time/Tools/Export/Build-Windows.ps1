param(
    [string]$Godot = '',
    [string]$OutputRoot = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $projectRoot '../..')).Path
$toolRoot = Join-Path $workspaceRoot 'BuildTools/Godot-4.7.2'
if (-not $Godot) { $Godot = Join-Path $toolRoot 'editor/Godot_v4.7.2-stable_win64_console.exe' }
if (-not $OutputRoot) { $OutputRoot = Join-Path $workspaceRoot ('Builds/ItIsTime/' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')) }
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Godot executable not found: $Godot" }
$engineVersion = (& $Godot --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $engineVersion -notlike '4.7.2.stable.*' -or $engineVersion -like '*.mono.*') {
    throw "Use the standard Godot 4.7.2 editor, not the .NET editor. Found: $engineVersion"
}
foreach ($file in @('windows_release_x86_64.exe','icudt_godot.dat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $toolRoot "templates/$file"))) { throw "Missing matching export template: $file" }
}
if (Test-Path -LiteralPath $OutputRoot) { throw "Choose a new output directory to keep earlier builds: $OutputRoot" }
$output = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $output | Out-Null
$game = Join-Path $output 'Windows-x86_64'
$packs = Join-Path $output 'ResourcePack'
New-Item -ItemType Directory -Path $game,$packs | Out-Null
& $Godot --headless --path $projectRoot --export-release 'Windows Desktop' (Join-Path $game 'ItIsTime.exe') --log-file (Join-Path $output 'export.log')
if ($LASTEXITCODE -ne 0) { throw "Export failed. See $output/export.log" }
if (Select-String -LiteralPath (Join-Path $output 'export.log') -Pattern '^ERROR:|^SCRIPT ERROR:' -Quiet) {
    throw "Godot reported export errors despite its exit code. See $output/export.log"
}
foreach ($file in @('ItIsTime.exe','ItIsTime.pck')) {
    if (-not (Test-Path -LiteralPath (Join-Path $game $file))) { throw "Export did not produce $file" }
}
# ICU data is required by the Chinese UI even when using a custom Windows template.
Copy-Item -LiteralPath (Join-Path $toolRoot 'templates/icudt_godot.dat') -Destination $game
$smokeLog = Join-Path $output 'smoke.log'
$smoke = Start-Process -FilePath (Join-Path $game 'ItIsTime.exe') -WorkingDirectory $game -WindowStyle Hidden -PassThru -ArgumentList @(
    '--headless','--log-file',('"'+$smokeLog+'"'),'--','--verify-export'
)
if (-not $smoke.WaitForExit(60000)) {
    Stop-Process -Id $smoke.Id
    throw "Standalone verification timed out. See $smokeLog"
}
if ($smoke.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $smokeLog) -or
    -not (Select-String -LiteralPath $smokeLog -Pattern '^EXPORTED_PACKAGE_PASSED$' -Quiet) -or
    (Select-String -LiteralPath $smokeLog -Pattern '^ERROR:|^SCRIPT ERROR:' -Quiet)) {
    throw "Standalone verification failed. See $smokeLog"
}
Copy-Item -LiteralPath (Join-Path $game 'ItIsTime.pck') -Destination (Join-Path $packs 'ItIsTime.pck')
@'
ItIsTime Windows x86_64 test build

Run ItIsTime.exe directly from this folder. Keep ItIsTime.pck and all DLL/data files alongside it.
No Godot editor or .NET installation is required. Uses Forward+ / Direct3D 12.
Saves and logs: %APPDATA%/Godot/app_userdata/ItIsTime/
Console getlogs archives: %APPDATA%/Godot/app_userdata/ItIsTime/log_archives/
../ResourcePack/ItIsTime.pck contains the same complete project data as this executable's PCK.
The PCK is not a source-project backup or a standalone executable.
'@ | Set-Content -LiteralPath (Join-Path $game 'README.txt') -Encoding UTF8
$files = Get-ChildItem -LiteralPath $output -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' -and $_.Extension -ne '.log' }
$manifest = [ordered]@{ engine=$engineVersion; created=(Get-Date -Format o); files=@($files | ForEach-Object {
    @{path=$_.FullName.Substring($output.Length).TrimStart('/','\'); bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
}) }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding UTF8
Write-Output "BUILD_READY=$output"
