@echo off
set "SUMMON_GODOT=E:\codex\Godot_v4.7.2-stable_win64.exe"
if not exist "%SUMMON_GODOT%" (
  echo Godot 4.7.2 not found. Open project.godot and run Scenes/Tests/SummonAssemblyLab.tscn with F6.
  pause
  exit /b 1
)
"%SUMMON_GODOT%" --path "%~dp0." --resolution 1440x900 res://Scenes/Tests/SummonAssemblyLab.tscn
