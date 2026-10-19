extends RefCounted
## Pure state machine. Only the application host may acknowledge real operations.
const CONFIG_PATH := "res://Content/Events/GrasslandEvents.json"
const SAVE_KEY := "story_events"
const TASKS = preload("res://Scripts/Application/NewPlayerTasks.gd")
var config: Dictionary = {}
var definitions: Dictionary = {}

func _init() -> void:
	configure(JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)))

func configure(value: Variant) -> String:
	if not value is Dictionary or value.get("version") != 1 or not value.get("events") is Array or not value.get("bindings") is Dictionary: return "事件配置格式无效。"
	for key: String in ["rewards","battles","monster_fields"]:
		if not value.bindings.get(key) is Dictionary: return "事件绑定表缺少："+key
	if not value.bindings.get("bet_rounds") is Array or value.bindings.bet_rounds.size()!=4: return "赌局必须保留四轮配置。"
	var candidate := {}
	for event: Variant in value.events:
		if not event is Dictionary or not event.get("id") is String or event.id.is_empty() or candidate.has(event.id): return "事件ID为空或重复。"
		if not strings(event.get("entries")) or event.entries.is_empty() or not event.get("operations") is Dictionary: return "事件入口或操作配置无效。"
		for branch: Variant in event.operations:
			var op: Variant = event.operations[branch]
			if not branch is String or not op is Dictionary or op.get("kind") not in ["local","transaction","purchase","sacrifice","battle","spectator","bet"] or not op.get("next") is String: return "事件操作配置无效。"
			if not strings(op.get("from",["available"])) or op.get("next","").is_empty(): return "事件阶段配置无效。"
			for key: String in ["reward","battle","entry","guard"]:
				if op.has(key) and (not op[key] is String or op[key].is_empty()): return "事件操作引用无效。"
		candidate[event.id] = event.duplicate(true)
	config = value.duplicate(true)
	definitions = candidate
	return ""

static func initial_progress() -> Dictionary:
	return {"version":1,"sequence":0,"entries":{},"receipts":{},"queue":[],"clock":{"ready":false,"day":0.0}}

static func ensure(data: Dictionary) -> Dictionary:
	if not data.has(SAVE_KEY): data[SAVE_KEY] = initial_progress()
	return data[SAVE_KEY]

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0

static func integer(value: Variant) -> bool:
	return number(value) and float(value)==floorf(float(value)) and float(value)<=2147483647

static func strings(value: Variant) -> bool:
	if not value is Array: return false
	var seen := {}
	for item: Variant in value:
		if not item is String or item.is_empty() or seen.has(item): return false
		seen[item] = true
	return true

static func valid_progress(data: Dictionary) -> bool:
	if not data.has(SAVE_KEY): return true
	var p: Variant = data[SAVE_KEY]
	if not p is Dictionary or p.get("version")!=1 or not integer(p.get("sequence")) or not p.get("entries") is Dictionary or not p.get("receipts") is Dictionary or not strings(p.get("queue")): return false
	var clock: Variant = p.get("clock")
	if not clock is Dictionary or not clock.get("ready") is bool or not number(clock.get("day")): return false
	for id: Variant in p.entries:
		var e: Variant = p.entries[id]
		if not id is String or not e is Dictionary: return false
		for key: String in ["stage","entry","conversation","route"]:
			if not e.get(key) is String: return false
		if not strings(e.get("seen")) or not e.get("pending") is Dictionary or not e.get("completed") is bool or not integer(e.get("rounds")) or e.rounds>4: return false
		for key: String in ["triggered","defense_won"]:
			if not e.get(key) is bool: return false
		if e.completed != (e.stage=="complete"): return false
		if e.has("purchased_day") and (not number(e.purchased_day) or not number(e.get("due_day")) or float(e.due_day)!=float(e.purchased_day)+4.0): return false
		if not e.pending.is_empty() and (not _valid_request(e.pending) or e.pending.event_id!=id or e.pending.stage!=e.stage): return false
	for key: Variant in p.receipts:
		var receipt: Variant = p.receipts[key]
		if not key is String or not receipt is Dictionary or receipt.get("request_id")!=key or not receipt.get("event_id") is String: return false
	for id: String in p.queue:
		if not p.entries.has(id) or p.entries[id].completed or p.entries[id].triggered: return false
	return true

