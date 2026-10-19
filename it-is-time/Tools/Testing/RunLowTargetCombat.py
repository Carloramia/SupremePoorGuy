"""Run production attacks against live Rat targets without locomotion/attack intent."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

PROJECT = Path(__file__).resolve().parents[2]
ATTACKERS = ["stump_beast", "wolf", "snake", "horned_beast", "spider", "rat_1", "rat_2", "bird",
             "human_spear1", "human_spear5", "human_sword", "human_claw", "human_flail", "human_shield", "human_bow"]


def execute(run, godot, output):
    folder = output / "raw" / run["name"]
    folder.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    for variable in ("APPDATA", "LOCALAPPDATA"):
        path = folder / variable
        path.mkdir()
        env[variable] = str(path)
    result_path = folder / "result.json"
    command = [str(godot), "--headless", "--fixed-fps", "60", "--path", str(PROJECT),
               "--log-file", str(folder / "engine.log"), "--script", "res://Tests/Integration/MeasureLiveLowTargetCombat.gd",
               "--quit-after", "3600", "--", f"--out={result_path}", f"--pair={run['attacker']},{run['target']}",
               f"--side={run['side']}", f"--seed={run['seed']}"]

    command.append(f"--gap={run['gap']}")
    started = time.monotonic()
    with (folder / "stdout.log").open("wb") as log:
        completed = subprocess.run(command, cwd=PROJECT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240)
    text = (folder / "stdout.log").read_text(encoding="utf-8", errors="replace")
    assert completed.returncode == 0 and result_path.exists() and "MELEE_RESULT path=" in text, text[-2500:]
    data = json.loads(result_path.read_text(encoding="utf-8"))
    assert not data["errors"], data["errors"]
    assert "SCRIPT ERROR:" not in text, text[-2500:]
    assert data["options"]["balance_revision"] == 2
    assert data["options"]["fixture"] == "passive_live_rat_normal_support_physics_and_contact_callbacks"
    assert all((row["attack_id"] >= 0 or row.get("passive")) and not row["friendly"] for row in data["damage_events"])
    return {**run, "status": "passed", "wall_seconds": time.monotonic()-started,
            "simulated_seconds": data["simulated_seconds"], "attacks": len(data["attacks"]),
            "damage_events": len(data["damage_events"]), "result": str(result_path.relative_to(output)),
            "shutdown_resource_warning": "resources still in use at exit" in text,
            "sha256": hashlib.sha256(result_path.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--attackers", default=",".join(ATTACKERS))
    parser.add_argument("--targets", default="rat_1,rat_2")
    parser.add_argument("--repeats", type=int, default=2)
    parser.add_argument("--gap", type=float, default=35.0)
    args = parser.parse_args()
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=True)
    assert not (output / "plan.json").exists(), "Use a fresh output folder."
    attackers, targets = args.attackers.split(","), args.targets.split(",")
    assert set(attackers) <= set(ATTACKERS) and set(targets) <= {"rat_1", "rat_2"}
    runs = [{"name": f"{a}__{t}_{i}", "attacker": a, "target": t, "side": "left" if i % 2 == 0 else "right",
             "seed": 181800+index*10+i, "repeat": i, "gap": args.gap}
            for index, (a, t) in enumerate((a, t) for a in attackers for t in targets)
            for i in range(args.repeats)]
    (output / "plan.json").write_text(json.dumps(runs, indent=2), encoding="utf-8")
    hashes = {}
    for base in ("Scripts", "Scenes", "Resources", "Tests/Integration"):
        for path in (PROJECT / base).rglob("*"):
            if path.suffix in {".gd", ".tscn", ".tres"}:
                hashes[path.relative_to(PROJECT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    (output / "source_hashes.json").write_text(json.dumps(hashes, indent=2), encoding="utf-8")
    started, observations = time.monotonic(), []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = {pool.submit(execute, r, args.godot, output): r for r in runs}
        for future in concurrent.futures.as_completed(futures):
            run = futures[future]
            try:
                observation = future.result()
            except Exception as exc:
                observation = {**run, "status": "failed", "error": str(exc)}
            observations.append(observation)
            manifest = {"scope": "live Rat without move/attack intent; production support, AI, attacks and physics",
                        "workers": 2, "completed": len(observations), "planned": len(runs),
                        "wall_seconds": time.monotonic()-started,
                        "runs": sorted(observations, key=lambda r: r["name"])}
            (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            print(f"LOW_TARGET {len(observations)}/{len(runs)} {run['name']} {observation['status']} "
                  f"attacks={observation.get('attacks')} hits={observation.get('damage_events')}", flush=True)
    changed = [name for name, digest in hashes.items() if hashlib.sha256((PROJECT / name).read_bytes()).hexdigest() != digest]
    (output / "changed_sources.json").write_text(json.dumps(changed, indent=2), encoding="utf-8")
    assert not changed, "Sources changed during the test batch."
    print(f"LOW_TARGET_COMPLETE {len(observations)} runs, {sum(o['status']=='failed' for o in observations)} failed", flush=True)


if __name__ == "__main__":
    main()
