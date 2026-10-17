"""Separate observed attack failures from preparation cancellation and censored actions."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re

LAUNCH = {"foreleg_stomp": {"STOMPING", "LANDING"}, "wolf_pounce": {"flying"}, "wolf_bite": {"lunging"},
          "snake_lunge_bite": {"lunging"}, "ground_charge": {"CHARGING"}, "spider_pounce": {"LEAPING"}}
CONTACT = re.compile(r'^\[(wolf_attack_hit|snake_bite_hit)\] weapon=(\S+) attached_part=(\S+) target=(\S+) estimated_impulse=(\S+) hp_damage=(\S+)')


def scalar(text, key):
    match = re.search(r'"' + re.escape(key) + r'": (?:&)?"([^"]*)"', text)
    return match[1] if match else None


def analyze(directory, case="diagnostic_161005"):
    baseline = defaultdict(Counter)
    for path in sorted(directory.glob("mixed_*.json")) + sorted(directory.glob("duel_*.json")):
        run = json.loads(path.read_text(encoding="utf-8"))
        for attack in run["attacks"]:
            action = attack["action"].replace("snake_bite", "snake_lunge_bite")
            phase_set = {p["phase"] for p in attack["phases"]}
            row = baseline[(attack["species"], action)]
            row["started"] += 1
            if attack["reason"] == "observation_ended":
                row["pending_hit" if attack["damage"] > 0 else "pending_no_damage"] += 1
            elif attack["damage"] > 0:
                row["ended_hit"] += 1
            else:
                category = "ended_launched_no_damage" if phase_set & LAUNCH[action] else "ended_before_launch"
                row[category] += 1
                row[category + ":" + attack["reason"]] += 1
            row["effective_hit"] += attack["damage"] > 0

    run = json.loads((directory / (case + ".json")).read_text(encoding="utf-8"))
    assert not run["errors"]
    actors = {row["id"]: row for row in run["roster"]}
    attacks = run["attacks"]
    details = {a["id"]: dict(a, samples=[], contacts=[], native_end=None, launch_rejection=None, recovery_reason=None) for a in attacks}
    unmapped = []

    def find_action(actor, action, time):
        candidates = [a for a in attacks if a["actor"] == actor and a["action"] == action and a["start"] - 0.034 <= time <= a["end"] + 0.034]
        return max(candidates, key=lambda a: a["start"]) if candidates else None

    clock, previous_impact = 0.0, None
    for line in (directory / (case + ".log")).read_text(encoding="utf-8").splitlines():
        if line.startswith("MELEE_RESULT"): break
        if line.startswith("MELEE_DIAG_TIME "):
            clock = float(line.split()[-1])
        elif line.startswith("MELEE_DIAG_SAMPLE "):
            sample = json.loads(line[len("MELEE_DIAG_SAMPLE "):])
            if sample["attack_id"] >= 0: details[sample["attack_id"]]["samples"].append(sample)
        elif line.startswith("[part_impact]"):
            previous_impact = dict(re.findall(r'(\w+)=([^\s]+)', line))
        elif match := CONTACT.match(line):
            label, weapon, part, target, impulse, damage = match.groups()
            victim = target.split("/MeleeArena/")[1].split("/")[0]
            species, action = ("snake", "snake_lunge_bite") if label == "snake_bite_hit" else (("spider", "spider_pounce") if weapon.startswith("SpiderForelegDamage") else ("wolf", "wolf_bite"))
            source = next(a["id"] for a in actors.values() if a["species"] == species and a["team"] != actors[victim]["team"])
            event = {"time": clock, "source": source, "target": victim, "part": target.split("/")[-1], "impulse": float(impulse), "damage": float(damage)}
            if previous_impact and previous_impact.get("weapon") == weapon and previous_impact.get("target") == event["part"]:
                for key in ["raw_damage", "armor"]: event[key] = float(previous_impact[key])
                event["registered"] = previous_impact["registered"] == "true"
            previous_impact = None
            attack = find_action(source, action, clock)
            if attack is None: unmapped.append(event)
            else: details[attack["id"]]["contacts"].append(event)
        elif line.startswith("[wolf_attack]") and " module=" in line and '"active": false' in line:
            header = dict(re.findall(r'(character|module|event)=([^\s]+)', line))
            actor = header["character"].split("/")[-1]
            action = "wolf_bite" if header["module"] == "Bite" else "wolf_pounce"
            attack = find_action(actor, action, clock)
            if attack is not None: details[attack["id"]]["native_end"] = header["event"]
        elif line.startswith("[spider_attack]") and "reason=launch_target_unreachable" in line:
            actor = re.search(r'character=(\S+)', line)[1].split("/")[-1]
            attack = find_action(actor, "spider_pounce", clock)
            if attack is not None: details[attack["id"]]["launch_rejection"] = scalar(line.split(" plan=", 1)[-1], "reason")
        elif line.startswith("[snake_attack]") and "event=phase_changed" in line and scalar(line, "phase") == "recovering":
            actor = re.search(r'character=(\S+)', line)[1].split("/")[-1]
            attack = find_action(actor, "snake_lunge_bite", clock)
            if attack is not None: details[attack["id"]]["recovery_reason"] = scalar(line, "reason")

    assert not unmapped, unmapped
    counts = defaultdict(Counter)
    for a in details.values():
        key = (a["species"], a["action"])
        row = counts[key]
        row["started"] += 1
        phase_set = {p["phase"] for p in a["phases"]}
        a["sampled_close_reasons"] = dict(Counter(s["close_reason"] for s in a["samples"] if s.get("close_reason")))
        a["sampled_max_jaw_error"] = max((abs(s.get("angle_error_degrees", 0)) for s in a["samples"]), default=0)
        if a["damage"] > 0: category = "effective_hit"
        elif a["reason"] == "observation_ended": category = "pending"
        elif not phase_set & LAUNCH[a["action"]]: category = "before_launch"
        elif a["action"] in ["wolf_bite", "snake_lunge_bite", "spider_pounce"]:
            if not a["contacts"]: category = "no_enemy_query_contact"
            elif all(c["impulse"] <= 1 for c in a["contacts"]): category = "low_impulse_only"
            elif any(c.get("raw_damage", 0) > 0 and c.get("raw_damage", 0) <= c.get("armor", -1) for c in a["contacts"]): category = "armor_blocked_contact"
            else: category = "contact_without_hp_unresolved"
        else: category = "launched_no_damage"
        a["diagnosis"] = category
        row[category] += 1
        if a["recovery_reason"]: row["recovery:" + a["recovery_reason"]] += 1
        if a["launch_rejection"]: row["launch_rejection:" + a["launch_rejection"]] += 1
        if a["native_end"]: row["native_end:" + a["native_end"]] += 1
    for a in details.values():
        # Actual positive settlement log rows must agree with the damage signals.
        if a["action"] in ["wolf_bite", "snake_lunge_bite", "spider_pounce"]:
            positive = [c for c in a["contacts"] if c["damage"] > 0]
            assert len(positive) == a["damage_events"], (a["id"], len(positive), a["damage_events"])
    result = {"baseline": [{"species": key[0], "action": key[1], **dict(row)} for key, row in baseline.items()],
              "diagnostic": [{"species": key[0], "action": key[1], **dict(row)} for key, row in counts.items()],
              "details": list(details.values()), "effects": run["effects"], "unmapped_contacts": unmapped}
    filename = "attack_failure_diagnosis.json" if case == "diagnostic_161005" else case + "_failure_diagnosis.json"
    (directory / filename).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ["details", "effects"]}, ensure_ascii=False, indent=2))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--case", default="diagnostic_161005")
    args = parser.parse_args()
    analyze(args.directory, args.case)
