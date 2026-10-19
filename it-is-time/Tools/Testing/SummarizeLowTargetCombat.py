"""Summarize observed low-target damage hits; zero attempts are not a zero hit rate."""
import argparse
from collections import Counter, defaultdict
import csv
import json
from pathlib import Path

NAMES = {"stump_beast":"树桩兽", "wolf":"Wolf", "snake":"Snake", "horned_beast":"HornedBeast",
         "spider":"Spider", "rat_1":"Rat_1", "rat_2":"Rat_2", "bird":"Bird",
         "human_spear1":"Human / Spear1", "human_spear5":"Human / Spear5", "human_sword":"Human / 弯刀",
         "human_claw":"Human / 爪套", "human_flail":"Human / 链锤", "human_shield":"Human / 盾", "human_bow":"Human / Bow"}
CALIBRATED = {"stump_beast":1.21070145, "wolf":1.01251955, "snake":0.30141956,
              "horned_beast":0.84904925, "spider":0.42071807}


def read_batch(folder, phase, include=None):
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["completed"] == manifest["planned"]
    assert json.loads((folder / "changed_sources.json").read_text(encoding="utf-8")) == []
    observations = []
    for trial in manifest["runs"]:
        if include is not None and trial["attacker"] not in include:
            continue
        assert trial["status"] == "passed", trial
        data = json.loads((folder / trial["result"]).read_text(encoding="utf-8"))
        assert not data["errors"]
        assert data["options"]["fixture"] == "passive_live_rat_normal_support_physics_and_contact_callbacks"
        attacker = next(row for row in data["roster"] if row["team"] == 0)
        target = next(row for row in data["roster"] if row["team"] == 1)
        actions = [a for a in data["attacks"] if a["actor"] == attacker["id"] and a["action"] != "wolf_pounce"]
        contacts = [c for c in data["options"]["damage_contacts"] if c["attacker"] == attacker["id"]]
        if phase == "approach" and trial["attacker"] in CALIBRATED:
            assert all(abs(c["multiplier"]-CALIBRATED[trial["attacker"]]) < 1e-6 for c in contacts)
        samples = [s for s in data["snapshots"] if s["actor"] == attacker["id"]]
        gates = Counter(str(g.get("reason")) for s in samples for g in s.get("gates",[]))
        blocks = Counter(s["block"] for s in samples)
        targets = [s for s in data["snapshots"] if s["actor"] == target["id"]]
        final_distances = [g["distance"] for g in samples[-1].get("gates",[]) if "distance" in g] if samples else []
        per_action = []
        for action in actions:
            per_action.append({"phase":phase,"trial":trial["name"],"attacker":trial["attacker"],"target":trial["target"],
                               "side":trial["side"],"action":action["action"],"start":action["start"],"end":action["end"],
                               "reason":action["reason"],"positive_damage_hit":action["damage"]>0,
                               "damage":action["damage"],"parts_hit":len(action["victim_parts"]),
                               "phases":" / ".join(str(p["phase"]) for p in action["phases"])})
        observations.append({"phase":phase,"trial":trial["name"],"attacker":trial["attacker"],"target":trial["target"],
                             "side":trial["side"],"seconds":data["simulated_seconds"],"actions":per_action,
                             "contacts":len(contacts),"armor_blocked_contacts":sum(c["final_damage"]<=0 for c in contacts),
                             "damage":sum(a["damage"] for a in actions),
                             "passive_damage_events":sum(e.get("passive",False) and e["attacker"]==attacker["id"] for e in data["damage_events"]),
                             "passive_damage":sum(e["amount"] for e in data["damage_events"] if e.get("passive",False) and e["attacker"]==attacker["id"]),
                             "no_attack":not actions,"blocks":dict(blocks),"gates":dict(gates),
                             "nearest_final_gate_distance":min(final_distances) if final_distances else None,
                             "target_bounds_height":target["bounds"][1],
                             "target_anchor_height":targets[0]["position"][1] if targets else None,
                             "target_alive":target["alive"],"source":str(folder/trial["result"]),
                             "shutdown_audio_warning":trial.get("shutdown_resource_warning",False)})
    return observations


