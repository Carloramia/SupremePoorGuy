extends RefCounted
## Trusted event-system adapter, not a dialogue/quest runner. Facts come from the owning system.
const CONTENT = preload("res://Scripts/Summoning/SummonContent.gd")

static func apply(data: Dictionary, key: String, receipt_id: String, facts: Dictionary) -> String:
	if not CONTENT.EVENT_REWARDS.has(key) or receipt_id.strip_edges().is_empty(): return "奖励来源或回执缺失。"
	var marker := "content_reward:"+key
	if marker in data.completed: return "这份奖励已经领取。"
	if key in ["QST_GRASS_008","QST_GRASS_011","QST_GRASS_016","boss:earth-guardian","QST_SIDE_002_001","QST_GRASS_020:round_4"]:
		var battle: Dictionary = data.battle_results.get(str(facts.get("battle_id","")),{})
		var source := "QST_GRASS_020" if key=="QST_GRASS_020:round_4" else key
		if battle.is_empty() or battle.get("content_source","")!=source: return "缺少与本事件匹配的真实战斗回执。"
		if key=="QST_GRASS_020:round_4":
			if battle.get("outcome") not in ["victory","defeat"] or battle.get("combat_mode")!="spectator" or int(facts.get("settled_rounds",0))!=4: return "赠礼只在第四次真实观战赌局结算后发放，胜负均可。"
		elif battle.get("outcome")!="victory": return "该事件需要对应战斗胜利。"
	if key in ["QST_SIDE_001_001","QST_GRASS_007","QST_GRASS_015"] and facts.get("dialogue_completed")!=true: return "需要指定对话完成回执。"
	if key=="QST_SIDE_002_001" and facts.get("returned_to_giver")!=true: return "防卫预算需要返回城主交付。"
	if key=="QST_GRASS_010" and facts.get("single_owned_attack_check_passed")!=true: return "甲壳圣堂需要正式库存的单体攻击条件通过。"
	if key.begins_with("QST_SIDE_003_001:"):
		if facts.get("sacrifice_committed")!=true or facts.get("stage")!=key.get_slice(":",1): return "献祭阶段或消费回执缺失。"
		if key.ends_with(":stage_3") and "content_reward:QST_SIDE_003_001:stage_2" not in data.completed: return "先结算第二次献祭奖励，再接收第三次献祭奖励。"
	var reward: Dictionary = CONTENT.EVENT_REWARDS[key]
	for id: String in reward.runes:
		if id not in data.known_runes: data.known_runes.append(id)
	for id: String in reward.relics:
		if id not in data.known_relics: data.known_relics.append(id)
	data.completed.append(marker)
	if not data.has("content_reward_receipts"): data.content_reward_receipts={}
	data.content_reward_receipts[key]=receipt_id
	return ""
