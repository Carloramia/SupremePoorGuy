function Resolve-ProjectGodot {
    param([string]$ProjectRoot, [string]$GodotPath = '')
    $candidates = @($GodotPath, $env:GODOT_BIN,
        (Join-Path $ProjectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'),
        (Join-Path $ProjectRoot '.tools/godot/Godot_v4.7.2-stable_win64.exe'))
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return (Resolve-Path -LiteralPath $candidate).Path }
        if ($candidate) { $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue; if ($command) { return $command.Source } }
        if ($candidate -eq $GodotPath -and $GodotPath) { throw "GodotPath does not exist: $GodotPath" }
    }
    foreach ($name in @('godot', 'godot4')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw 'Godot not found. Install Godot 4.7.2 and pass -GodotPath, set GODOT_BIN, or add godot to PATH. See docs/GETTING_STARTED.md.'
}