static func _valid_request(r: Dictionary) -> bool:
	for key: String in ["request_id","event_id","stage","branch","kind","next"]:
		if not r.get(key) is String or r[key].is_empty(): return false
	if r.kind not in ["transaction","purchase","sacrifice","battle","spectator","bet"]: return false
	return r.get("operation") is Dictionary and r.get("payload") is Dictionary and r.get("plan") is Dictionary

func entry(data: Dictionary, id: String) -> Dictionary:
	var p := ensure(data)
	if not p.entries.has(id): p.entries[id] = {"stage":"available","seen":[],"entry":"","conversation":"","route":"","pending":{},"completed":false,"rounds":0,"triggered":false,"defense_won":false}
	return p.entries[id]

func _token(p: Dictionary, prefix: String) -> String:
	p.sequence += 1
	return prefix+"_"+str(p.sequence)

func _summoned_party(data: Dictionary) -> bool:
	var facts := {"locations":[],"summon_batches":[],"party_size":0,"victories":[]}
	TASKS._capture_reliable_facts(data,facts)
	return not facts.summon_batches.is_empty() and data.get("monsters",[]).any(func(m): return m.get("position")=="team")

func reconcile(data: Dictionary, world_entered: bool = false) -> void:
	var p := ensure(data)
	var defense: Dictionary=p.entries.get("QST_SIDE_002_001",{})
	if defense.get("stage")=="active" and not defense.get("defense_won",false):
		var target: String=config.bindings.battles.get("defense",{}).get("site_id","hex_camp_mv9za92d_38" if config.bindings.get("approved_failure_rules",false) else "")
		if not target.is_empty():
			for result: Dictionary in data.get("battle_results",{}).values():
				if result.get("outcome")=="victory" and result.get("map_id")=="hex_frontier_20261019" and result.get("site_id")==target: defense.defense_won=true; break
	if world_entered and _summoned_party(data):
		var tree := entry(data,"QST_GRASS_002")
		if not tree.completed and not tree.triggered and "QST_GRASS_002" not in p.queue: p.queue.append("QST_GRASS_002")
	var engine: Dictionary = p.entries.get("QST_GRASS_014",{})
	if p.clock.ready and engine.has("due_day") and float(p.clock.day)>=float(engine.due_day):
		var ghost := entry(data,"QST_GRASS_015")
		if not ghost.completed and not ghost.triggered and "QST_GRASS_015" not in p.queue: p.queue.append("QST_GRASS_015")

func set_game_day(data: Dictionary, day: float) -> String:
	if not number(day): return "游戏时间无效。"
	var clock: Dictionary = ensure(data).clock
	if clock.ready and day<float(clock.day): return "游戏时间不得倒退。"
	clock.ready = true
	clock.day = day
	reconcile(data)
	return ""

func ready_events(data: Dictionary, safe: bool) -> Array:
	if not safe: return []
	return data.get(SAVE_KEY,{}).get("queue",[]).duplicate()

func open(data: Dictionary, id: String, entrance: String, safe: bool) -> Dictionary:
	if not definitions.has(id): return _error("未知事件ID。")
	if not safe: return _error("当前阶段不可开始事件演出。")
	if entrance not in definitions[id].entries: return _error("事件入口未登记。")
	var e := entry(data,id)
	if e.completed: return _error("事件已完成。")
	if e.stage=="await_policy": return _error("此分支的后续处理规则待配置。")
	if id=="QST_GRASS_002" and not _summoned_party(data): return _error("需要完成召唤安置并安排出战。")
	if id=="QST_GRASS_015" and not e.triggered and id not in ensure(data).queue: return _error("购买引擎尚未满4个游戏日。")
	if entrance not in e.seen: e.seen.append(entrance)
	e.entry = entrance
	e.conversation = _token(ensure(data),"dialogue")
	e.triggered = true
	ensure(data).queue.erase(id)
	return {"ok":true,"event":view(data,id)}

