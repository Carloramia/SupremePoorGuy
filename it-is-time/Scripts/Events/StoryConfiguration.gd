extends RefCounted
## Validate authoring types, not readiness. null stays pending and never becomes zero.
const FIELDS := {
	"QST_MAIN_001_001":[], "QST_GRASS_002":["battles"],
	"QST_SIDE_001_001":["private_money_magic"], "QST_SIDE_002_001":["battles"],
	"QST_GRASS_005":[], "QST_GRASS_006":["pickup_item_id","battles"],
	"QST_GRASS_007":[], "QST_GRASS_008":["battles"], "QST_GRASS_009":["magic_reward"],
	"QST_GRASS_010":["attack_threshold","magic_reward"], "QST_GRASS_011":["battles"],
	"QST_GRASS_012":["direct_magic_reward","enchanter_magic_reward","battles"],
	"QST_GRASS_013":["magic_reward"], "QST_GRASS_014":["purchase_cost"], "QST_GRASS_015":[],
	"QST_GRASS_016":["battles"], "QST_GRASS_017":["fight_magic_reward","wood_magic_reward","battles"],
	"QST_SIDE_003_001":["first_magic_reward"],
	"QST_GRASS_019":["watch_magic_reward","battles","reward_presets"],
	"QST_GRASS_020":["loss_policy","rounds"],
	"AUX_GRASS_FOSTER":[], "AUX_GRASS_SALGERT":[], "AUX_GRASS_ROVA":[]
}

static func integer(value: Variant, minimum := 0) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and floor(float(value))==float(value) and float(value)>=minimum

static func error(values: Variant, only_id := "") -> String:
	if not values is Dictionary: return "parameters.json必须为事件ID字典。"
	var ids: Array = FIELDS.keys() if only_id.is_empty() else [only_id]
	for id: String in ids:
		if not FIELDS.has(id): return "未注册的事件参数ID："+id
		var p: Variant = values.get(id,{})
		if not p is Dictionary: return "事件参数必须为字典："+id
		for key: Variant in p:
			if not key is String or key not in FIELDS[id]: return "未知参数："+id+"."+str(key)
			var value: Variant = p[key]
			if value==null: continue
			var path: String = id+"."+str(key)
			match key:
				"battles":
					if not value is Dictionary: return path+"必须为分支字典。"
					for branch: Variant in value:
						var reason := battle_error(value[branch],path+"."+str(branch))
						if not reason.is_empty(): return reason
				"rounds":
					if not value is Array or value.size()!=4: return path+"必须为4轮配置数组。"
					for index: int in value.size():
						var reason := battle_error(value[index],path+"[%d]" % index)
						if not reason.is_empty(): return reason
				"reward_presets":
					if not value is Dictionary: return path+"必须为奖励路径字典。"
					for branch: Variant in value:
						if branch not in ["wolf","beast"] or (value[branch]!=null and not value[branch] is String): return path+"含无效奖励引用。"
				"pickup_item_id","loss_policy":
					if not value is String: return path+"必须为字符串或null。"
				_:
					if not (value is float or value is int) or not is_finite(float(value)) or float(value)<0: return path+"必须为非负有限数值或null。"
		# Structural containers cannot be null: their children may remain null instead.
		for key: String in ["battles","rounds","reward_presets"]:
			if p.has(key) and p[key]==null: return id+"."+key+"结构不能为null，请保留子字段为null。"
	return ""

static func battle_error(value: Variant, path: String) -> String:
	if not value is Dictionary: return path+"必须为战斗配置字典。"
	for key: Variant in value:
		if key not in ["source_id","battle_map_id","enemy_config_id","side_a_roster","side_b_roster"]: return path+"含未知字段："+str(key)
		if value[key]!=null and not value[key] is String: return path+"."+str(key)+"必须为ID字符串或null。"
	return ""
