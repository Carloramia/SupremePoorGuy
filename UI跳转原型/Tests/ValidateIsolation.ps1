$ErrorActionPreference = 'Stop'
$taskRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskConfig = Get-Content -LiteralPath (Join-Path $taskRoot 'project.godot') -Raw
if ($taskConfig -match '\[autoload\]|\[editor_plugins\]') {
    throw 'Prototype must not register autoloads or plugins.'
}
$taskFiles = Get-ChildItem -LiteralPath $taskRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.gd', '.tscn') -and $_.FullName -notmatch '\\.godot\\' }
$taskReferences = 0
foreach ($taskFile in $taskFiles) {
    $taskText = Get-Content -LiteralPath $taskFile.FullName -Raw
    $taskIsModel = $taskFile.Name -eq 'PrototypeState.gd'
    $taskIsTest = $taskFile.FullName.StartsWith((Join-Path $taskRoot 'Tests') + [System.IO.Path]::DirectorySeparatorChar)
    $taskIsVisual = $taskFile.FullName.StartsWith((Join-Path $taskRoot 'Scripts\UI') + [System.IO.Path]::DirectorySeparatorChar)
    if ($taskIsVisual -and $taskText -match 'PrototypeState|GameDemo|FileAccess|DirAccess|state\.data|state\.save|state\.summon|state\.recycle') {
        throw "Visual component must not depend on controller, model, or persistence: $($taskFile.Name)"
    }
    if ($taskFile.Extension -eq '.gd' -and $taskText -match 'HTTPRequest|OS\.execute|OS\.shell_open|change_scene_to|\.paused\s*=') {
        throw "Unexpected business IO/global mutation: $($taskFile.Name)"
    }
    if (-not $taskIsModel -and -not $taskIsTest -and $taskText -match 'FileAccess|DirAccess') {
        throw "File IO must live in PrototypeState or tests: $($taskFile.Name)"
    }
    if ($taskIsModel -and $taskText -match 'res://[^"\r\n]*\.json|user://(?!prototype_session|native_)') {
        throw 'Unexpected model storage target.'
    }
    foreach ($taskMatch in [regex]::Matches($taskText, 'res://[^"\s]+')) {
        $taskRelative = $taskMatch.Value.Substring(6)
        $taskResolved = [System.IO.Path]::GetFullPath((Join-Path $taskRoot $taskRelative))
        if (-not $taskResolved.StartsWith($taskRoot + [System.IO.Path]::DirectorySeparatorChar)) {
            throw "Reference escaped the prototype: $taskResolved"
        }
        if (-not (Test-Path -LiteralPath $taskResolved)) {
            throw "Missing resource: $taskResolved"
        }
        $taskReferences += 1
    }
}
Write-Output "UI_FLOW_ISOLATION_PASSED files=$($taskFiles.Count) references=$taskReferences"
Write-Output 'Static boundary check only; run ValidateNativeUI.gd in Godot for current runtime validation.'
