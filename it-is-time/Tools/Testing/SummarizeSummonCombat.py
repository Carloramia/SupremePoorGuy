"""Validate real-engine damage ledgers and summarize the summon-pool experiment."""
import argparse
import collections
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics
import shutil

from RunSummonCombat import PROJECT, SPECIES

NAMES = dict(zip(SPECIES, ["树桩兽", "Wolf", "Snake", "角兽", "Spider"]))
ACTIONS = {"foreleg_stomp": "踏地", "wolf_pounce": "飞扑（位移）", "wolf_bite": "啃咬",
           "snake_lunge_bite": "突刺啃咬", "ground_charge": "冲锋", "spider_pounce": "跳跃攻击"}
LAUNCH = {"foreleg_stomp": {"STOMPING", "LANDING"}, "wolf_pounce": {"flying"},
          "wolf_bite": {"lunging", "closing"}, "snake_lunge_bite": {"lunging", "closing"},
          "ground_charge": {"CHARGING"}, "spider_pounce": {"LEAPING"}}


def ratio(numerator, denominator):
    return numerator / denominator if denominator else None


def average(values):
    return statistics.mean(values) if values else None


def near(a, b):
    assert math.isclose(a, b, rel_tol=1e-6, abs_tol=1e-3), (a, b)


def damage_totals(events):
    fields = ["amount", "raw", "after_armor", "without_armor", "armor_absorbed",
              "passive_suppression", "overkill", "effective_armor_hp_saved"]
    return {key: sum(e[key] for e in events) for key in fields}


def combat_stats(attacks, outcomes, events):
    damaging = [a for a in attacks if a["action"] != "wolf_pounce"]
    hits = [a for a in damaging if a["damage"] > 0]
    kills = [o for o in outcomes if o["enemy_killed_by_damage"]]
    completed = [a for a in damaging if a["reason"] != "observation_ended"]
    hit_counts = [o["hits_dealt"] for o in kills]
    totals = damage_totals(events)
    return dict(actor_exposures=len(outcomes), duels=len({o["trial"] for o in outcomes}),
                attempts=len(damaging), hits=len(hits), hit_rate=ratio(len(hits), len(damaging)),
                finished_attempts=len(completed), finished_hits=sum(a["damage"] > 0 for a in completed),
                launched=sum(a["launched"] for a in damaging),
                mean_damage_per_attempt=ratio(totals["amount"], len(damaging)),
                mean_damage_per_hit=ratio(totals["amount"], len(hits)),
                part_damage_events=len(events), kills=len(kills),
                mean_hits_to_kill=average(hit_counts), min_hits_to_kill=min(hit_counts, default=None),
                max_hits_to_kill=max(hit_counts, default=None),
                max_hits_without_kill=max((o["hits_dealt"] for o in outcomes if not o["enemy_killed_by_damage"]), default=None),
                mean_seconds_to_kill=average([o["enemy_death_time"] for o in kills]),
                survivors_without_kill=sum(not o["enemy_killed_by_damage"] and o["alive"] for o in outcomes),
                losses=sum(not o["alive"] for o in outcomes),
                open_at_time_limit=sum(a["censoring"] == "time_limit_open" for a in damaging),
                pending_at_death=sum(a["censoring"] in {"owner_defeated", "target_defeated"} for a in damaging),
                pounces=sum(a["action"] == "wolf_pounce" for a in attacks), **totals)


