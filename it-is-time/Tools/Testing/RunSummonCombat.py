"""Balanced real-engine duels and paired armor-off controls; no scene edits."""
import argparse
import concurrent.futures
import hashlib
import itertools
import json
import os
from pathlib import Path
import subprocess
import time

SPECIES = ["stump_beast", "wolf", "snake", "horned_beast", "spider"]
PROJECT = Path(__file__).resolve().parents[2]


def plan_runs():
    runs = []
    for index, (a, b) in enumerate(itertools.combinations_with_replacement(SPECIES, 2)):
        for repeat in range(4):
            pair = [a, b] if repeat % 2 == 0 else [b, a]
            for armor in (["on", "off"] if repeat < 2 else ["on"]):
                runs.append(dict(name=f"{a}__{b}_{repeat}_{armor}", pair=",".join(pair),
                                 seed=181100+index*10+repeat, repeat=repeat, armor=armor,
                                 seconds=120, gap=60))
    assert len(runs) == 90 and len({r["name"] for r in runs}) == 90
    return runs


def execute(run, godot, root):
    folder = root / "raw" / run["name"]
    folder.mkdir(parents=True, exist_ok=True)
    output = folder / "result.json"
    assert not output.exists(), f"Preserve recorded observations: {output}"
    env = os.environ.copy()
    for key, sub in [("APPDATA", "AppData"), ("LOCALAPPDATA", "LocalAppData")]:
        path = folder / sub
        path.mkdir(exist_ok=True)
        env[key] = str(path)
    command = [str(godot), "--headless", "--fixed-fps", "60", "--path", str(PROJECT),
               "--log-file", str(folder / "engine.log"), "--script",
               "res://Tests/Integration/MeasureSummonCombat.gd", "--", f"--out={output}"]
    command += [f"--{key}={run[key]}" for key in ("pair", "seed", "seconds", "gap", "armor")]
    started = time.monotonic()
    with (folder / "stdout.log").open("wb") as log:
        result = subprocess.run(command, env=env, cwd=PROJECT, stdout=log,
                                stderr=subprocess.STDOUT, timeout=600)
    text = (folder / "stdout.log").read_text(encoding="utf-8", errors="replace")
    assert result.returncode == 0, (result.returncode, text[-2000:])
    assert "MELEE_RESULT path=" in text and output.exists(), "Missing completion marker"
    assert "SCRIPT ERROR:" not in text and "ERROR:" not in text, text[-2000:]
    data = json.loads(output.read_text(encoding="utf-8"))
    assert not data["errors"], data["errors"]
    assert data["options"]["audited_damage_events"] == len(data["damage_events"])
    assert data["options"]["end_reason"] == "first_death" or data["simulated_seconds"] >= run["seconds"]
    assert sorted(a["species"] for a in data["roster"]) == sorted(run["pair"].split(","))
    assert all("final_parts" in a for a in data["roster"]), "Missing final HP ledger"
    assert all(not e["friendly"] and 0 <= e["attack_id"] < len(data["attacks"]) for e in data["damage_events"])
    return dict(**run, status="passed", wall_seconds=round(time.monotonic()-started, 3),
                simulated_seconds=data["simulated_seconds"], end_reason=data["options"]["end_reason"],
                attacks=len(data["attacks"]), damage_events=len(data["damage_events"]),
                result=str(output.relative_to(root)), sha256=hashlib.sha256(output.read_bytes()).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    root = args.out.resolve()
    root.mkdir(parents=True, exist_ok=True)
    assert not (root / "plan.json").exists(), "Choose a fresh folder to preserve previous observations."
    runs = plan_runs()
    (root / "plan.json").write_text(json.dumps(runs, indent=2), encoding="utf-8")
    # Content identity includes uncommitted local code/resources, which are the actual tested build.
    hashes = {}
    for base in ("Scripts", "Scenes", "Resources", "Tests/Integration"):
        for path in sorted((PROJECT / base).rglob("*")):
            if path.suffix in {".gd", ".tscn", ".tres"}:
                hashes[path.relative_to(PROJECT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    hashes["project.godot"] = hashlib.sha256((PROJECT / "project.godot").read_bytes()).hexdigest()
    (root / "source_hashes.json").write_text(json.dumps(hashes, indent=2), encoding="utf-8")
    completed = []
    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = {pool.submit(execute, run, args.godot, root): run for run in runs}
        for future in concurrent.futures.as_completed(futures):
            run = futures[future]
            try:
                result = future.result()
            except Exception as exc:
                result = dict(**run, status="failed", error=str(exc))
            completed.append(result)
            manifest = dict(workers=2, wall_seconds=round(time.monotonic()-started, 3),
                            completed=len(completed), planned=len(runs),
                            runs=sorted(completed, key=lambda r: r["name"]))
            (root / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            print(f"COMBAT_PROGRESS {len(completed)}/{len(runs)} {run['name']} {result['status']} "
                  f"attacks={result.get('attacks')} damage_events={result.get('damage_events')} "
                  f"sim_s={result.get('simulated_seconds')} wall_s={manifest['wall_seconds']}", flush=True)
    assert all(r["status"] == "passed" for r in completed), "Inspect failed trials in manifest.json"
    print(f"COMBAT_COMPLETE runs={len(completed)} wall_s={time.monotonic()-started:.3f}", flush=True)


if __name__ == "__main__":
    main()
