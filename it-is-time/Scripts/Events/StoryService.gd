extends RefCounted
## Transactional story logic. GameSession alone owns saving and rollback.
const CATALOG = preload("res://Scripts/Events/StoryCatalog.gd")
const REWARDS = preload("res://Scripts/Summoning/SummonRewardBindings.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const MAPS = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const OPENING := "QST_MAIN_001_001"
const LIBRARY := "QST_SIDE_001_001"
const ENGINE := "QST_GRASS_014"
const GHOST := "QST_GRASS_015"
const ALTAR := "QST_SIDE_003_001"
const BET := "QST_GRASS_020"

static func ensure(data: Dictionary) -> Dictionary:
	if not data.has("story_events"): data.story_events={"version":1,"entries":{},"receipts":{}}
	return data.story_events

static func entry(data: Dictionary, id: String) -> Dictionary:
	return data.get("story_events",{}).get("entries",{}).get(id,{})

static func valid(data: Dictionary) -> bool:
	if not data.has("story_events"): return true
	if not data.get("battle",{}) is Dictionary or not data.get("event_items",{}) is Dictionary: return false
	var value: Variant = data.story_events
	if not value is Dictionary or value.get("version")!=1 or not value.get("entries") is Dictionary or not value.get("receipts") is Dictionary: return false
	for receipt: Variant in value.receipts:
		if not receipt is String or value.receipts[receipt]!=true: return false
	for id: Variant in value.entries:
		if not id is String or CATALOG.definition(id).is_empty() or not CATALOG.definition(id).get("nodes") is Dictionary: return false
		var row: Variant = value.entries[id]
		if not row is Dictionary or not CATALOG.definition(id).nodes.has(row.get("node","")) or not row.get("flags") is Dictionary or not row.get("context") is Dictionary or not row.get("completed") is bool: return false
		if not row.get("resume",false) is bool: return false
		for key: String in ["accepted","seen_donkey","seen_merchant","await_enchanter","engine_owned","guide_shown","pickup_committed"]:
			if row.flags.has(key) and not row.flags[key] is bool: return false
		for key: String in ["bought_at_minutes","ghost_due_minutes"]:
			if row.flags.has(key) and not number(row.flags,key): return false
		for key: String in ["source_id","entry_role","trigger_mode"]:
			if not row.context.get(key) is String: return false
		if row.context.trigger_mode not in ["interact","on_game_start","on_game_time"]: return false
		var node: Dictionary = CATALOG.definition(id).nodes[row.node]
		if row.has("dialogue_history"):
			if not row.dialogue_history is Array: return false
			for reference: Variant in row.dialogue_history:
				if not reference is Dictionary or not reference.get("node") is String or not CATALOG.definition(id).nodes.has(reference.node): return false
				var source: Dictionary = CATALOG.definition(id).nodes[reference.node]
				if not CATALOG.CONFIGURATION.integer(reference.get("paragraph")) or int(reference.paragraph)>=source.get("paragraphs",[]).size(): return false
		if row.completed!=(node.type=="end"): return false
		for key: String in ["cursor","revision"]:
			if not (row.get(key) is int or row.get(key) is float) or not is_finite(float(row[key])) or float(row[key])<0.0 or float(row[key])!=floor(float(row[key])): return false
		if node.type=="dialogue" and int(row.cursor)>=node.paragraphs.size(): return false
		if node.type!="dialogue" and int(row.cursor)!=0: return false
		if not row.flags.get("await_battle",false) is bool: return false
		if row.flags.get("await_battle",false):
			var request: Dictionary = data.get("battle",{})
			if request.get("kind")!="story" or request.get("phase")!="loading" or request.get("event_id")!=id or request.get("battle_id")!=row.flags.get("pending_battle_id"): return false
		var rounds: Variant = row.flags.get("settled_rounds",0)
		if not (rounds is int or rounds is float) or float(rounds)!=floor(float(rounds)) or int(rounds) not in [0,1,2,3,4]: return false
		if id==BET and int(rounds)==4 and row.node not in ["gift","gift_reward","end"]: return false
		if id==OPENING and row.completed and data.get("event_items",{}).get("king_special_order",0)!=1: return false
	return true

static func new_entry(id: String, context: Dictionary) -> Dictionary:
	return {"node":CATALOG.definition(id).start,"cursor":0,"revision":0,"flags":{},"context":context.duplicate(true),"completed":false,"resume":false,"dialogue_history":[]}

## Save references to revealed prose, never text copies or unchosen branch predictions.
static func _remember_prose(id: String, row: Dictionary) -> void:
	var node: Dictionary = CATALOG.definition(id).nodes[row.node]
	var paragraphs: Array = node.get("paragraphs",[])
	if paragraphs.is_empty(): return
	if not row.has("dialogue_history"): row.dialogue_history=[]
	var references: Array = []
	if node.type=="dialogue":
		# An old save proves the prefix of its current node, but not earlier branches.
		var first: int = 0 if row.dialogue_history.is_empty() else int(row.cursor)
		for index: int in range(first,int(row.cursor)+1): references.append({"node":row.node,"paragraph":index})
	else:
		for index: int in paragraphs.size(): references.append({"node":row.node,"paragraph":index})
	# JSON reads paragraph indices as floats; Dictionary equality is not a receipt key.
	var same_tail: bool = row.dialogue_history.size()>=references.size()
	if same_tail:
		for index: int in references.size():
			var previous: Dictionary = row.dialogue_history[row.dialogue_history.size()-references.size()+index]
			if previous.node!=references[index].node or int(previous.paragraph)!=int(references[index].paragraph): same_tail=false; break
	if same_tail: return
	row.dialogue_history.append_array(references)

static func prose(data: Dictionary, id: String) -> String:
	var row := entry(data,id).duplicate(true)
	if row.is_empty(): return ""
	_remember_prose(id,row)
	var lines: Array[String] = []
	for reference: Dictionary in row.get("dialogue_history",[]):
		var node: Dictionary = CATALOG.definition(id).nodes[reference.node]
		var line := CATALOG.paragraph(id,node.paragraphs[int(reference.paragraph)])
		if not line.is_empty(): lines.append(line)
	return "\n\n".join(lines)

static func prepare_new_game(data: Dictionary) -> void:
	ensure(data).entries[OPENING]=new_entry(OPENING,{"source_id":"layout_summoning_hut","entry_role":"opening","trigger_mode":"on_game_start"})

static func due(data: Dictionary) -> bool:
	var engine := entry(data,ENGINE)
	return engine.get("flags",{}).get("engine_owned",false) and float(data.get("world_time",{}).get("total_minutes",0.0))>=float(engine.get("flags",{}).get("ghost_due_minutes",INF)) and not entry(data,GHOST).get("completed",false)

static func open(data: Dictionary, id: String, context: Dictionary, configured: Dictionary = {}) -> String:
	if CATALOG.definition(id).is_empty(): return "事件ID未注册："+id
	var configuration_error := CATALOG.CONFIGURATION.error(configured if not configured.is_empty() else CATALOG.parameters(),id)
	if not configuration_error.is_empty(): return "事件配置错误："+configuration_error
	if id.begins_with("AUX_") and id!="AUX_GRASS_ROVA": return "城市入口应展开其子事件，不直接执行。"
	if entry(data,id).get("completed",false): return "此事件已经完成。"
	if id==GHOST and not due(data): return "购买引擎后满4个游戏日才会出现鬼魂。"
	if id=="QST_GRASS_002" and (int(data.serial)<1 or not data.monsters.any(func(unit):return unit.position=="team")): return "需要先完成召唤并安排出战。"
	if id=="AUX_GRASS_ROVA" and "content_reward:"+LIBRARY not in data.completed: return "先完成图书馆的首次交谈。"
	var allowed := CATALOG.bindings(id,str(data.get("delivery_map_version","20261019")),configured).any(func(binding):return binding.source_id==context.get("source_id","") and binding.entry_role==context.get("entry_role",""))
	if context.get("trigger_mode","") in ["on_game_start","on_game_time"]:
		allowed=(id==OPENING and not entry(data,id).is_empty()) or (id==GHOST and due(data))
	if not allowed: return "该地点未绑定此事件或阶段。"
	var state := ensure(data)
	var newly_created: bool = not state.entries.has(id)
	if not state.entries.has(id): state.entries[id]=new_entry(id,context)
	var current: Dictionary = state.entries[id]
	if not newly_created: _remember_prose(id,current)
	var previous_role: String = "" if newly_created else current.context.get("entry_role","")
	current.context=context.duplicate(true)
	current.resume=false
	if id=="QST_GRASS_007" and current.node not in ["return_dialogue","reward"]:
		var role: String = context.get("entry_role","")
		current.flags["seen_"+role]=true
		if role!=previous_role or current.node not in ["donkey","merchant","donkey_choice","merchant_choice"]:
			current.node="merchant" if role=="merchant" else "donkey"
			current.cursor=0
	if id=="QST_GRASS_012" and current.flags.get("await_enchanter",false):
		if context.get("entry_role")!="return_city_enchanter": current.node="waiting"; current.cursor=0
		elif current.node not in ["enchanter","enchanter_reward"]: current.node="enchanter"; current.cursor=0
	if id=="QST_SIDE_002_001" and context.get("entry_role")=="clear_target" and not current.flags.get("accepted",false): return "请先向城主接取防卫预算委托。"
	_remember_prose(id,current)
	current.revision+=1
	return ""

static func number(parameters: Dictionary, key: String) -> bool:
	var value: Variant = parameters.get(key)
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0.0

static func missing(id: String, key: String) -> String:
	return "待配置：Content/Events/Current/parameters.json → "+id+" → "+key

static func candidates(data: Dictionary, stage: int) -> Array:
	var result: Array = []
	for unit: Dictionary in data.monsters:
		if unit.position=="pending" or not unit.get("recoverable",true) or unit.get("locked",false) or unit.id in data.battle.get("party_ids",[]): continue
		var facts: Dictionary = unit.get("event_traits",{})
		var fur: bool = facts.get("fur",unit.get("definition_id","")=="wolf")
		var flying: bool = facts.get("can_fly",false)
		var snake: bool = unit.get("definition_id","")=="snake" and int(unit.get("anatomy",{}).get("extra_limb_pairs",0))==0
		if (stage==1 and fur) or (stage==2 and flying) or (stage==3 and snake): result.append(unit)
	return result

static func action_error(data: Dictionary, id: String, command: Dictionary, parameters: Dictionary) -> String:
	var current := entry(data,id)
	if current.is_empty(): return "事件尚未开始。"
	var configuration_error := CATALOG.CONFIGURATION.error(parameters,id)
	if not configuration_error.is_empty(): return "事件配置错误："+configuration_error
	var p: Dictionary = parameters.get(id,{})
	var op: String = command.get("op","")
	if op not in CATALOG.OPERATIONS: return "未注册的事件操作："+op
	if current.flags.get("await_battle",false): return "正在等待已提交的战斗结果。"
	if op in ["money","require_money"] and not number(p,str(command.get("parameter",""))): return missing(id,str(command.get("parameter","")))
	if op=="both_seen" and not (current.flags.get("seen_donkey",false) and current.flags.get("seen_merchant",false)): return "需要先发现老驴和商人，发现顺序不限。"
	if op=="require_role" and current.context.get("entry_role","")!=command.role: return "请抵达对应地点的阶段入口后交付。"
	if op in ["attack_check","shell_reward"]:
		if not number(p,"attack_threshold"): return missing(id,"attack_threshold")
		if op=="shell_reward":
			if not number(p,"magic_reward"): return missing(id,"magic_reward")
			if not data.monsters.any(func(unit):return unit.position in ["team","warehouse"] and float(unit.attack)>float(p.attack_threshold)): return "当前没有单只攻击力高于阈值的自有怪物。"
	if op=="buy_engine":
		if not number(p,"purchase_cost"): return missing(id,"purchase_cost")
		if current.flags.get("engine_owned",false): return "引擎已经购买。"
		if int(data.array_stage)>=4: return "召唤阵已经达到当前支持的最大圈数，不能扣费购买。"
		if float(data.magic)<float(p.purchase_cost): return "魔力不足。"
	if op=="pickup" and (not p.get("pickup_item_id") is String or str(p.get("pickup_item_id","")).strip_edges().is_empty()): return missing(id,"pickup_item_id（具体物品暂时搁置）")
	if op=="sacrifice":
		if int(command.stage)==1 and not number(p,"first_magic_reward"): return missing(id,"first_magic_reward")
		if candidates(data,int(command.stage)).size()<int(command.stage): return "没有足够的合格、可回收且未锁定怪物。"
	if op=="battle":
		if id=="QST_GRASS_012" and current.flags.get("await_enchanter",false): return "已接取回城路线，不能改选直接解决。"
		var setting: Dictionary = p.get("battles",{}).get(command.branch,{})
		if id=="QST_SIDE_002_001" and (not setting.get("source_id") is String or setting.get("source_id","").is_empty()): return missing(id,"battles.clear.source_id（指定清剿地点）")
		var error := battle_setting_error(setting,command.get("mode","party"))
		if not error.is_empty(): return missing(id,"battles."+str(command.branch)+"."+error)
		if not str(setting.get("source_id","")).is_empty() and setting.source_id!=current.context.get("source_id",""): return "请先抵达指定清剿地点："+str(setting.source_id)
		if command.get("mode","party")=="party" and not data.monsters.any(func(unit):return unit.position=="team"): return "请先安排出战队伍。"
		if command.get("restriction","")=="no_large" and data.monsters.any(func(unit):return unit.position=="team" and unit.get("mode","") in ["giant","ultra"]): return "矿井禁止大型怪物出战，请先调整队伍；不会删除怪物。"
		if command.has("reward_preset") and reward_record(p.get("reward_presets",{}).get(command.reward_preset)).is_empty(): return missing(id,"reward_presets."+str(command.reward_preset)+"（有效的正式怪物记录JSON路径）")
	if op=="monster_reward" and current.flags.get("reward_record",{}).is_empty(): return missing(id,"reward_presets（需在开战前绑定并冻结奖励预设）")
	if op=="bet":
		var round_index := int(current.flags.get("settled_rounds",0))
		if round_index>=4: return "四次赌局已结算，只能处理待赠礼。"
		var rounds: Array = p.get("rounds",[])
		if rounds.size()!=4: return missing(id,"rounds（必须有四轮手填阵容）")
		var error := battle_setting_error(rounds[round_index],"spectator")
		if not error.is_empty(): return missing(id,"rounds[%d].%s" % [round_index,error])
		if p.get("loss_policy")!="lose_stake": return missing(id,"loss_policy（失败支付尚未确认，不执行真实支付）")
		if float(data.magic)<float([10,20,50,100][round_index]): return "魔力不足以支付本轮本金。"
	return ""

static func battle_setting_error(setting: Variant, mode: String) -> String:
	if not setting is Dictionary: return "配置必须为字典"
	if not setting.get("battle_map_id") is String or MAPS.map_data(setting.get("battle_map_id",""),"20261019").get("kind","")!="battle": return "battle_map_id"
	var settings := load("res://Content/Maps/FrontierEditor_20261019/Runtime/BattleSettings.tres") as DeliveryBattleSettings
	for key: String in (["side_a_roster","side_b_roster"] if mode=="spectator" else ["enemy_config_id"]):
		if not setting.get(key) is String: return key
		var reason := settings.availability_error(str(setting[key]))
		if not reason.is_empty(): return key+"（"+reason+"）"
	return ""

static func advance(data: Dictionary, parameters: Dictionary, id: String, choice_id: String, revision: int, selected_ids: Array = []) -> String:
	var current := entry(data,id)
	if current.is_empty() or current.completed or int(current.revision)!=revision: return "事件进度已变化，请刷新后重试。"
	var node: Dictionary = CATALOG.definition(id).nodes[current.node]
	if node.type=="dialogue":
		if choice_id!="next": return "对白步骤不接受该选项。"
		_remember_prose(id,current)
		if int(current.cursor)+1<node.paragraphs.size(): current.cursor+=1
		else: _goto(data,id,str(node.next))
	else:
		var selected: Dictionary = {}
		if node.type=="action" and choice_id=="confirm": selected={"action":node.action}
		elif node.type=="choice":
			for option: Dictionary in node.options:
				if option.id==choice_id: selected=option; break
		if selected.is_empty(): return "该节点不存在此选项。"
		var command: Dictionary = selected.get("action",{})
		var error := action_error(data,id,command,parameters)
		if not error.is_empty(): return error
		var op: String = command.get("op","")
		var p: Dictionary = parameters.get(id,{})
		var receipt := id+":"+str(current.node)+":"+choice_id
		if ensure(data).receipts.has(receipt) and op not in ["close","both_seen","require_role","battle","bet"]: return "该结果已经提交。"
		if op=="close": return ""
		_remember_prose(id,current)
		match op:
			"flag": current.flags[command.flag]=command.value
			"appointment":
				if not data.has("event_items"): data.event_items={}
				data.event_items["king_special_order"]=1
				_goto(data,id,"end")
			"money": data.magic+=float(p[command.parameter])
			"attack_check":
				var passed: bool = data.monsters.any(func(unit):return unit.position in ["team","warehouse"] and float(unit.attack)>float(p.attack_threshold))
				_goto(data,id,command.passed if passed else command.failed)
			"shell_reward":
				data.magic+=float(p.magic_reward)
				var reward_error := _reward(data,id,id,{"single_owned_attack_check_passed":true})
				if not reward_error.is_empty(): return reward_error
			"reward":
				var facts := {"dialogue_completed":true,"returned_to_giver":current.context.get("entry_role")=="city_center","battle_id":current.flags.get("last_battle_id",""),"settled_rounds":current.flags.get("settled_rounds",0)}
				var reward_error := _reward(data,id,command.reward_key,facts)
				if not reward_error.is_empty(): return reward_error
			"buy_engine":
				data.magic-=float(p.purchase_cost)
				data.array_stage+=1
				data.layout.stage=data.array_stage
				current.flags.engine_owned=true
				current.flags.bought_at_minutes=float(data.world_time.total_minutes)
				current.flags.ghost_due_minutes=float(data.world_time.total_minutes)+4.0*1440.0
			"pickup":
				if not data.has("event_items"): data.event_items={}
				data.event_items[p.pickup_item_id]=int(data.event_items.get(p.pickup_item_id,0))+1
				current.flags.pickup_committed=true
			"sacrifice":
				var stage := int(command.stage)
				var unique := {}
				var eligible: Array = candidates(data,stage).map(func(unit):return unit.id)
				for unit_id: Variant in selected_ids:
					if not unit_id is String or unit_id not in eligible or unique.has(unit_id): return "献祭对象重复、不合格或已不可用。"
					unique[unit_id]=true
				if unique.size()!=stage or data.monsters.size()-stage<1: return "必须选择本阶段要求的数量，且献祭后至少保留一只怪物。"
				data.monsters=data.monsters.filter(func(unit):return unit.id not in unique)
				if stage==1: data.magic+=float(p.first_magic_reward)
				else:
					var reward_error := _reward(data,id,id+":stage_"+str(stage),{"sacrifice_committed":true,"stage":"stage_"+str(stage)})
					if not reward_error.is_empty(): return reward_error
				current.flags.sacrifices_settled=stage
			"battle","bet":
				var branch: String = command.get("branch",choice_id)
				var config: Dictionary = p.get("battles",{}).get(branch,{})
				config=config.duplicate(true)
				if command.has("reward_preset"): config.reward_record=reward_record(p.get("reward_presets",{}).get(command.reward_preset))
				if op=="bet":
					var round_index := int(current.flags.get("settled_rounds",0))
					config=p.rounds[round_index].duplicate(true)
					current.flags.bet_side=int(command.side)
					current.flags.bet_stake=[10,20,50,100][round_index]
					data.magic-=float(current.flags.bet_stake)
				var error_battle := _begin_battle(data,id,command,config,branch)
				if not error_battle.is_empty(): return error_battle
			"monster_reward":
				var record: Dictionary = current.flags.reward_record.duplicate(true)
				record.id="story_reward_"+id
				record.position="warehouse"
				if not record.has("traits"): record.traits=[]
				if data.monsters.any(func(unit):return unit.id==record.id): return "该奖励怪物已经接收。"
				data.monsters.append(record)
		if op not in ["attack_check","battle","bet"]:
			var next: String = selected.get("next",command.get("next",""))
			if not next.is_empty(): _goto(data,id,next)
		if op not in ["both_seen","require_role","battle","bet","attack_check"]: ensure(data).receipts[receipt]=true
	_remember_prose(id,current)
	current.revision+=1
	return ""

static func _goto(data: Dictionary, id: String, node: String) -> void:
	var current := entry(data,id)
	current.node=node
	current.cursor=0
	_remember_prose(id,current)
	if CATALOG.definition(id).nodes[node].type=="end": current.completed=true; current.resume=false

static func _reward(data: Dictionary, id: String, key: String, facts: Dictionary) -> String:
	return REWARDS.apply(data,key,"story:"+id+":"+str(entry(data,id).node),facts)

static func _begin_battle(data: Dictionary, id: String, command: Dictionary, config: Dictionary, branch: String) -> String:
	if not data.battle.is_empty(): return "已有待处理战斗。"
	var current := entry(data,id)
	var world: Dictionary = data.worlds.get("frontier_layout",{})
	if world.is_empty(): return "地图位置尚未保存。"
	var mode: String = "spectator" if command.op=="bet" else str(command.get("mode","party"))
	var party: Array = [] if mode=="spectator" else data.monsters.filter(func(unit):return unit.position=="team").map(func(unit):return unit.id)
	var request_id := "story_%s_%d" % [id,int(current.revision)]
	if command.has("reward_preset"):
		current.flags.reward_record=config.get("reward_record",{}).duplicate(true)
	data.battle={"battle_id":request_id,"request_id":request_id,"phase":"loading","kind":"story","map_id":"frontier_layout","source_map_id":"frontier_layout","location_id":current.context.source_id,"return_position":world.player.duplicate(),"battle_map_id":config.battle_map_id,"enemy_config_id":config.get("side_b_roster","") if mode=="spectator" else config.get("enemy_config_id",""),"party_ids":party,"event_id":id,"combat_mode":mode,"side_a_roster":config.get("side_a_roster",""),"side_b_roster":config.get("side_b_roster",""),"story_branch":branch,"story_won":command.get("won",""),"story_lost":command.get("lost",str(current.node)),"reward_preset":command.get("reward_preset",""),"clear_location_on_victory":id=="QST_SIDE_002_001"}
	var settings := load("res://Content/Maps/FrontierEditor_20261019/Runtime/BattleSettings.tres") as DeliveryBattleSettings
	data.battle.enemy_definitions_snapshot=Array(settings.enemy_rosters[data.battle.enemy_config_id].definitions)
	if mode=="spectator": data.battle.side_a_definitions_snapshot=Array(settings.enemy_rosters[config.side_a_roster].definitions)
	if id=="QST_GRASS_008": data.battle.enemy_anatomy={"scale":3.0}
	current.flags.await_battle=true
	current.flags.pending_battle_id=request_id
	return ""

static func reward_record(path: Variant) -> Dictionary:
	if not path is String or not path.begins_with("res://") or not path.ends_with(".json") or not FileAccess.file_exists(path): return {}
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not record is Dictionary or not FACTORY.valid_record(record): return {}
	for key: String in ["name","form","color"]:
		if not record.get(key) is String or record[key].is_empty(): return {}
	if record.form not in ["人形","兽形","蛇形"] or not Color.html_is_valid(record.color): return {}
	for key: String in ["hp","attack","armor","speed"]:
		var value: Variant = record.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value)<0: return {}
	if record.has("traits"):
		if not record.traits is Array: return {}
		for ability_tag: Variant in record.traits:
			if not ability_tag is String: return {}
	return record