func view(data: Dictionary, id: String) -> Dictionary:
	if not definitions.has(id): return {}
	var e: Dictionary = data.get(SAVE_KEY,{}).get("entries",{}).get(id,{})
	var state: Dictionary = e.duplicate(true)
	state["id"] = id
	state["title"] = definitions[id].title
	# Do not return future sacrifice conditions or plans to the presentation layer.
	state["branches"] = []
	var stage: String = e.get("stage","available")
	if not e.get("completed",false) and e.get("pending",{}).is_empty():
		for branch: String in definitions[id].operations:
			var op: Dictionary = definitions[id].operations[branch]
			if stage in op.get("from",["available"]):
				if op.has("entry") and op.entry!=e.get("entry",""): continue
				state.branches.append(branch)
	state.erase("pending")
	state["pending_request_id"] = e.get("pending",{}).get("request_id","")
	return state

func _error(message: String) -> Dictionary:
	return {"ok":false,"error":message}

func _reward(key: String) -> Variant:
	return config.bindings.get("rewards",{}).get(key)

func _reward_error(value: Variant) -> String:
	if not value is Dictionary or not value.has("magic") or not integer(value.magic): return "奖励魔力或奖励内容待配置。"
	for key: Variant in value:
		if key not in ["magic","runes","relics","items","monsters"]: return "奖励类型无效。"
	if not TASKS._valid_reward({"magic":value.magic,"runes":value.get("runes",[]),"relics":value.get("relics",[])}): return "奖励ID或类型无效。"
	for key: String in ["items","monsters"]:
		var list: Variant = value.get(key,[])
		if not list is Array: return "物品或怪物奖励必须是数组。"
		for item: Variant in list:
			if not item is Dictionary or not item.get("id") is String or item.id.is_empty() or not integer(item.get("count")) or int(item.count)<1: return "物品或怪物奖励ID及数量待配置。"
	return ""

func _battle_error(value: Variant) -> String:
	if not value is Dictionary or not value.get("battle_map_id") is String or value.battle_map_id.is_empty(): return "战斗场景待配置。"
	if not value.get("enemy_config_id") is String or value.enemy_config_id.is_empty(): return "敌军预设待配置。"
	return ""

func _field(m: Dictionary, name: String) -> Variant:
	var key: Variant = config.bindings.get("monster_fields",{}).get(name)
	return m.get(key) if key is String and not key.is_empty() else null

func _owned(data: Dictionary) -> Array:
	return data.get("monsters",[]).filter(func(m): return m.get("position") in ["warehouse","team"])