def aggregate(observations, by_target=False):
    groups = defaultdict(list)
    for row in observations:
        key = (row["phase"],row["attacker"],row["target"] if by_target else "all")
        groups[key].append(row)
    rows = []
    for (phase,attacker,target), entries in sorted(groups.items()):
        actions = [a for entry in entries for a in entry["actions"]]
        hits = sum(a["positive_damage_hit"] for a in actions)
        blocks, gates = Counter(), Counter()
        for e in entries: blocks.update(e["blocks"]); gates.update(e["gates"])
        rows.append({"phase":phase,"attacker":attacker,"target":target,"trials":len(entries),
                     "attempts":len(actions),"hits":hits,"hit_rate":hits/len(actions) if actions else None,
                     "no_attack_trials":sum(e["no_attack"] for e in entries),
                     "censored_no_hit":sum(a["reason"]=="observation_ended" and not a["positive_damage_hit"] for a in actions),
                     "damage_contacts":sum(e["contacts"] for e in entries),
                     "passive_damage_events":sum(e["passive_damage_events"] for e in entries),
                     "passive_damage":sum(e["passive_damage"] for e in entries),
                     "armor_blocked_contacts":sum(e["armor_blocked_contacts"] for e in entries),
                     "mean_damage_per_hit":sum(e["damage"] for e in entries)/hits if hits else None,
                     "target_deaths":sum(not e["target_alive"] for e in entries),
                     "top_block":blocks.most_common(1)[0][0] if blocks else "",
                     "top_gate":gates.most_common(1)[0][0] if gates else ""})
    return rows


def csv_file(path, rows):
    with path.open("w",encoding="utf-8-sig",newline="") as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)


