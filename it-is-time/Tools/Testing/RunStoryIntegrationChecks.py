"""Run isolated story and neighbouring-system regressions; reject errors even after PASS."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
CHECKS = {
    "ValidateStoryDialogueLog": "STORY_LOG_CHECKS=",
    "ValidateStoryTextLayout": "STORY_TEXT_CHECKS=",
    "ValidateDemoMagic": "DEMO_MAGIC_CHECKS=",
    "ValidateStoryEvents": "STORY_CHECKS=",
    "ValidateStoryEventPaths": "STORY_PATH_CHECKS=",
    "ValidateStoryEventBoundaries": "STORY_BOUNDARY_CHECKS=",
    "ValidateOpeningAppointment": "OPENING_APPOINTMENT_PASSED",
    "ValidateGameSession": "APPLICATION_SESSION_PASSED",
    "ValidateGameRoot": "APPLICATION_ROOT_PASSED",
    "ValidateApplicationRecovery": "APPLICATION_RECOVERY_PASSED",
    "ValidateApplicationInput": "APPLICATION_INPUT_PASSED",
    "ValidateDeliveryApplication": "DELIVERY_APPLICATION_PASSED",
    "ValidateGlobalSettings": "GLOBAL_SETTINGS_PASSED",
    "ValidateBattleDeployment": "BATTLE_DEPLOYMENT_PASSED",
    "ValidateBattleControlsAndDisplay": "BATTLE_CONTROLS_DISPLAY_PASSED",
    "ValidateHexWorldApplication": "HEX_WORLD_APPLICATION_PASSED",
    "ValidateHexWorldIntegration": "HEX_WORLD_INTEGRATION_PASSED",
    "ValidateHexLegacySelection": "HEX_LEGACY_SELECTION_PASSED",
    "ValidateHexStoneActions": "HEX_STONE_ACTIONS_PASSED",
    "ValidateHexBattleDeployment": "HEX_BATTLE_DEPLOYMENT PASSED",
    "ValidateCurrentSummoning": "CURRENT_SUMMON_CHECKS=",
    "ValidateSummonCombatEffects": "SUMMON_COMBAT_CHECKS=",
    "ValidateSummonContentLab": "SUMMON_LAB_CHECKS=",
    "ValidateNewPlayerTasks": "NEW_PLAYER_TASKS checks=",
    "ValidateNewPlayerTaskSession": "NEW_PLAYER_TASK_SESSION checks=",
    "ValidateNewPlayerTaskUI": "NEW_PLAYER_TASK_UI checks=",
    "ValidateWorldTime": "WORLD_TIME_PASSED",
    "ValidateMapLogging": "MAP_LOGGING_PASSED",
    "ValidateLocalization": "LOCALIZATION_INTEGRATION_PASSED",
    "ValidateQuests": "QUEST_FRAMEWORK_PASSED",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=Path("E:/codex/Godot_v4.7.2-stable_win64_console.exe"))
    parser.add_argument("--only", nargs="+", choices=CHECKS)
    parser.add_argument("--timeout", type=int, default=90)
    parser.add_argument("--output", type=Path, default=ROOT / "Tests/.runtime/story-regression" / time.strftime("%Y%m%d_%H%M%S"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    rows = []
    for name in args.only or CHECKS:
        started = time.monotonic()
        log = (args.output / (name + ".log")).resolve()
        command = [str(args.godot), "--headless", "--path", str(ROOT), "--log-file", str(log), "--script", f"res://Tests/Integration/{name}.gd", "--quit-after", "7200"]
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8", errors="replace", timeout=args.timeout)
            output = result.stdout + result.stderr
            errors = re.findall(r"(?m)^\s*(?:SCRIPT ERROR|ERROR):.*$", output)
            counters_failed = bool(re.search(r"(?i)(?:failures|errors)\s*=\s*[1-9]", output))
            ok = result.returncode == 0 and CHECKS[name] in output and not errors and not counters_failed
            row = {"test": name, "passed": ok, "exit_code": result.returncode, "errors": errors, "seconds": round(time.monotonic()-started, 2)}
        except subprocess.TimeoutExpired as exc:
            output = "\n".join(value.decode("utf-8", "replace") if isinstance(value, bytes) else value or "" for value in [exc.stdout, exc.stderr])
            row = {"test": name, "passed": False, "errors": ["timeout"], "seconds": args.timeout}
        (args.output / (name + ".output.txt")).write_text(output, encoding="utf-8")
        rows.append(row)
        (args.output / "results.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
        print(("PASS " if row["passed"] else "FAIL ") + name + " " + str(row["seconds"]) + "s", flush=True)
        for error in row["errors"][:4]: print(error.strip(), flush=True)
    print("RESULTS " + str(args.output.resolve()), flush=True)
    return 0 if all(row["passed"] for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