func _guard(data: Dictionary, id: String, e: Dictionary, op: Dictionary, payload: Dictionary) -> String:
	var guard: String = op.get("guard","")
	var owned := _owned(data)
	match guard:
		"summoned_party":
			if not _summoned_party(data): return "需要完成召唤安置并安排出战。"
		"defense_active":
			if e.defense_won: return "清剿目标已完成，请返回城主。"
		"defense_won":
			if not e.defense_won or e.entry!="center": return "需赢得指定清剿战斗并返回城主。"
		"both_seen":
			if "donkey" not in e.seen or "merchant" not in e.seen: return "需要先发现老驴和商人。"
		"attack":
			var threshold: Variant = config.bindings.get("attack_threshold")
			if not number(threshold): return "单只攻击力阈值待配置。"
			if not owned.any(func(m): return number(_field(m,"attack")) and float(_field(m,"attack"))>float(threshold)): return "没有攻击力高于阈值的持有怪物，或正式攻击字段未绑定。"
		"small_party":
			var team := owned.filter(func(m): return m.position=="team")
			if team.is_empty(): return "出战队伍不能为空。"
			for m: Dictionary in team:
				if not _field(m,"large") is bool: return "正式大型怪物字段未绑定。"
				if _field(m,"large"): return "矿井禁止大型怪物出战，请调整队伍。"
		"direct_route","no_route":
			if not e.route.is_empty(): return "已锁定回城路线。"
		"engine":
			if not ensure(data).clock.ready: return "权威游戏时间服务尚未接入。"
			var maximum: Variant = config.bindings.get("engine_max_stage")
			if not integer(maximum) or int(maximum)<1: return "召唤阵扩圈上限待配置。"
			if int(data.get("array_stage",1))>=int(maximum): return "召唤阵已达扩圈上限。"
			if float(data.get("magic",0))<100: return "魔力不足100。"
		"bet":
			if e.rounds>=4: return "四轮赌局已经结束。"
			if config.bindings.get("bet_loss_policy")!="lose_stake" or config.bindings.get("bet_draw_policy") not in ["hold_for_resolution","refund_stake_without_round"] or config.bindings.get("bet_abort_policy") not in ["hold_for_resolution","refund_stake_without_round"]: return "失败支付、平局和中止处理尚待确认，禁止真实下注。"
			var rounds: Variant = config.bindings.get("bet_rounds")
			if not rounds is Array or rounds.size()!=4: return "四轮赌局配置缺失。"
			var round_data: Variant = rounds[int(e.rounds)]
			if not round_data is Dictionary or round_data.get("stake")!=[10,20,50,100][int(e.rounds)]: return "赌注配置无效。"
			for side: String in ["one","two"]:
				var error := _battle_error(round_data.get(side))
				if not error.is_empty(): return "赌局双方阵容待手填："+error
			if float(data.get("magic",0))<float(round_data.stake): return "下注魔力不足。"
	if op.kind=="sacrifice":
		if payload.get("confirmed")!=true: return "献祭需要明确确认不可逆消耗。"
		var selected: Variant = payload.get("monster_ids")
		if not strings(selected) or selected.size()!=int(op.count): return "献祭数量不符或实例重复。"
		if owned.size()-selected.size()<1: return "献祭后必须至少保留一只持有怪物。"
		for instance_id: String in selected:
			var matches := owned.filter(func(m): return m.get("id")==instance_id)
			if matches.size()!=1: return "献祭实例已不存在或尚未安置。"
			var m: Dictionary = matches[0]
			for event: Dictionary in data.get(SAVE_KEY,{}).get("entries",{}).values():
				if event.get("pending",{}).get("plan",{}).get("frozen_rosters",{}).get("left",[]).any(func(unit):return unit.id==instance_id): return "所选怪物被未结算的事件战斗占用。"
			if not m.get("recoverable",true) or m.get("locked",false) or instance_id in data.get("battle",{}).get("party_ids",[]): return "所选怪物不可回收、已锁定或被战斗占用。"
			if op.trait=="limbless_snake":
				if _field(m,"snake")!=true or not integer(_field(m,"hands")) or not integer(_field(m,"feet")) or _field(m,"hands")!=0 or _field(m,"feet")!=0: return "需要正式字段确认蛇类且无手无足。"
			elif _field(m,op.trait)!=true: return "正式怪物特征未绑定或不满足当前献祭要求。"
	return ""

