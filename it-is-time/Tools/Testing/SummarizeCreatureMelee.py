"""Validate and summarize SimulateCreatureMelee.gd's actual combat observations."""
import argparse
import collections
import csv
import json
import math
from pathlib import Path

SPECIES = ["stump_beast", "wolf", "snake", "horned_beast", "spider"]
NAMES = dict(zip(SPECIES, ["树桩兽", "Wolf", "Snake", "角兽", "Spider"]))
ACTION_NAMES = {"foreleg_stomp": "踏地", "wolf_pounce": "飞扑（接近动作）", "wolf_bite": "啃咬",
                "snake_lunge_bite": "突进啃咬", "ground_charge": "冲锋", "spider_pounce": "跳跃攻击"}
LAUNCH_PHASES = {"foreleg_stomp": {"STOMPING", "LANDING"}, "wolf_pounce": {"flying"},
                 "wolf_bite": {"lunging", "closing"}, "snake_lunge_bite": {"lunging", "closing"},
                 "ground_charge": {"CHARGING"}, "spider_pounce": {"LEAPING"}}


def rate(hit, total):
    return f"{hit}/{total}（{hit/total:.1%}）" if total else "—（无样本）"


def summarize(rounds):
    attacks, damage, roster, snapshots = [], [], [], []
    for trial in rounds:
        trial_id = str(trial["options"]["seed"])
        actor_map = {row["id"]: row for row in trial["roster"]}
        assert len(actor_map) == len(trial["roster"])
        assert all(row["species"] in SPECIES for row in actor_map.values())
        for index, action in enumerate(trial["attacks"]):
            assert action["id"] == index
            assert action["end"] >= action["start"]
            if action["action"] == "snake_bite": action["action"] = "snake_lunge_bite"
            action["trial"] = trial_id
            action["mode"] = trial["options"]["mode"]
            action["target_species"] = actor_map.get(action["target"], {}).get("species", "unknown")
            action["finished"] = action["reason"] != "observation_ended"
            action["launched"] = any(p["phase"] in LAUNCH_PHASES[action["action"]] for p in action["phases"])
            action["duration"] = action["end"] - action["start"]
            attacks.append(action)
        total = 0.0
        for event in trial["damage_events"]:
            assert event["amount"] > 0 and not event["friendly"]
            assert 0 <= event["attack_id"] < len(trial["attacks"]), event
            action = trial["attacks"][event["attack_id"]]
            assert action["actor"] == event["attacker"], event
            assert event["time"] + 1 / 60 >= action["start"]
            event["trial"] = trial_id
            event["attacker_species"] = action["species"]
            event["action"] = action["action"]
            damage.append(event)
            total += event["amount"]
        assert math.isclose(total, sum(a["damage"] for a in trial["attacks"]), abs_tol=1e-5)
        for action in trial["attacks"]:
            settled = [e for e in trial["damage_events"] if e["attack_id"] == action["id"]]
            assert len(settled) == action["damage_events"]
            assert math.isclose(sum(e["amount"] for e in settled), action["damage"], abs_tol=1e-5)
        for row in trial["roster"]: roster.append(dict(row, trial=trial_id))
        for row in trial["snapshots"]: snapshots.append(dict(row, species=actor_map[row["actor"]]["species"]))

    rows = []
    for species in SPECIES:
        for action_id in ACTION_NAMES:
            selected = [a for a in attacks if a["species"] == species and a["action"] == action_id]
            if not selected: continue
            finished = [a for a in selected if a["finished"]]
            row = {"species": species, "action": action_id, "started": len(selected), "ended": len(finished),
                   "launched": sum(a["launched"] for a in selected), "effective_hits": sum(a["damage"] > 0 for a in selected),
                   "ended_hits": sum(a["damage"] > 0 for a in finished), "hp_damage": sum(a["damage"] for a in selected),
                   "part_damage_events": sum(a["damage_events"] for a in selected),
                   "mean_ended_seconds": sum(a["duration"] for a in finished)/len(finished) if finished else None,
                   "end_reasons": dict(collections.Counter(a["reason"] for a in finished))}
            rows.append(row)
    matrix = []
    for attacker in SPECIES:
        for victim in SPECIES:
            targeted = [a for a in attacks if a["species"] == attacker and a["target_species"] == victim and a["action"] != "wolf_pounce"]
            matrix.append({"attacker": attacker, "victim": victim, "targeted_attacks": len(targeted),
                           "targeted_hits": sum(a["target"] in a["victims"] for a in targeted),
                           "damage_events": sum(e["attacker_species"] == attacker and e["victim_species"] == victim for e in damage),
                           "hp_damage": sum(e["amount"] for e in damage if e["attacker_species"] == attacker and e["victim_species"] == victim)})
    blockers = {}
    for species in SPECIES:
        rows_for_species = [s for s in snapshots if s["species"] == species and s["alive"]]
        blockers[species] = {
            "samples": len(rows_for_species),
            "block_samples": dict(collections.Counter(s["block"] for s in rows_for_species)),
            "gate_reasons": dict(collections.Counter(str(g["reason"]) for s in rows_for_species for g in s["gates"])),
            "prediction_reasons": dict(collections.Counter(str(p.get("reason", p.get("result", {}).get("reason", "unknown")))
                                                          for s in rows_for_species for p in s["predictions"]))}
    return {"rounds": len(rounds), "simulated_seconds": sum(r["simulated_seconds"] for r in rounds),
            "attacks": rows, "matrix": matrix, "blockers": blockers,
            "survival": {s: {"survived": sum(r["alive"] for r in roster if r["species"] == s),
                             "entries": sum(r["species"] == s for r in roster)} for s in SPECIES},
            "errors": [dict(e, seed=r["options"]["seed"]) for r in rounds for e in r["errors"]]}, attacks, damage


