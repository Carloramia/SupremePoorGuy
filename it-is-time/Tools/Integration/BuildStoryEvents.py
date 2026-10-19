"""Compile current planning text to native story assets; never execute prose as code.

Only texts.json is rebuilt. Editable flows/parameters are created once, then preserved.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Content/Events/Current"
SOURCE = ROOT.parent / "UI跳转原型/事件/草原事件_配表草稿.events.json"
AUTHORITY = SOURCE.with_name("事件总表.md")
ACTIVE_PARAMETERS = {
    "QST_MAIN_001_001": [], "QST_GRASS_002": ["battles"],
    "QST_SIDE_001_001": ["private_money_magic"], "QST_SIDE_002_001": ["battles"],
    "QST_GRASS_005": [], "QST_GRASS_006": ["pickup_item_id", "battles"],
    "QST_GRASS_007": [], "QST_GRASS_008": ["battles"], "QST_GRASS_009": ["magic_reward"],
    "QST_GRASS_010": ["attack_threshold", "magic_reward"], "QST_GRASS_011": ["battles"],
    "QST_GRASS_012": ["direct_magic_reward", "enchanter_magic_reward", "battles"],
    "QST_GRASS_013": ["magic_reward"], "QST_GRASS_014": ["purchase_cost"], "QST_GRASS_015": [],
    "QST_GRASS_016": ["battles"], "QST_GRASS_017": ["fight_magic_reward", "wood_magic_reward", "battles"],
    "QST_SIDE_003_001": ["first_magic_reward"],
    "QST_GRASS_019": ["watch_magic_reward", "battles", "reward_presets"],
    "QST_GRASS_020": ["loss_policy", "rounds"],
    "AUX_GRASS_FOSTER": [], "AUX_GRASS_SALGERT": [], "AUX_GRASS_ROVA": [],
}

def dialogue(paragraphs, next_node):
    return {"type": "dialogue", "paragraphs": paragraphs, "next": next_node}

def option(key, label, next_node="", **action):
    value = {"id": key, "label": label}
    if next_node:
        value["next"] = next_node
    if action:
        value["action"] = action
    return value

def choice(*options, paragraphs=None):
    return {"type": "choice", "paragraphs": paragraphs or [], "options": list(options)}

def action(label, op, **fields):
    return {"type": "action", "label": label, "action": {"op": op, **fields}}

def flow(start, **nodes):
    return {"start": start, "nodes": nodes}

def battle(branch, won, lost="decision", mode="party", **more):
    return {"op": "battle", "branch": branch, "won": won, "lost": lost, "mode": mode, **more}

def definitions():
    leave = option("leave", "离开", op="close")
    end = {"type": "end"}
    result = {}
    result["QST_MAIN_001_001"] = flow("intro", intro=dialogue(list(range(3,11)), "sign"), sign=action("确认签收", "appointment"), end=end)
    result["QST_GRASS_002"] = flow("intro", intro=dialogue([3,4,5], "decision"), decision=choice(option("battle", "教训卡洛德", **battle("battle", "end")), leave), end=end)
    result["QST_SIDE_001_001"] = flow("intro", intro=dialogue(list(range(3,11)), "runes"), runes=action("收下攻击、防御符文", "reward", reward_key="QST_SIDE_001_001", next="aid"), aid=choice(option("aid", "领取罗瓦的援助", op="money", parameter="private_money_magic", next="end"), leave), end=end)
    result["QST_SIDE_002_001"] = flow("intro", intro=dialogue(list(range(4,9)), "accept"), accept=choice(option("accept", "接下委托", "progress", op="flag", flag="accepted", value=True), leave), progress=choice(option("battle", "前往已绑定的清剿战斗", **battle("clear", "return", "progress")), leave, paragraphs=[11]), **{"return":choice(option("submit", "返回城主交付", "submit", op="require_role", role="city_center"),leave), "submit":dialogue([14,15,16], "reward"), "reward":action("收下螺旋人像", "reward", reward_key="QST_SIDE_002_001", next="end"), "end":end})
    result["QST_GRASS_005"] = flow("intro", intro=dialogue([0,1,2,3,4], "end"), end=end)
    result["QST_GRASS_006"] = flow("intro", intro=dialogue([0], "pickup"), pickup=action("拾取神秘物品", "pickup", next="approach"), approach=dialogue([1], "decision"), decision=choice(option("battle", "应对靠近的狼群", **battle("battle", "end", "decision")),leave), end=end)
    result["QST_GRASS_007"] = flow("donkey", donkey=dialogue([1], "donkey_choice"), merchant=dialogue([3,4,5,6], "merchant_choice"), donkey_choice=choice(option("from_donkey", "我带你去找你兄弟", "return_dialogue", op="both_seen"), leave), merchant_choice=choice(option("from_merchant", "是一头很老的驴吗？", "return_dialogue", op="both_seen"), leave), return_dialogue=dialogue([9], "reward"), reward=action("收下挑衅铃、宣传旗帜", "reward", reward_key="QST_GRASS_007", next="end"), end=end)
    result["QST_GRASS_008"] = flow("intro", intro=dialogue([0,1], "decision"), decision=choice(option("battle", "应对冲来的拱兽", **battle("battle", "reward")), leave), reward=action("收下巨化符文", "reward", reward_key="QST_GRASS_008", next="end"), end=end)
    result["QST_GRASS_009"] = flow("intro", intro=dialogue([0,1,2,3,4,5], "reward"), reward=action("领取魔力", "money", parameter="magic_reward", next="end"), end=end)
    result["QST_GRASS_010"] = flow("intro", intro=dialogue([0,1], "decision"), decision=choice(option("break", "尝试打碎甲壳", op="attack_check", passed="success", failed="failure"),leave), failure=dialogue([3], "decision"), success=dialogue([4,5], "reward"), reward=action("收下壳雕和魔力", "shell_reward", next="end"), end=end)
    result["QST_GRASS_011"] = flow("intro", intro=dialogue([0,1,2], "decision"), decision=choice(option("enter", "进入探索", **battle("enter", "aftermath", restriction="no_large")),leave), aftermath=dialogue([5,6], "reward"), reward=action("摘抄大群、撕咬诅咒", "reward", reward_key="QST_GRASS_011", next="end"), end=end)
    result["QST_GRASS_012"] = flow("intro", intro=dialogue([0,1,2,3], "decision"), decision=choice(option("direct", "直接解决", **battle("direct", "direct_aftermath")), option("ask", "路过萨尔格特城帮你问一下", "waiting", op="flag", flag="await_enchanter", value=True),leave), waiting=choice(option("enchanter", "寻找附魔魔法师", "enchanter", op="require_role", role="return_city_enchanter"),leave), direct_aftermath=dialogue([{"index":4,"lines":[1,2]}],"direct_reward"), direct_reward=action("领取直接解决的报酬", "money", parameter="direct_magic_reward", next="end"), enchanter=dialogue([{"index":6,"lines":[0]}], "enchanter_reward"), enchanter_reward=action("领取回城处理的报酬", "money", parameter="enchanter_magic_reward", next="end"), end=end)
    result["QST_GRASS_013"] = flow("intro", intro=dialogue([0,1,2], "decision"), decision=choice(option("record", "记录星图", op="money", parameter="magic_reward", next="end"),leave), end=end)
    result["QST_GRASS_014"] = flow("intro", intro=dialogue(list(range(7)), "decision"), decision=choice(option("buy", "我买了", op="buy_engine", next="bought"),leave), bought=dialogue([8], "end"), end=end)
    result["QST_GRASS_015"] = flow("intro", intro=dialogue([1,2,3,4,5,6], "decision"), decision=choice(option("funny", "有点好笑", "funny"),option("kind", "没那么好笑", "kind")), funny=dialogue([8,9,10,11], "teach"), kind=dialogue([13,14,15,16], "teach"), teach=action("学习好战、血肉顽强", "reward", reward_key="QST_GRASS_015", next="end"), end=end)
    result["QST_GRASS_016"] = flow("intro", intro=dialogue(list(range(6)), "decision"), decision=choice(option("help", "帮他处理魔眼拱兽", **battle("help", "aftermath")),option("away", "离远一点", op="close")), aftermath=dialogue([{"index":7,"lines":[0]},8], "reward"), reward=action("收下结晶化眼球", "reward", reward_key="QST_GRASS_016", next="end"), end=end)
    result["QST_GRASS_017"] = flow("intro", intro=dialogue([0,1,2], "decision"), decision=choice(option("fight", "帮忙赶走鸟", **battle("fight", "fight_reward")),option("wood", "建议用木头搭桥", "wood", op="require_money", parameter="wood_magic_reward"),leave), wood=dialogue([{"index":4,"lines":[1]}], "wood_reward"), wood_reward=action("领取木桥方案的报酬", "money", parameter="wood_magic_reward", next="end"), fight_reward=action("领取赶走食矿鸟的报酬", "money", parameter="fight_magic_reward", next="end"), end=end)
    result["QST_SIDE_003_001"] = flow("intro", intro=dialogue([1,2], "stage_1"), stage_1=choice(option("first", "选择1只有皮毛的怪物", op="sacrifice", stage=1, next="stage_2"),leave, paragraphs=[{"index":3,"lines":[0,1]}]), stage_2=choice(option("second", "选择2只飞行怪物", op="sacrifice", stage=2, next="stage_3"),leave, paragraphs=[{"index":4,"lines":[0,1]}]), stage_3=choice(option("third", "选择3只无手无足的蛇类怪物", op="sacrifice", stage=3, next="end"),leave, paragraphs=[{"index":5,"lines":[0,1]}]), end=end)
    result["QST_GRASS_019"] = flow("intro", intro=dialogue([0,1,2], "decision"), decision=choice(option("wolf", "帮助狼", **battle("wolf", "monster_reward", reward_preset="wolf")), option("beast", "帮助拱兽", **battle("beast", "monster_reward", reward_preset="beast")), option("watch", "谁也不帮", **battle("watch", "watch_reward", mode="spectator")),leave), monster_reward=action("接收获胜奖励怪物", "monster_reward", next="end"), watch_reward=action("领取观战魔力", "money", parameter="watch_magic_reward", next="end"), end=end)
    result["QST_GRASS_020"] = flow("intro", intro=dialogue([0,1,2,3,4], "decision"), decision=choice(option("one", "赌就赌，我选怪物1组", op="bet", side=0), option("two", "赌就赌，我选怪物2组", op="bet", side=1),leave), again=dialogue([7], "decision"), gift=dialogue([11], "gift_reward"), gift_reward=action("收下发条盒", "reward", reward_key="QST_GRASS_020:round_4", next="end"), unresolved={"type":"blocked","message":"本轮结果或账务处理尚待配置。保留原赌局，不再次下注、不擅自退款或增加轮次。"}, end=end)
    result["AUX_GRASS_ROVA"] = flow("intro", intro=dialogue([1], "close"), close=action("返回", "close"))
    for key in ["AUX_GRASS_FOSTER","AUX_GRASS_SALGERT"]:
        result[key]=flow("menu", menu={"type":"container"})
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--verify",action="store_true")
    args=parser.parse_args()
    draft=json.loads(SOURCE.read_text(encoding="utf-8-sig"))
    source_map=json.loads((ROOT/"Content/Maps/FrontierEditor_20261019/Source/hex_layout.json").read_text(encoding="utf-8-sig"))
    document={"schema_version":1,"authority_sha256":hashlib.sha256(AUTHORITY.read_bytes()).hexdigest(),"draft_sha256":hashlib.sha256(SOURCE.read_bytes()).hexdigest(),"events":{row["id"]:{"title":row["name"],"paragraphs":[p["text"] for p in draft["stories"][row["id"]]]} for row in draft["tables"]["events"]}}
    flows=definitions()
    parameters={}
    for event in source_map["event_catalog"]["events"]:
        values=dict(event.get("runtime_bindings",{}).get("parameters",{}))
        values["battles"]={}
        for node in flows[event["id"]]["nodes"].values():
            for item in node.get("options",[]):
                command=item.get("action",{})
                if command.get("op")=="battle":
                    values["battles"][command["branch"]]={"battle_map_id":None,**({"side_a_roster":None,"side_b_roster":None} if command.get("mode")=="spectator" else {"enemy_config_id":None})}
        parameters[event["id"]]=values
    parameters["QST_SIDE_001_001"]["rune_unlock_count"]=2
    # Reuse explicit authoring-map bindings, including disabled rosters. Never swap species.
    native=json.loads((ROOT/"Content/Maps/FrontierEditor_20261019/Runtime/Maps/frontier_layout.json").read_text(encoding="utf-8"))
    for event_id,site_id in [("QST_GRASS_002","layout_wolf_den_001"),("QST_GRASS_008","layout_forest_wolf_den_001")]:
        site=next(row for row in native["objects"] if row["id"]==site_id)
        parameters[event_id]["battles"]["battle"].update({"battle_map_id":site["battle_map_id"],"enemy_config_id":site["enemy_config_id"]})
    parameters["QST_SIDE_002_001"]["battles"]["clear"]["source_id"]=None
    parameters["QST_GRASS_008"].pop("relic_quantity",None)
    parameters["QST_GRASS_008"]["rune_unlock_count"]=1
    parameters["QST_GRASS_011"]["rune_unlock_count"]=2
    parameters["QST_GRASS_015"]["rune_unlock_count"]=2
    parameters["QST_GRASS_016"].pop("magic_eye_probability",None)
    parameters["QST_GRASS_016"]["magic_eye_guaranteed_count"]=1
    parameters["QST_GRASS_006"]["pickup_item_id"]=None
    parameters["QST_GRASS_010"].pop("action_magic_cost",None) # No confirmed action cost.
    parameters["QST_GRASS_014"]["maximum_array_stage"]=4 # Existing supported board capacity.
    parameters["QST_SIDE_003_001"].pop("third_rune_unlock_count",None)
    parameters["QST_SIDE_003_001"]["second_rune_unlock_count"]=1
    parameters["QST_SIDE_003_001"]["third_relic_quantity"]=1
    parameters["QST_GRASS_019"]["reward_presets"]={"wolf":None,"beast":None}
    parameters["QST_GRASS_020"].update({"loss_policy":None,"rounds":[{"battle_map_id":None,"side_a_roster":None,"side_b_roster":None} for _ in range(4)],"gift_relic_id":"clockwork-box"})
    # Export only operational knobs. Historical count/weather placeholders remain in Source.
    parameters={event_id:{key:values[key] for key in ACTIVE_PARAMETERS[event_id]} for event_id,values in parameters.items()}
    # Confirmed Demo fixed event payments. Combat-level loot is a separate pending system.
    fixed_magic = {
        "QST_SIDE_001_001": {"private_money_magic": 10},
        "QST_GRASS_009": {"magic_reward": 10},
        "QST_GRASS_010": {"magic_reward": 20},
        "QST_GRASS_012": {"direct_magic_reward": 10, "enchanter_magic_reward": 20},
        "QST_GRASS_013": {"magic_reward": 10},
        "QST_GRASS_017": {"fight_magic_reward": 10, "wood_magic_reward": 10},
        "QST_SIDE_003_001": {"first_magic_reward": 20},
        "QST_GRASS_019": {"watch_magic_reward": 10},
    }
    for event_id, rewards in fixed_magic.items():
        parameters[event_id].update(rewards)
    if args.verify:
        saved=json.loads((OUT/"texts.json").read_text(encoding="utf-8"))
        assert saved==document,"Texts differ from current authority; rebuild first."
        saved_flows=json.loads((OUT/"flows.json").read_text(encoding="utf-8"))
        assert set(saved_flows)==set(document["events"]),"Event IDs differ."
        saved_parameters=json.loads((OUT/"parameters.json").read_text(encoding="utf-8"))
        assert set(saved_parameters)==set(saved_flows),"Parameter IDs differ."
        print("STORY_SOURCE_VERIFIED events=23")
        return
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/"texts.json").write_text(json.dumps(document,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    for name,value in [("flows.json",flows),("parameters.json",parameters)]:
        target=OUT/name
        if not target.exists():target.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("STORY_COMPILED events=23; editable existing flows/parameters preserved")

if __name__=="__main__":main()