func act(data: Dictionary, id: String, branch: String, conversation: String, payload: Dictionary = {}) -> Dictionary:
	if not definitions.has(id): return _error("未知事件。")
	var e := entry(data,id)
	if e.completed or conversation.is_empty() or conversation!=e.conversation: return _error("事件已完成或对话会话过期。")
	if not e.pending.is_empty():
		if id=="QST_SIDE_003_001" and branch=="reward_retry": return {"ok":true,"request":e.pending.duplicate(true)}
		if e.pending.branch==branch and e.pending.payload==payload: return {"ok":true,"request":e.pending.duplicate(true)}
		return _error("已有待完成请求，请恢复原请求。")
	if branch in ["leave","close"]:
		e.conversation = ""
		return {"ok":true}
	var op: Dictionary = definitions[id].operations.get(branch,{})
	if op.is_empty() or e.stage not in op.get("from",["available"]): return _error("当前阶段不允许此分支。")
	if op.has("entry") and e.entry!=op.entry: return _error("请从对应入口继续。")
	var error := _guard(data,id,e,op,payload)
	if not error.is_empty(): return _error(error)
	if op.kind=="local":
		e.stage = op.next
		e.completed = e.stage=="complete"
		if op.has("route"): e.route = op.route
		e.conversation = "" if e.completed else e.conversation
		return {"ok":true}
	var plan := {}
	if op.has("reward"):
		var reward: Variant = _reward(op.reward)
		error = _reward_error(reward)
		if not error.is_empty(): return _error(error+" 来源："+op.reward)
		plan["reward"] = reward.duplicate(true)
	if op.has("battle"):
		var battle_config: Variant = config.bindings.get("battles",{}).get(op.battle)
		error = _battle_error(battle_config)
		if not error.is_empty(): return _error(error+" 来源："+op.battle)
		plan["battle"] = battle_config.duplicate(true)
		if op.kind=="spectator" and _battle_error(battle_config.get("other_side")).length()>0: return _error("观战另一方阵容待配置。")
	if op.kind in ["battle","spectator"]:
		plan["mode"] = "player" if op.kind=="battle" else "spectator"
		plan["deploy_player"] = op.kind=="battle"
		# The helped monster is a reward, never an extra ally in the player roster.
		plan["include_helped_ally"] = false
	if op.kind=="battle" and not data.get("monsters",[]).any(func(m): return m.get("position")=="team"): return _error("玩家出战队伍不能为空。")
	if op.kind=="purchase": plan = {"cost":100,"from_stage":data.array_stage,"to_stage":int(data.array_stage)+1}
	if op.kind=="bet": plan = {"round":int(e.rounds)+1,"stake":[10,20,50,100][int(e.rounds)],"side":branch,"rosters":config.bindings.bet_rounds[int(e.rounds)].duplicate(true)}
	plan["source_site_id"]=e.get("source_site_id","")
	var request := {"request_id":_token(ensure(data),"story"),"event_id":id,"stage":e.stage,"branch":branch,"kind":op.kind,"next":op.next,"operation":op.duplicate(true),"payload":payload.duplicate(true),"plan":plan}
	if op.kind in ["battle","spectator"]: request["battle_id"] = request.request_id+"_battle"
	e.pending = request
	return {"ok":true,"request":request.duplicate(true)}

func pending_request(data: Dictionary, id: String) -> Dictionary:
	return data.get(SAVE_KEY,{}).get("entries",{}).get(id,{}).get("pending",{}).duplicate(true)

func check_receipt(data: Dictionary, receipt: Dictionary) -> String:
	for key: String in ["request_id","event_id","stage","branch","kind","outcome"]:
		if not receipt.get(key) is String or receipt[key].is_empty(): return "回执关联字段不完整。"
	var p := ensure(data)
	if p.receipts.has(receipt.request_id):
		return "" if p.receipts[receipt.request_id]==receipt else "同一请求收到冲突回执。"
	var r := pending_request(data,receipt.event_id)
	if r.is_empty(): return "没有匹配的待处理请求。"
	for key: String in ["request_id","event_id","stage","branch","kind"]:
		if r[key]!=receipt[key]: return "回执与当前请求不匹配。"
	if r.has("battle_id"):
		if receipt.get("battle_id")!=r.battle_id or receipt.outcome not in ["victory","defeat","retreat","interrupted","load_failed","draw"]: return "战斗ID或真实结束结果无效。"
		if r.kind in ["spectator","bet"] and receipt.outcome in ["victory","defeat"] and receipt.get("winner") not in ["one","two"]: return "观战必须提供真实获胜方。"
	else:
		if receipt.outcome not in (["success","consumed"] if r.kind=="sacrifice" else ["success"]) or receipt.get("committed")!=true: return "事务尚未成功提交。"
	return ""