static func cancel_battle(data: Dictionary, request: Dictionary) -> void:
	if request.get("kind")!="story": return
	var current := entry(data,request.event_id)
	if current.is_empty() or current.flags.get("pending_battle_id")!=request.get("battle_id"): return
	current.flags.await_battle=false
	# A paid, interrupted bet is not a loss or a new bet. Preserve its ledger for adjudication.
	if request.event_id==BET: _goto(data,BET,"unresolved")
	current.resume=true
	current.revision+=1

static func battle_result(data: Dictionary, request: Dictionary, result: Dictionary) -> String:
	if request.get("kind")!="story": return ""
	var id: String = request.event_id
	var current := entry(data,id)
	if current.is_empty() or current.flags.get("pending_battle_id","")!=result.battle_id: return "事件战斗回执已过期或不匹配。"
	current.flags.await_battle=false
	current.flags.last_battle_id=result.battle_id
	if id==BET:
		var winner: int = result.get("winner_faction",-1)
		if winner not in [0,1] or result.outcome not in ["victory","defeat"]:
			_goto(data,id,"unresolved")
		else:
			if winner==int(current.flags.bet_side): data.magic+=float(current.flags.bet_stake)*2.0
			current.flags.settled_rounds=int(current.flags.get("settled_rounds",0))+1
			_goto(data,id,"gift" if current.flags.settled_rounds==4 else "again")
	else:
		var won: bool = result.outcome=="victory" or (request.get("combat_mode")=="spectator" and result.outcome=="defeat")
		if won:
			current.flags.reward_preset=request.get("reward_preset","")
			_goto(data,id,str(request.story_won))
		else: _goto(data,id,str(request.story_lost))
	current.resume=not current.completed and id!="QST_SIDE_002_001"
	current.revision+=1
	return ""