def read_trials(root, partial=False, allow_failed=False):
    manifest_path = root / "analysis_manifest.json"
    if not manifest_path.exists(): manifest_path = root / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not partial:
        assert manifest["completed"] == manifest["planned"] == 90
        assert allow_failed or all(r["status"] == "passed" for r in manifest["runs"])
        coverage = collections.Counter((r["armor"], tuple(sorted(r["pair"].split(",")))) for r in manifest["runs"])
        assert len(coverage) == 30
        assert all(count == (4 if armor == "on" else 2) for (armor, _), count in coverage.items())
    trials, attacks, events, outcomes, effects, snapshots = [], [], [], [], [], []
    for run in manifest["runs"]:
        if run["status"] != "passed": continue
        path = root / run["result"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == run["sha256"]
        trial = json.loads(path.read_text(encoding="utf-8"))
        assert not trial["errors"]
        assert trial["physics_hz"] == 60 and not trial["options"]["rune_modifiers"]
        assert str(trial["options"]["armor"]) == run["armor"]
        assert len(trial["damage_events"]) == trial["options"]["audited_damage_events"]
        assert trial["options"]["end_reason"] == "first_death" or trial["simulated_seconds"] >= run["seconds"]
        assert sorted(a["species"] for a in trial["roster"]) == sorted(run["pair"].split(","))
        actor_map = {a["id"]: a for a in trial["roster"]}
        armor = run["armor"]
        for actor in trial["roster"]:
            other = next(a for a in trial["roster"] if a["id"] != actor["id"])
            actor["opponent_species"] = other["species"]
        for index, action in enumerate(trial["attacks"]):
            assert action["id"] == index and action["end"] >= action["start"]
            assert action["action"] in ACTIONS
            actor = actor_map[action["actor"]]
            other = next(a for a in trial["roster"] if a["id"] != actor["id"])
            action.update(trial=run["name"], armor_mode=armor, opponent_species=other["species"],
                          launched=any(p["phase"] in LAUNCH[action["action"]] for p in action["phases"]),
                          duration=action["end"]-action["start"])
            action["censoring"] = ("owner_defeated" if not actor["alive"] else
                                   "target_defeated" if not other["alive"] else "time_limit_open") \
                                  if action["reason"] == "observation_ended" else "none"
            attacks.append(action)
        for event in trial["damage_events"]:
            assert event["amount"] > 0 and not event["friendly"]
            assert 0 <= event["attack_id"] < len(trial["attacks"])
            action = trial["attacks"][event["attack_id"]]
            assert event["attacker"] == action["actor"]
            assert event["victim"] != event["attacker"]
            assert action["action"] != "wolf_pounce", "Pounce should be displacement-only"
            assert event["profile"] in {"swing", "passive", "shockwave"}
            near(event["raw"], event["amount"]+event["armor_absorbed"]+event["passive_suppression"]+event["overkill"])
            near(event["amount"], min(event["hp_before"], event["after_armor"]))
            near(event["effective_armor_hp_saved"], min(event["without_armor"], event["hp_before"])-event["amount"])
            assert event["effective_armor_hp_saved"] >= -1e-5
            event.update(trial=run["name"], armor_mode=armor, attacker_species=action["species"], action=action["action"])
            events.append(event)
        for action in trial["attacks"]:
            selected = [e for e in trial["damage_events"] if e["attack_id"] == action["id"]]
            near(action["damage"], sum(e["amount"] for e in selected))
            assert action["damage_events"] == len(selected)
        near(sum(a["damage"] for a in trial["attacks"]), sum(e["amount"] for e in trial["damage_events"]))
        for actor in trial["roster"]:
            other = next(a for a in trial["roster"] if a["id"] != actor["id"])
            dealt = [e for e in trial["damage_events"] if e["attacker"] == actor["id"]]
            taken = [e for e in trial["damage_events"] if e["victim"] == actor["id"]]
            hits_dealt = len({e["attack_id"] for e in dealt})
            initial = {p["name"]: p["hp"] for p in actor["initial_parts"]}
            near(actor["initial_hp"], sum(initial.values()))
            near(actor["remaining_hp"], sum(p["hp"] for p in actor["final_parts"]))
            indirect = actor["initial_hp"]-actor["remaining_hp"]-sum(e["amount"] for e in taken)
            assert indirect >= -1e-3
            for part in actor["final_parts"]:
                damage = sum(e["amount"] for e in taken if e["part"] == part["name"])
                assert part["hp"]+damage <= initial[part["name"]]+1e-3
            outcomes.append(dict(trial=run["name"], armor_mode=armor, actor=actor["id"], species=actor["species"],
                                 opponent_species=other["species"], team=actor["team"], alive=actor["alive"],
                                 death_time=actor["death_time"], enemy_death_time=other["death_time"],
                                 enemy_killed_by_damage=not other["alive"] and bool(dealt),
                                 death_without_enemy_damage=not actor["alive"] and not taken,
                                 hits_dealt=hits_dealt, damage_dealt=sum(e["amount"] for e in dealt),
                                 damage_taken=sum(e["amount"] for e in taken), initial_hp=actor["initial_hp"],
                                 remaining_hp=actor["remaining_hp"], indirect_hp_cleared=max(indirect,0),
                                 broken_parts=sum(p["broken"] for p in actor["final_parts"]),
                                 observed_seconds=trial["simulated_seconds"]))
        for effect in trial["effects"]:
            index = effect["attack_id"]
            assert 0 <= index < len(trial["attacks"])
            action = trial["attacks"][index]
            effects.append(dict(effect, trial=run["name"], armor_mode=armor, species=action["species"]))
        for snap in trial["snapshots"]:
            snapshots.append(dict(snap, trial=run["name"], armor_mode=armor,
                                  species=actor_map[snap["actor"]]["species"],
                                  opponent_species=actor_map[snap["actor"]]["opponent_species"]))
        trials.append(dict(run=run, data=trial))
    return manifest, trials, attacks, events, outcomes, effects, snapshots


def summarize(root, partial=False, allow_failed=False):
    manifest, trials, attacks, events, outcomes, effects, snapshots = read_trials(root, partial, allow_failed)
    matrix, species, modules, armor_rows = [], [], [], []
    for armor in ("on", "off"):
        aa = [a for a in attacks if a["armor_mode"] == armor]
        ee = [e for e in events if e["armor_mode"] == armor]
        oo = [o for o in outcomes if o["armor_mode"] == armor]
        for s in SPECIES:
            sa = [a for a in aa if a["species"] == s]
            se = [e for e in ee if e["attacker_species"] == s]
            so = [o for o in oo if o["species"] == s]
            species.append(dict(armor_mode=armor, species=s, **combat_stats(sa, so, se)))
            for target in SPECIES:
                matrix.append(dict(armor_mode=armor, attacker=s, victim=target,
                                   **combat_stats([a for a in sa if a["opponent_species"] == target],
                                                  [o for o in so if o["opponent_species"] == target],
                                                  [e for e in se if e["victim_species"] == target])))
            for action in ACTIONS:
                ma = [a for a in sa if a["action"] == action]
                if not ma: continue
                me = [e for e in se if e["action"] == action]
                modules.append(dict(armor_mode=armor, species=s, action=action,
                                    started=len(ma), launched=sum(a["launched"] for a in ma),
                                    hits=sum(a["damage"] > 0 for a in ma),
                                    hit_rate=ratio(sum(a["damage"] > 0 for a in ma), len(ma)) if action != "wolf_pounce" else None,
                                    mean_damage=ratio(sum(e["amount"] for e in me), len(ma)),
                                    mean_duration=average([a["duration"] for a in ma]),
                                    end_reasons=dict(collections.Counter(a["reason"] for a in ma)),
                                    **damage_totals(me)))
        for s in SPECIES+["all"]:
            selected = [e for e in ee if s == "all" or e["victim_species"] == s]
            totals = damage_totals(selected)
            capped_without = sum(min(e["without_armor"], e["hp_before"]) for e in selected)
            armor_rows.append(dict(armor_mode=armor, victim=s, positive_damage_events=len(selected),
                                   nominal_mitigation_rate=ratio(totals["armor_absorbed"], totals["raw"]),
                                   effective_hp_mitigation_rate=ratio(totals["effective_armor_hp_saved"], capped_without),
                                   zero_effective_saving_events=sum(e["effective_armor_hp_saved"] < 1e-5 for e in selected),
                                   capped_hp_without_armor=capped_without, **totals))
    paired = []
    normal = {(t["run"]["pair"], t["run"]["seed"]): t for t in trials if t["run"]["armor"] == "on"}
    for t in trials:
        run = t["run"]
        if run["armor"] != "off": continue
        base = normal.get((run["pair"], run["seed"]))
        if base is None: continue
        def winner(trial):
            roster = trial["data"]["roster"]
            alive = [a for a in roster if a["alive"]]
            return f"team_{alive[0]['team']}:{alive[0]['species']}" if len(alive) == 1 else "timeout" if len(alive) == 2 else "double_ko"
        paired.append(dict(pair=run["pair"], seed=run["seed"],
                           on_trial=base["run"]["name"], off_trial=run["name"],
                           on_seconds=base["data"]["simulated_seconds"], off_seconds=t["data"]["simulated_seconds"],
                           on_winner=winner(base), off_winner=winner(t),
                           on_damage=sum(e["amount"] for e in base["data"]["damage_events"]),
                           off_damage=sum(e["amount"] for e in t["data"]["damage_events"])))
    blockers = []
    for s in SPECIES:
        ss = [r for r in snapshots if r["species"] == s and r["armor_mode"] == "on" and r["alive"]]
        blockers.append(dict(species=s, samples=len(ss),
                             block_counts=dict(collections.Counter(r["block"] for r in ss)),
                             gate_counts=dict(collections.Counter(str(g["reason"]) for r in ss for g in r["gates"]))))
    paired_names = {row["on_trial"] for row in paired}
    paired_baseline_species = [dict(species=species_id,
                                   **combat_stats([a for a in attacks if a["trial"] in paired_names and a["species"] == species_id],
                                                  [o for o in outcomes if o["trial"] in paired_names and o["species"] == species_id],
                                                  [e for e in events if e["trial"] in paired_names and e["attacker_species"] == species_id]))
                               for species_id in SPECIES]
    configurations = []
    for species_id in SPECIES:
        observed = [actor for trial in trials if trial["run"]["armor"] == "on"
                    for actor in trial["data"]["roster"] if actor["species"] == species_id]
        if not observed: continue
        first = observed[0]
        assert all(a["initial_parts"] == first["initial_parts"] for a in observed)
        configurations.append(dict(species=species_id, parts=first["parts"], initial_hp=first["initial_hp"],
                                   mass=first["mass"], collision_bounds=first["bounds"],
                                   part_hp_values=sorted({p["hp"] for p in first["initial_parts"]}),
                                   armor_values=sorted({p["armor"] for p in first["initial_parts"]})))
    primary_species = [dict(armor_mode=mode, species=species_id,
                            **combat_stats([a for a in attacks if a["armor_mode"] == mode and a["species"] == species_id and a["opponent_species"] != species_id],
                                           [o for o in outcomes if o["armor_mode"] == mode and o["species"] == species_id and o["opponent_species"] != species_id],
                                           [e for e in events if e["armor_mode"] == mode and e["attacker_species"] == species_id and e["victim_species"] != species_id]))
                       for mode in ("on", "off") for species_id in SPECIES]
    failures = []
    for run in manifest["runs"]:
        if run["status"] == "passed": continue
        log = root / "raw" / run["name"] / "stdout.log"
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines() if log.exists() else []
        errors = [line for line in lines if "SCRIPT ERROR:" in line or "CrashHandlerException:" in line]
        failures.append({"trial":run["name"], "pair":run["pair"], "armor":run["armor"],
                         "reason":errors[0] if errors else "incomplete result", "log":log.relative_to(root).as_posix()})
    summary = dict(partial=partial, completed=manifest["completed"], planned=manifest["planned"],
                   valid_trials=len(trials), failed_trials=failures,
                   recovered_trials=[r["name"] for r in manifest["runs"] if r.get("recovered")],
                   primary_trials=sum(len(set(t["run"]["pair"].split(","))) == 2 for t in trials),
                   simulated_seconds=sum(t["data"]["simulated_seconds"] for t in trials),
                   wall_seconds=manifest["wall_seconds"], damage_events=len(events),
                   baseline_trials=sum(t["run"]["armor"] == "on" for t in trials),
                   control_trials=sum(t["run"]["armor"] == "off" for t in trials),
                   time_limits=sum(t["data"]["options"]["end_reason"] == "time_limit" for t in trials),
                   double_kos=sum(all(not a["alive"] for a in t["data"]["roster"]) for t in trials),
                   unknown_deaths=[o for o in outcomes if o["death_without_enemy_damage"]],
                   baseline_death_ledger={key:sum(o[key] for o in outcomes if o["armor_mode"] == "on" and not o["alive"])
                                          for key in ("initial_hp", "damage_taken", "indirect_hp_cleared", "remaining_hp")},
                   species=species, primary_species=primary_species, matchups=matrix, modules=modules, armor=armor_rows, configurations=configurations,
                   paired_armor_controls=paired, blockers=blockers,
                   paired_baseline_species=paired_baseline_species,
                   shockwaves=[dict(armor_mode=mode, species=s, waves=len(ww),
                                    contacts=sum(w["contacts"] for w in ww),
                                    recorded_wave_actions=len({(w["trial"], w["attack_id"]) for w in ww}),
                                    contact_actions=len({(w["trial"], w["attack_id"]) for w in ww if w["contacts"] > 0}),
                                    min_impulse=min((w["impact_impulse"] for w in ww), default=None),
                                    max_impulse=max((w["impact_impulse"] for w in ww), default=None),
                                    max_raw_damage=max((w["raw_damage"] for w in ww), default=None))
                               for mode in ("on", "off") for s in ("stump_beast", "horned_beast")
                               for ww in [[w for w in effects if w["armor_mode"] == mode and w["species"] == s]]])
    return summary, attacks, events, outcomes


def csv_write(path, records):
    if not records: return
    fields = list(dict.fromkeys(key for r in records for key in r))
    with path.open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        for row in records:
            writer.writerow({k: json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else v for k, v in row.items()})


def number(value):
    return "—" if value is None else f"{value:.2f}"


def pct(value):
    return "—" if value is None else f"{value:.1%}"


def report_text(summary):
    s = summary
    lines = ["召唤池生物互攻与护甲实测 2026-10-18", "",
             f"计划 {s['planned']} 场，已执行 {s['completed']} 场；选取完整有效结果 {s['valid_trials']} 场：正常护甲 {s['baseline_trials']} 场，关闭护甲对照 {s['control_trials']} 场。",
             f"异类互攻有完整结果 {s['primary_trials']} 场；同类对战作为补充。原生崩溃后成功复跑替换 {len(s['recovered_trials'])} 场；仍不可用 {len(s['failed_trials'])} 场，全部明确排除。",
             f"模拟时间合计 {s['simulated_seconds']:.2f} 秒；批次墙钟耗时 {s['wall_seconds']:.1f} 秒。",
             "", "实验条件和口径", "",
             "使用当前 CreatureFactory 召唤池正式 NPC 与实际物理、AI、伤害及断裂规则；无符文、无战场修饰。",
             "五种生物两两组合并包含同类，每个无序组合正常护甲4场，左右互换各2场；其中两场同种子另做护甲归零对照。",
             "平地竞技场，初始完整碰撞包围盒间的X轴表面距离60，导航与地形相同；保留各物种当前尺寸、质量、HP、护甲。",
             "每场最多120模拟秒，首次死亡即停止。停止时另一方可能正在攻击；本表计算截止时实际观测到的效果。",
             "有效命中=独立伤害攻击动作至少造成一次敌方正HP扣除。一次攻击击中多个部位只算一次命中，实际扣血相加。",
             "发动包括准备后中断、死亡中断；观察截止尚未完成者单列。没有发动的组合命中率为缺测，不能写成0%。",
             "Wolf飞扑仅提供位移，没有直接伤害；其后啃咬单独计入伤害攻击，飞扑不进入均伤和命中率分母。",
             "每次攻击均伤包含落空；命中均伤只对至少造成一次扣血的攻击取平均，均为实际HP损失而非理论溢出伤害。",
             "击杀命中数只统计已实际击杀对手的场次，包含同帧互相击杀；未击杀者不做HP/均伤外推。关键部位断裂可能连带清空其余HP。",
             "命中率为有效扣血率，不是几何接触率：被护甲完全抵消的接触不进入命中数。",
             "同类对战每场有两名同类攻击者，因此同类单格4场包含8个个体观测；其余单格为4场4个个体。",
             "这是单挑抽样，不能直接当作混战命中率。每组合仅4场，低命中/零命中结论需要扩大样本后验证。",
             "不同种子重复保留相同的已保存结构和初始位置；重复结果可能相同，不能把重复运行当作独立随机姿态样本。", "",
             "当前角色基线（包围盒尺寸为X×Y×Z）", "", "生物\t部位数\t全身HP合计\t单部位HP\t单部位Armor\t总质量\t碰撞包围盒"]
    for r in s["configurations"]:
        lines.append(f"{NAMES[r['species']]}\t{r['parts']}\t{r['initial_hp']:.0f}\t{r['part_hp_values']}\t{r['armor_values']}\t{r['mass']:.2f}\t{'×'.join(f'{x:.3f}' for x in r['collision_bounds'])}")
    lines += ["", "正常护甲主结果（仅不同物种互攻，不包含同类对战）", "",
             "生物\t有效命中/发动\t命中率\t每次攻击均伤\t命中均伤\t已击杀/个体观测\t击杀平均命中数(最小-最大)\t击杀平均耗时"]
    for r in s["primary_species"]:
        if r["armor_mode"] != "on": continue
        bounds = "—" if not r["kills"] else f"{r['mean_hits_to_kill']:.2f}({r['min_hits_to_kill']}-{r['max_hits_to_kill']})"
        lines.append(f"{NAMES[r['species']]}\t{r['hits']}/{r['attempts']}\t{pct(r['hit_rate'])}\t{number(r['mean_damage_per_attempt'])}\t{number(r['mean_damage_per_hit'])}\t{r['kills']}/{r['actor_exposures']}\t{bounds}\t{number(r['mean_seconds_to_kill'])}s")
    lines += ["", "正常护甲：全部25个定向组合", "",
              "攻击方→目标\t有效命中/发动\t命中率\t每次攻击均伤\t命中均伤\t已击杀场次\t击杀平均命中数(最小-最大)\t未击杀场次最多已命中\t未完成动作数"]
    for r in s["matchups"]:
        if r["armor_mode"] != "on": continue
        if not r["duels"]:
            lines.append(f"{NAMES[r['attacker']]}→{NAMES[r['victim']]}\t缺测：没有无错误的完整结果，不计为零命中。")
            continue
        bounds = "—" if not r["kills"] else f"{r['mean_hits_to_kill']:.2f}({r['min_hits_to_kill']}-{r['max_hits_to_kill']})"
        lines.append(f"{NAMES[r['attacker']]}→{NAMES[r['victim']]}\t{r['hits']}/{r['attempts']}\t{pct(r['hit_rate'])}\t{number(r['mean_damage_per_attempt'])}\t{number(r['mean_damage_per_hit'])}\t{r['kills']}\t{bounds}\t{number(r['max_hits_without_kill'])}\t{r['open_at_time_limit']+r['pending_at_death']}")
    lines += ["", "正常护甲：分攻击模组（全部有效样本，含同类补测）", "", "生物/动作\t命中/发动\t进入出招阶段\t扣血总量\t动作平均耗时\t结束原因"]
    for r in s["modules"]:
        if r["armor_mode"] != "on": continue
        lines.append(f"{NAMES[r['species']]}/{ACTIONS[r['action']]}\t{r['hits']}/{r['started']}\t{r['launched']}\t{r['amount']:.2f}\t{r['mean_duration']:.2f}s\t{json.dumps(r['end_reasons'], ensure_ascii=False)}")
    ledger = s["baseline_death_ledger"]
    total_armor = next(r for r in s["armor"] if r["armor_mode"] == "on" and r["victim"] == "all")
    lines += ["", "结果解释", "",
              f"正常护甲中死亡个体初始HP合计{ledger['initial_hp']:.2f}，实际受到直接伤害{ledger['damage_taken']:.2f}，连带Broken清零{ledger['indirect_hp_cleared']:.2f}，停止时剩余{ledger['remaining_hp']:.2f}。",
              "所以不能用全身HP合计除以攻击均伤推算击杀次数；命中Head/Torso或关键连接链，可能比打掉许多非致命部位更快结束战斗。",
              "角兽的踏地与冲锋、Wolf的飞扑与啃咬必须分开看；整体均伤和命中率是模组使用次数混合后的结果，不能直接归因于单一攻击的伤害不足。",
              "树桩兽若冲击波触敌但原伤害仍为0，应优先检查实测落地冲量与全局普通冲量门槛5的关系，不能把零扣血归因于Armor。",
              f"在本组已造成扣血的接触中，Armor名义吸收{total_armor['armor_absorbed']:.2f}，但同事件实际多保住HP只有{total_armor['effective_armor_hp_saved']:.2f}；{total_armor['zero_effective_saving_events']}/{total_armor['positive_damage_events']}笔事件因溢出等原因没有多保住任何HP。",
              "当前Armor10可将最低主动原伤害30降为20（减少1/3）；但原伤害1000面对满100HP部位时，减护甲前后都会清空该部位，护甲不会延长该次存活。",
              "以上解释是当前固定体型、固定HP与护甲下的结果；Spider、Wolf、Snake的尺寸和质量未归一化，不能将差异全部视作技能倍率问题。"]
    lines += ["", "护甲规则与实际减免（全部有效正常护甲受击事件，含同类补测）", "",
              "当前常规部位最大HP与Armor见raw结果的initial_parts；实际活动的全局规则保存在每场options.damage_rules。",
              "主动攻击冲量I≤1时原伤害为0；I>1时原伤害=min(max((I-1)×12,30),10000)。之后逐个部位减去Armor。",
              "普通非挥舞武器：原伤害=min(max((I-5)×2,0),10000)，减护甲后再乘0.05，且单次最多扣2HP。",
              "踏地冲击波使用后一条原始冲量换算和距离衰减，再减护甲；不使用挥舞最低伤害，也不走非挥舞0.05/2HP限制。",
              "名义吸收=原伤害中被Armor抵消的数值。实际保住HP=在同一次事件、同一碰撞冲量和受击前HP下，关闭护甲会额外扣除的HP。",
              "若原伤害远大于剩余HP，Armor虽减掉10伤害，也可能一滴HP都保不住，故名义吸收和实际保住HP必须分开。",
              "以下逐事件护甲归因仅覆盖已经造成正扣血的接触；完全被护甲抵消的接触不在此账本中，不能据此估计全部接触的减免率。", "",
              "受击生物\t正扣血事件\t原伤害合计\t名义吸收\t名义减免率\t实际保住HP\t有效HP减免率\t护甲未保住HP的事件"]
    for r in s["armor"]:
        if r["armor_mode"] != "on": continue
        name = NAMES.get(r["victim"], "合计")
        lines.append(f"{name}\t{r['positive_damage_events']}\t{r['raw']:.2f}\t{r['armor_absorbed']:.2f}\t{pct(r['nominal_mitigation_rate'])}\t{r['effective_armor_hp_saved']:.2f}\t{pct(r['effective_hp_mitigation_rate'])}\t{r['zero_effective_saving_events']}")
    pairs = s["paired_armor_controls"]
    lines += ["", "关闭护甲对照", "",
              f"同种子同初始位置配对 {len(pairs)} 场；生还结果相同 {sum(p['on_winner']==p['off_winner'] for p in pairs)} 场，改变 {sum(p['on_winner']!=p['off_winner'] for p in pairs)} 场。",
              "护甲归零后断裂、倒地、AI和后续轨迹会分叉；整场伤害差不能全部解释成护甲直接减免。paired_armor_controls.csv逐场保留这些差异。",
              "生物\t对照配对中的正常护甲命中/发动\t归零护甲命中/发动\t配对正常均伤\t归零均伤\t配对正常击杀数\t归零击杀数\t归零击杀平均命中数"]
    for r in s["species"]:
        if r["armor_mode"] == "off":
            paired_on = next(p for p in s["paired_baseline_species"] if p["species"] == r["species"])
            lines.append(f"{NAMES[r['species']]}\t{paired_on['hits']}/{paired_on['attempts']}\t{r['hits']}/{r['attempts']}\t{number(paired_on['mean_damage_per_attempt'])}\t{number(r['mean_damage_per_attempt'])}\t{paired_on['kills']}\t{r['kills']}\t{number(r['mean_hits_to_kill'])}")
    lines += ["", "踏地冲击波补充（仅已退出场景的波，截止时仍活跃的波未计入此表）", ""]
    for r in s["shockwaves"]:
        lines.append(f"{NAMES[r['species']]} armor={r['armor_mode']}: waves={r['waves']} contacts={r['contacts']} contact_actions={r['contact_actions']} wave_actions={r['recorded_wave_actions']} impact=[{number(r['min_impulse'])},{number(r['max_impulse'])}] max_raw={number(r['max_raw_damage'])}")
    lines += ["", "数据核验与可复查文件", "",
              f"有效结果中的{s['damage_events']}笔正扣血逐笔核对来源、动作、护甲、HP上限、溢出及伤害和；有效数据没有未归属伤害或友伤。存在运行错误的结果已排除。",
              f"无敌方伤害而死亡的个体：{len(s['unknown_deaths'])}；达到120秒仍未出现首个死亡的场次：{s['time_limits']}（包含护甲对照）。",
              f"同帧双方死亡的对局：{s['double_kos']}（包含护甲对照）；造成击杀不等于本方存活或获胜。",
              "summary.json为完整聚合；matchups.csv为25种定向组合、护甲开关分组；species_summary.csv为物种汇总。",
              "attack_events.csv为逐动作记录；damage_events.csv为逐部位伤害账本；duel_outcomes.csv包括连带Broken清零HP、剩余HP、击杀命中数。",
              "armor_summary.csv为逐事件护甲归因；paired_armor_controls.csv为配对护甲对照；raw/*/result.json为完整原始输出。",
              "manifest.json包含每场状态与结果SHA256；plan.json为预定组合/种子；source_hashes.json保留测试代码与资源的内容版本。",
              "原始manifest保留所有最初失败；analysis_manifest选择有完整无错误结果的同配置复跑，recovery_manifest与recovery2_manifest保留复跑成败。",
              "Spider同类对战触发SpiderLegStepMovementController3D.gd:698已释放关节的类型赋值错误；角兽对Spider出现原生signal 11，具体根因未定位。不能将这些失败记录当作零伤害或零命中。",
              "只新增测试探针和批次/分析脚本，未改动正式角色、攻击、护甲、HP或召唤池资源。",
              "未测真实战斗地图的障碍、符文加成、渲染帧率或多人混战；这些结果不代表最终游戏平衡。", ""]
    lines += ["", "排除的计划轮次", ""]
    lines += [f"{r['trial']}: {r['reason']}；日志 {r['log']}" for r in s["failed_trials"]]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--partial", action="store_true")
    parser.add_argument("--allow-failed", action="store_true", help="Keep failed trials explicit and exclude their incomplete data")
    args = parser.parse_args()
    s, attacks, events, outcomes = summarize(args.directory, args.partial, args.allow_failed)
    target = args.directory / "partial" if args.partial else args.directory
    target.mkdir(exist_ok=True)
    if not args.partial:
        expected = json.loads((args.directory / "source_hashes.json").read_text(encoding="utf-8"))
        s["changed_tested_sources"] = [name for name, digest in expected.items()
                                       if not (PROJECT / name).exists() or hashlib.sha256((PROJECT / name).read_bytes()).hexdigest() != digest]
        assert not s["changed_tested_sources"], s["changed_tested_sources"]
        sources = target / "scripts"
        sources.mkdir(exist_ok=True)
        for relative in ("Tools/Testing/RunSummonCombat.py", "Tools/Testing/SummarizeSummonCombat.py",
                         "Tests/Integration/SimulateCreatureMelee.gd", "Tests/Integration/MeasureSummonCombat.gd"):
            shutil.copyfile(PROJECT / relative, sources / Path(relative).name)
    (target / "summary.json").write_text(json.dumps(s, ensure_ascii=False, indent=2), encoding="utf-8")
    for name, records in [("matchups", s["matchups"]), ("species_summary", s["primary_species"]), ("species_including_mirrors", s["species"]),
                          ("action_summary", s["modules"]), ("armor_summary", s["armor"]),
                          ("paired_armor_controls", s["paired_armor_controls"]),
                          ("attack_events", attacks), ("damage_events", events), ("duel_outcomes", outcomes)]:
        csv_write(target / f"{name}.csv", records)
    (target / "CombatAnalysis.txt").write_text(report_text(s), encoding="utf-8-sig")
    print(json.dumps({"completed": s["completed"], "partial": s["partial"], "damage_events": s["damage_events"],
                      "unknown_deaths": len(s["unknown_deaths"]), "output": str(target)}, ensure_ascii=True))


if __name__ == "__main__":
    main()