def table(summary):
    lines = ["| 类型 | 动作 | 发动 | 进入出招阶段 | 有效命中/发动 | 有效命中/已结束 | 部位扣血事件 | 扣血总量 | 已结束平均耗时 |",
             "|---|---|---:|---:|---|---|---:|---:|---:|"]
    for r in summary["attacks"]:
        mean = f'{r["mean_ended_seconds"]:.2f}s' if r["mean_ended_seconds"] is not None else "—"
        direct = "—（本身无伤害）" if r["action"] == "wolf_pounce" else rate(r["effective_hits"], r["started"])
        ended = "—" if r["action"] == "wolf_pounce" else rate(r["ended_hits"], r["ended"])
        lines.append(f'| {NAMES[r["species"]]} | {ACTION_NAMES[r["action"]]} | {r["started"]} | {r["launched"]} | {direct} | {ended} | {r["part_damage_events"]} | {r["hp_damage"]:.1f} | {mean} |')
    return lines


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    paths = sorted(args.directory.glob("mixed_*.json")) + sorted(args.directory.glob("duel_*.json"))
    rounds = [json.loads(p.read_text(encoding="utf-8")) for p in paths]
    assert rounds, "No completed rounds"
    for trial in rounds:
        assert trial["simulated_seconds"] >= float(trial["options"]["seconds"])
    all_summary, attacks, damage = summarize(rounds)
    mixed = [r for r in rounds if r["options"]["mode"] == "mixed"]
    duel = [r for r in rounds if r["options"]["mode"] == "duel"]
    mixed_summary, _, _ = summarize(mixed)
    duel_summary, _, _ = summarize(duel)
    (args.directory / "summary.json").write_text(json.dumps({"all": all_summary, "mixed": mixed_summary, "duel": duel_summary}, ensure_ascii=False, indent=2), encoding="utf-8")
    for filename, records in [("attack_events.csv", attacks), ("damage_events.csv", damage), ("matchup_matrix.csv", mixed_summary["matrix"])]:
        if not records: continue
        with (args.directory / filename).open("w", newline="", encoding="utf-8-sig") as file:
            writer = csv.DictWriter(file, fieldnames=list(records[0]))
            writer.writeheader()
            writer.writerows(records)
    lines = ["# 生成生物混战测试实测报告", "", "日期：2026-10-16。范围：树桩兽、Wolf、Snake、角兽、Spider；排除 Bird、Human。", "",
             "本次实际运行现有 NPC 的移动、选敌和攻击，重点比较攻击发动后是否造成敌方 HP 减少，并记录未能进入出招阶段的情况。Wolf 啃咬和 Spider 跳跃攻击产生了持续有效伤害；Snake 多次在准备后重新预测失败，角兽的冲锋样本较少；树桩兽有踏地和冲击波触敌，但没有造成 HP 损失。下方数据均以当前体型和预设为准。", "",
             "## 测试条件与统计口径", "",
             f'- Godot {rounds[0]["engine"]["string"]}，无窗口真实物理运行，{rounds[0]["physics_hz"]} Hz，保持正常 HP、护甲、质量、体型、攻击预设、死亡和连带断裂。',
             f'- {len(mixed)} 轮 5 对 5 混战，每侧各一只上述生物，队列按种子打乱；各轮时长依次为 {[r["simulated_seconds"] for r in mixed]} 秒。' if mixed else "- 无混战样本。",
             f'- {len(duel)} 轮不同类型之间的补充单挑；总观察 {all_summary["simulated_seconds"]:.1f} 秒模拟时间。混战与单挑分表，避免把单挑数据充作混战命中率。',
             '- 独立平坦竞技场，导航边界 X±245、Z±125；主混战及常规单挑的初始完整碰撞箱中心在 X=-50 / +50，混战 Z 方向间隔 18；角兽远距离补测使用 X=-110 / +110。复用正式 CreatureFactory、BattleHost、NPC 和物理攻击组件。没有强制攻击、锁定目标或人为续命。',
             '- 有效命中：一次独立攻击至少通过真实 damaged 信号造成一次敌方 HP 减少。一击打到多个部位仍只计一次有效命中；部位事件和扣血另计。伤害数值为实际扣除 HP，排除连带 Broken 清零。',
             '- 该口径不是几何碰撞接触率：被护甲完全抵消的碰撞不算有效命中。本测试不据此断言命中箱是否接触。',
             '- 发动包含准备后中断的动作；“已结束”排除观察截止时尚未结束的动作，包括死亡或目标丢失等中断。两种分母均展示。阶段采样误差不超过一物理帧。',
             '- Wolf 飞扑本身没有伤害碰撞箱，只是位移/接近动作；后续啃咬独立计数，不能把飞扑的 0 伤害当作 0% 攻击命中率。',
             '- 关闭本测试实例的错误自动打包，直接采集脚本/引擎错误。测试不写入存档、不调整游戏资源；不评估画面渲染性能。', "",
             "## 混战结果", ""] + table(mixed_summary)
    lines += ["", "## 混战定向命中矩阵", "", "行是攻击方、列是发动时选定的目标类型。格内为命中该选定角色的动作数/以它为目标发动的伤害动作数；排除纯位移飞扑。误伤其他敌人的伤害不算选定目标命中。无样本不表示不能攻击。", "",
              "| 攻击方 / 目标 | " + " | ".join(NAMES[s] for s in SPECIES) + " |",
              "|---|" + "---|" * len(SPECIES)]
    for species in SPECIES:
        values = [next(r for r in mixed_summary["matrix"] if r["attacker"] == species and r["victim"] == victim) for victim in SPECIES]
        lines.append("| " + NAMES[species] + " | " + " | ".join(rate(r["targeted_hits"], r["targeted_attacks"]) for r in values) + " |")
    lines += ["", "## 补充单挑结果", ""] + table(duel_summary)
    lines += ["", "| 单挑组合（左 / 右） | 初始中心间距 | 发动数（左 / 右） | 有效命中数（左 / 右） | 结束时存活（左 / 右） |", "|---|---:|---:|---:|---|"]
    for r in duel:
        pair = str(r["options"]["pair"]).split(",")
        counts = [sum(a["species"] == s for a in r["attacks"]) for s in pair]
        hits = [sum(a["species"] == s and a["damage"] > 0 for a in r["attacks"]) for s in pair]
        alive = ["是" if row["alive"] else "否" for row in r["roster"]]
        lines.append(f'| {NAMES[pair[0]]} / {NAMES[pair[1]]} | {float(r["options"].get("separation",100)):g} | {counts[0]} / {counts[1]} | {hits[0]} / {hits[1]} | {alive[0]} / {alive[1]} |')
    lines += ["", "## 攻击阻塞与结束情况", "", "以下是存活期间每 0.5 秒的诊断快照计数，不是独立攻击尝试数，持续阻塞会重复采样。gate 原因可能每快照含多个攻击选项。", ""]
    for species in SPECIES:
        blocker = mixed_summary["blockers"][species]
        top = sorted(blocker["block_samples"].items(), key=lambda p: -p[1])[:5]
        gates = sorted(blocker["gate_reasons"].items(), key=lambda p: -p[1])[:5]
        reasons = {ACTION_NAMES[r["action"]]: r["end_reasons"] for r in mixed_summary["attacks"] if r["species"] == species}
        lines += [f'- **{NAMES[species]}**：block={top}；gate={gates}；动作结束原因={reasons}。']
    detailed = [r for r in rounds if "effects" in r]
    if detailed:
        effects = [dict(e, seed=r["options"]["seed"]) for r in detailed for e in r["effects"]]
        transitions = [p for r in detailed for a in r["attacks"] if a["action"] == "snake_lunge_bite" for p in a["phases"] if p["phase"] == "recovering"]
        lines += ["", "## 补充阶段诊断", "", f'额外阶段原因/冲击波记录覆盖种子 {[r["options"]["seed"] for r in detailed]}，不追溯填充早期轮次。', "",
                  f'- Snake 进入 recovering 时的直接原因：{dict(collections.Counter(p.get("reason", "unknown") for p in transitions))}。应查看这个原因，末尾 completed 可能仅代表恢复收尾完成。',
                  f'- 已结束冲击波 {len(effects)} 个，记录到敌方范围接触 {sum(e["contacts"] for e in effects)} 次（未按动作去重）；原始伤害范围 {min((e["raw_damage"] for e in effects), default=0):.3f}～{max((e["raw_damage"] for e in effects), default=0):.3f}。']
        if effects:
            (args.directory / "shockwave_effects.json").write_text(json.dumps(effects, ensure_ascii=False, indent=2), encoding="utf-8")
            wave_actions = {(e["seed"], e["attack_id"]) for e in effects}
            contact_actions = {(e["seed"], e["attack_id"]) for e in effects if e["contacts"] > 0}
            lines += [f'- 这些冲击波来自 {len(wave_actions)} 次独立踏地，其中 {len(contact_actions)} 次发生敌方接触。接触与扣血是两个不同指标。',
                      f'- 记录的落地冲量为 {min(e["impact_impulse"] for e in effects):.3f}～{max(e["impact_impulse"] for e in effects):.3f}。当前 ForeLegStompShockwave 的 impulse_scale=1，StompShockwave3D 调用 DamageService.calculate_raw_damage，DamageRules 的 impulse_threshold=5；本组原始伤害因此为 0，尚未进入有效的护甲后扣血。这一链路解释了本补充轮中树桩兽接触敌人却没有造成伤害的情况。']
    lines += ["", "## 行为差异和后续排查重点", "",
              "Wolf 的飞扑与啃咬必须分开理解。飞扑负责接近，真正伤害来自啃咬；一次啃咬可以打到多个部位或其他敌人，所以有效动作命中数、选定目标命中数和部位扣血事件数并不相同。", "",
              "Snake 的低混战命中率主要表现为大量准备动作未进入突进阶段。补充轮直接记录到 snake_sweep_misses、target_left_attack_plane 和 target_lost；这些动作随后进入恢复，即使最终显示 completed，也不表示已完成一次有效突进。单挑结果明显高于混战，说明目标移动与混战环境下的预测重验值得优先排查。", "",
              "主混战中角兽很少进入实际冲锋，多数存活快照为 out_of_range。当前冲锋接收器给出的最小 X 距离是 133，大于主测试的初始队伍中心间距 100；日志具体拒绝原因为 below_acceleration_distance，所以 out_of_range 在这里主要表示太近。补充混战轮有三次冲锋对齐等待约 8 秒后以 alignment_timeout 结束；另一动作在观察结束前才进入 CHARGING。远距离单挑单独列出，不能用主混战的零命中推断冲锋功能无法工作。", "",
              "Spider 存在 launch_target_unreachable 导致的准备后中断；已进入跳跃也可能因目标丢失、布娃娃或冲击波中断。它与 Wolf 的差别不能只用伤害倍率解释，需分别检查起跳前的可达性重验与实际跳跃轨迹。", "",
              "建议优先检查踏地冲量到伤害的转换，再检查 Snake 的准备后重验、角兽对齐和 Spider 起跳可达性。这里仅给出排查顺序，测试未修改这些行为。"]
    far_trials = [r for r in duel if float(r["options"].get("separation", 100)) > 100]
    if far_trials:
        charges = [a for r in far_trials for a in r["attacks"] if a["action"] == "ground_charge"]
        casualties = [row for r in far_trials for row in r["roster"] if row["species"] != "horned_beast" and not row["alive"]]
        lines += ["", f'角兽远距离补测：中心间距 220 的 {len(far_trials)} 轮中，自然发动 {len(charges)} 次冲锋，{sum(a["damage"] > 0 for a in charges)} 次有效命中；{len(casualties)} 个对手死亡。当前两次均在约 8 秒前后使 Wolf / Spider 失去战斗能力，证明该距离条件下冲锋能够发动和结算伤害。样本仅两次，不应将其外推为稳定的 100% 命中率。']
    lines += ["", "## 当前体型和物理基线", "", "| 类型 | 部位数 | 总 HP | 总质量 | 碰撞包围盒 X × Y × Z |", "|---|---:|---:|---:|---|"]
    for species in SPECIES:
        row = next(r for r in rounds[0]["roster"] if r["species"] == species)
        lines.append(f'| {NAMES[species]} | {row["parts"]} | {row["initial_hp"]:.1f} | {row["mass"]:.3f} | {" × ".join(f"{v:.3f}" for v in row["bounds"])} |')
    lines += ["", "## 轮次与数据完整性", "", "| 模式 | 种子 | 模拟秒 | 攻击动作 | 扣血事件 | 断裂部位事件 | 错误 |", "|---|---:|---:|---:|---:|---:|---:|"]
    for r in rounds:
        lines.append(f'| {r["options"]["mode"]} | {r["options"]["seed"]} | {r["simulated_seconds"]:.1f} | {len(r["attacks"])} | {len(r["damage_events"])} | {len(r["breaks"])} | {len(r["errors"])} |')
    lines += ["", f'记录 {len(attacks)} 次动作、{len(damage)} 次扣血事件；敌方伤害来源全部关联到具体动作，伤害求和一致、友伤为 0。采集到的错误数：{len(all_summary["errors"])}。',
              "", "## 解释范围与复测", "", "这是一组当前版本的行为抽样，不能当作长期平衡胜率。体型没有归一化，初始位置、选敌、目标移动、断肢、倒地和死亡都会影响命中率。低样本尤其不应外推；常规单挑每组合一轮，角兽额外补测两种远距离组合，尚未对所有组合做左右互换复测。统计没有把零攻击数写成零命中率。", "",
              "原始 mixed_*.json / duel_*.json 含每次动作的阶段时间、目标、伤害和每 0.5 秒 AI 状态；同名 .log / .stdout.txt 为完整运行输出。summary.json、attack_events.csv、damage_events.csv 和 matchup_matrix.csv 可重新检查汇总。", "",
              "重跑单轮（在项目目录，推荐给 APPDATA/LOCALAPPDATA 指定独立测试目录）：", "", "```powershell",
              "& 'D:/GameJamWorkspace/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe' --headless --path . --fixed-fps 60 --script res://Tests/Integration/SimulateCreatureMelee.gd -- --seed=161001 --seconds=45 --out=D:/GameJamWorkspace/Reports/MeleeSimulation_2026-10-16/retest.json",
              "# 单挑再追加：--mode=duel --pair=wolf,snake", "```", ""]
    (args.directory / "混战测试报告.md").write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"mixed": mixed_summary["attacks"], "duel": duel_summary["attacks"], "errors": all_summary["errors"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