func commit_receipt(data: Dictionary, receipt: Dictionary) -> String:
	var error := check_receipt(data,receipt)
	if not error.is_empty(): return error
	var p := ensure(data)
	if p.receipts.has(receipt.request_id): return ""
	var e := entry(data,receipt.event_id)
	var r: Dictionary = e.pending
	if r.kind in ["battle","spectator"]:
		# Unknown draw/abort accounting stays pending and cannot consume a round.
		if r.kind=="spectator" and receipt.outcome not in ["victory","defeat"]:
			if not config.bindings.get("approved_failure_rules",false): return "观战平局或中止处理待确认，保留原请求。"
			if r.operation.kind=="bet":
				var refund: Dictionary=r.duplicate(true)
				refund.request_id=r.request_id+"_refund"; refund.kind="transaction"; refund.erase("battle_id")
				refund.plan["refund"]=true; refund.plan["battle_outcome"]=receipt.duplicate(true)
				refund.plan["reward"]={"magic":int(r.plan.stake),"runes":[],"relics":[]}
				e.pending=refund
			else: e.pending={}; e.stage="available"
			p.receipts[receipt.request_id]=receipt.duplicate(true)
			return ""
		if r.kind=="battle" and receipt.outcome!="victory":
			e.pending = {}
			if receipt.event_id=="QST_GRASS_006": e.stage = "picked_up" if config.bindings.get("approved_failure_rules",false) else "await_policy"
		elif r.operation.get("effect","")=="defense_won":
			e.defense_won = true
			e.pending = {}
		elif r.operation.kind=="bet" or r.plan.has("reward"):
			var followup: Dictionary = r.duplicate(true)
			followup.request_id = r.request_id+"_settle"
			followup.kind = "transaction"
			followup.erase("battle_id")
			followup.plan["battle_outcome"] = receipt.duplicate(true)
			if r.operation.kind=="bet":
				var won: bool = receipt.winner==r.plan.side
				followup.plan["reward"] = {"magic":int(r.plan.stake)*2 if won else 0,"runes":[],"relics":[]}
			e.pending = followup
		else:
			e.pending = {}
			e.stage = r.next
	else:
		if r.kind=="sacrifice" and receipt.outcome=="consumed":
			var reward_request: Dictionary = r.duplicate(true)
			reward_request.request_id = r.request_id+"_reward"
			reward_request.kind = "transaction"
			reward_request.plan["consumed_ids"] = r.payload.monster_ids.duplicate()
			e.pending = reward_request
			p.receipts[receipt.request_id] = receipt.duplicate(true)
			return ""
		if r.kind=="bet":
			var watching: Dictionary = r.duplicate(true)
			watching.request_id = r.request_id+"_watch"
			watching.kind = "spectator"
			watching["battle_id"] = r.request_id+"_battle"
			watching.plan["mode"] = "spectator"
			watching.plan["deploy_player"] = false
			watching.plan["include_helped_ally"] = false
			e.pending = watching
			p.receipts[receipt.request_id] = receipt.duplicate(true)
			return ""
		e.pending = {}
		e.stage = r.next
		if r.kind=="purchase":
			if not p.clock.ready: return "权威时间未就绪。"
			e["purchased_day"] = p.clock.day
			e["due_day"] = float(p.clock.day)+4.0
		if r.operation.kind=="bet" and not r.plan.get("refund",false):
			e.rounds += 1
			if e.rounds==4: e.stage = "complete"
	e.completed = e.stage=="complete"
	if e.completed: e.conversation = ""
	p.receipts[receipt.request_id] = receipt.duplicate(true)
	reconcile(data)
	return ""

func revalidate_operation(data: Dictionary, r: Dictionary) -> String:
	# Called again immediately before real consumption, not just when opening UI.
	if r.kind in ["battle","spectator"] or r.plan.has("battle_outcome") or r.plan.has("consumed_ids"): return ""
	return _guard(data,r.event_id,entry(data,r.event_id),r.operation,r.payload)
