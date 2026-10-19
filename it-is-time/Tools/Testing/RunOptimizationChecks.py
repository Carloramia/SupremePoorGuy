"""Run the focused cleanup regressions; Godot script errors can exit with code 0."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORKSPACE = ROOT.parents[1]
DEFAULT_GODOT = WORKSPACE / "Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
CHECKS = {
    "Tests/ValidateDemandDiagnostics3D.gd": "DEMAND_DIAGNOSTICS_PASSED",
    "Tests/ValidateTerrainProbe3D.gd": "TERRAIN_PROBE_PASSED",
    "Tests/ValidateStanceLegTorqueRelease3D.gd": "STANCE_LEG_TORQUE_RELEASE_VALIDATION_PASSED",
    "Tests/ValidateZeroGravitySegments3D.gd": "ZERO_GRAVITY_SEGMENTS_PASSED",
    "Tests/ValidatePerformanceOptimization.gd": "PASS: Performance mode switching",
    "Tests/ValidateControlledPartMotionTracking.gd": "CONTROLLED_PART_MOTION_TRACKING_VALIDATION_PASSED",
    "Tests/Integration/ValidateGameSession.gd": "APPLICATION_SESSION_PASSED",
    "Tests/Integration/ValidateGameRoot.gd": "APPLICATION_ROOT_PASSED",
    "Tests/Integration/ValidateQuests.gd": "QUEST_FRAMEWORK_PASSED",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=DEFAULT_GODOT)
    parser.add_argument("--output", type=Path, default=WORKSPACE / "Reports/ProjectOptimization_2026-10-18/Checks")
    parser.add_argument("--only", action="append", choices=list(CHECKS))
    args = parser.parse_args()
    if not args.godot.is_file():
        parser.error("Godot executable not found; supply --godot")
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    for script in args.only or CHECKS:
        log = (args.output / (Path(script).stem + ".log")).resolve()
        command = [str(args.godot), "--headless", "--fixed-fps", "60", "--path", str(ROOT), "--log-file", str(log), "--script", "res://" + script, "--quit-after", "2400"]
        try:
            process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
            output = process.stdout + process.stderr
            ok = process.returncode == 0 and CHECKS[script] in output and not re.search(r"(?m)^\s*(?:SCRIPT ERROR|ERROR):", output)
            result = {"script": script, "passed": ok, "returncode": process.returncode, "log": str(log)}
            log.with_suffix(".output.txt").write_text(output, encoding="utf-8")
        except subprocess.TimeoutExpired:
            result = {"script": script, "passed": False, "error": "timeout", "log": str(log)}
        results.append(result)
        print(("PASS " if result["passed"] else "FAIL ") + script, flush=True)
    (args.output / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if all(row["passed"] for row in results) else 1


if __name__ == "__main__":
    sys.exit(main())