def table(rows):
    output=["| 攻击者 | 发起伤害动作 | 命中动作 | 观察命中率 | 未出手场次 |","|---|---:|---:|---:|---:|"]
    for row in rows:
        rate=f"{row['hit_rate']:.1%}" if row["hit_rate"] is not None else "无法估计"
        output.append(f"| {NAMES[row['attacker']]} | {row['attempts']} | {row['hits']} | {rate} | {row['no_attack_trials']}/{row['trials']} |")
    return "\n".join(output)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args()
    base=args.reports
    broad=read_batch(base/"LiveLowTargetCombat_2026-10-18","approach")
    close=read_batch(base/"LiveLowTargetCloseCombat_2026-10-18","close")
    observations=broad+close
    assert len(broad)==60 and len(close)==28
    rows=aggregate(observations); pairs=aggregate(observations,True)
    actions=[a for e in observations for a in e["actions"]]
    args.out.mkdir(parents=True,exist_ok=True)
    csv_file(args.out/"species_summary.csv",rows)
    csv_file(args.out/"matchups.csv",pairs)
    csv_file(args.out/"attack_actions.csv",actions)
    result={"scope":"live passive low Rat targets with normal support and contact callbacks; production attacker AI/physics",
            "valid_observations":len(observations),"frozen_fixture_observations_excluded":136,
            "approach_trials":60,"close_trials":28,"summary":rows,"observations":observations,
            "shutdown_audio_warnings":sum(e["shutdown_audio_warning"] for e in observations),
            "limitations":["Two mirrored runs per attacker/target cell, not an IID random population",
                           "No target movement intent or retaliation; normal support and hit-driven physics remain active; no obstacles/crowds",
                           "Hit means positive HP damage by an action, not just geometry overlap",
                           "Wolf pounce is locomotion and excluded from damaging action denominator",
                           "Preparation/cancelled and observation-ended actions remain in started-action rate"]}
    (args.out/"summary.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    report="""# 新伤害规则与低矮目标攻击测试

## 已实现的规则

`原始伤害 = 35 × 攻击者完整身体基础总质量的立方根 × 动作倍率 × 命中质量`。

`最终伤害 = max(原始伤害 × 100 / (韧性 + 100) − 固定护甲, 0)`，先韧性、后固定护甲。默认韧性0、固定护甲10，韧性不设百分比钳制。部位默认HP为其裸装基础质量×40；五种召唤池生物的普通攻击采用已校准资源倍率。

同动作可分别对多个部位造成完整伤害，同一部位仅结算一次。身体质量排除装备合并质量，攻击上下文保存质量快照。旧仓库记录只迁移数值，保留保存姿态和符文倍率，下次保存前保留 `.pre_damage_v2.bak`。

## 测试口径

- Godot 4.7.2，固定60物理帧，平坦导航场地；实际保存的NPC场景、正常AI选择、真实运动与伤害，不强制发动攻击。
- 目标为正常参与物理模拟的Rat_1、Rat_2，保留正常HP、质量、防御、站立支撑、重力和接触回调，仅关闭目标AI移动意图和反击；允许受击位移。每场最多35模拟秒，首次死亡结束。
- 主轮覆盖15种物种/武器配置，各对两种目标从左右各测试一次，共60场；追加7种配置的近距离起始测试28场。主轮初始包围盒间距35，近距离轮间距0，不靠缩放模型制造低目标。两轮均不冻结靶体、不增加HP或护甲、不强行调用攻击；正常受击位移和布娃娃可能改变后续目标位置。
- 保存姿态的Rat_1整体碰撞高度约3.86、躯干锚点高度约2.41；Rat_2约3.18和1.99。运行中目标会正常站立及受击移动，实际锚点高度见summary.json。这里的“低矮”相对于多数攻击者；Rat互打是同类尺寸对照。
- 命中率＝造成正HP伤害的动作数/已经开始的伤害动作数。多部位扣血仍只算该动作命中一次；未出手不记成0%命中。Wolf飞扑本身是位移，不进入伤害动作分母。
- 这是包含准备失败和被取消动作的发起动作口径，未完成且未命中的样本另见CSV的 `censored_no_hit`。不能直接解释为“已释放攻击体后的纯几何命中率”。

## 主轮结果

"""+table([r for r in rows if r["phase"]=="approach"])+"""

## 近距离补测

"""+table([r for r in rows if r["phase"]=="close"])+"""

## 结论与后续诊断方向

- 召唤池五类都能实际伤害低矮目标；Wolf此处统计啃咬、HornedBeast主要观察到冲锋，不能推广为其所有攻击都达到表中命中率。树桩兽仍有未产生有效伤害的踏地。
- Bird与Bow具备低目标伤害样本，但准备阶段未完成的动作也计入本报告分母，需结合 `attack_actions.csv` 的阶段和原因字段看待百分比。
- Human近战须区分发起攻击但未形成有效扣血、完全未出手、以及已经命中。对落空样本应分别检查武器轨迹高度、Arm限位、有效伤害窗口及接触冲量；没有有效接触记录时，不应归因于固定护甲或韧性。冻结靶阶段的0%已全部排除。
- Rat及部分Human配置的主要问题是没有获得出手机会，需将AI距离/预测门槛与接近后实际停留位置对照。近距离补测用于区分该问题与已经出手后的落空；本轮没有擅自修改这些AI或动作姿态。
- 本轮为小样本、无移动意图的被动目标、初始同Z轴环境，保存结构重复且左右互为镜像，不提供总体置信区间，不代表移动目标或真实混战中的命中率。

## 数据有效性与复现

正式结果共88场，模拟期间无脚本/物理错误。预备试验曾冻结目标，后经独立碰撞对照证实：冻结靶常规接触伤害为0，未冻结同条件伤害为36.75。冻结会停止受击部位的积分回调，使普通武器与查询式攻击的结果不可比，因此之前136场冻结靶样本全部排除，使用本轮正常物理目标重新测试，不把预备阶段Human近战0%作为最终结论。

另已修正倍率资源的序列化顺序，正式场次对实际伤害上下文中的倍率逐条校验，避免只验证资源文件文本。

正式物理测试禁用音频混音，避免快速固定帧退出时尚未结束的声音产生资源提示；音效另以实时测试通过68项验证。禁用声音不替换伤害、碰撞或攻击行为。常态碰撞扣血单列为passive，不计入主动动作的命中分子或分母。

原始数据和各轮源文件哈希位于相邻 `LiveLowTargetCombat_2026-10-18`、`LiveLowTargetCloseCombat_2026-10-18` 目录。每轮运行期间源文件未变化；两轮配置及纳入范围由本报告和summary.json记录。

复现工具：`Tools/Testing/RunLowTargetCombat.py`。默认测试主轮；使用 `--gap 0 --attackers rat_1,rat_2,human_spear5,human_sword,human_claw,human_flail,human_shield` 可复现近距离轮。每次指定新的 `--out`，不覆盖旧观测。

详细表：`species_summary.csv`、逐组合 `matchups.csv`、逐动作 `attack_actions.csv`、逐场诊断及原始路径 `summary.json`。
"""
    (args.out/"低矮目标攻击测试报告.md").write_text(report,encoding="utf-8")
    print(table([r for r in rows if r["phase"]=="approach"]))
    print("\n近距离\n"+table([r for r in rows if r["phase"]=="close"]))
    print(f"VALID_OBSERVATIONS {len(observations)}")


if __name__=="__main__":main()
