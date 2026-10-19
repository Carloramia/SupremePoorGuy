extends SceneTree
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const RESOURCES = preload("res://Scripts/Events/StoryEventResources.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func reward_request(reward: Dictionary) -> Dictionary:
	return {"request_id":"fixture_reward","kind":"transaction","plan":{"reward":reward},"payload":{}}

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var service := RESOURCES.new()
	var session := SESSION.new()
	session.save_path = "res://Tests/.runtime/story_events/resources_%d.json" % Time.get_ticks_usec()
	check(session.save(),"Create isolated real game session")
	var data: Dictionary = session.data
	var base_magic: float = data.magic
	var reward := {"magic":13,"runes":["iron"],"relics":["bone-die"]}
	check(service.apply(data,reward_request(reward)).is_empty() and data.magic==base_magic+13,"Adapter changes actual balance and unlock collection")
	check(data.known_runes.count("iron")==1 and data.known_relics.count("bone-die")==1,"Already open references never gain duplicate entries")
	var bad := reward_request({"magic":20,"items":[{"id":"missing","count":1}]})
	var before: Dictionary = data.duplicate(true)
	check(not service.apply(data,bad).is_empty() and data==before,"Unknown item prevents entire reward including money")
	service.item_definitions["test-royal-order"] = {"name":"Test order"}
	var item_reward := reward_request({"magic":0,"items":[{"id":"test-royal-order","count":1}]})
	check(service.apply(data,item_reward).is_empty() and data.story_items["test-royal-order"]==1,"Registered story item enters actual saved inventory")
	check(session.save(),"Item inventory passes formal save validator")
	var broken: Dictionary = data.duplicate(true)
	broken.story_items["test-royal-order"] = -1
	check(not session._valid_save(broken),"Invalid inventory count is rejected by formal session")
	var purchase := {"kind":"purchase","plan":{"cost":100,"from_stage":1,"to_stage":2}}
	base_magic = data.magic
	check(service.apply(data,purchase).is_empty() and data.magic==base_magic-100 and data.array_stage==2 and data.layout.stage==2,"Purchase commits actual magic debit and valid circle expansion")
	before = data.duplicate(true)
	check(not service.apply(data,purchase).is_empty() and data==before,"Stale upgrade cannot charge again")
	data.magic = 9
	before = data.duplicate(true)
	check(not service.apply(data,{"kind":"bet","plan":{"stake":10}}).is_empty() and data==before,"Wager cannot overdraw balance")
	data.magic = 100
	check(service.apply(data,{"kind":"bet","plan":{"stake":10}}).is_empty() and data.magic==90,"Wager debits one real stake")
	for i: int in 2:
		var unit := FACTORY.template("wolf")
		unit.merge({"id":"owned_"+str(i),"position":"warehouse","traits":[]},true)
		data.monsters.append(unit)
	var sacrifice := {"request_id":"fixture_sacrifice","kind":"sacrifice","payload":{"monster_ids":["owned_0"],"confirmed":true},"plan":{"reward":{"magic":15}}}
	before = data.duplicate(true)
	sacrifice.plan.reward = {"magic":15,"items":[{"id":"missing","count":1}]}
	check(not service.apply(data,sacrifice).is_empty() and data==before,"Reward validation failure restores consumed creature")
	sacrifice.plan.reward = {"magic":15}
	check(service.apply(data,sacrifice).is_empty() and data.monsters.size()==1 and data.monsters[0].id=="owned_1" and data.magic==105,"Sacrifice really removes selected instance and gives configured reward")
	sacrifice.payload.monster_ids = ["owned_1"]
	before = data.duplicate(true)
	check(not service.apply(data,sacrifice).is_empty() and data==before,"Cannot consume last owned creature")
	service.monster_presets["test-wolf"] = FACTORY.template("wolf")
	var creature_reward := reward_request({"magic":0,"monsters":[{"id":"test-wolf","count":1}]})
	check(service.apply(data,creature_reward).is_empty() and data.monsters.size()==2 and data.monsters.back().position=="warehouse","Creature reward stores actual valid physical record in warehouse")
	check(session.save(),"Creature reward passes formal physical record save validation")
	before = data.duplicate(true)
	check(not service.apply(data,creature_reward).is_empty() and data==before,"Existing instance cannot be overwritten by repeated direct mutation")
	# Exercise adapter through the only production commit path with durable receipt.
	var id := "QST_GRASS_013"
	session.story_events.config.bindings.rewards.stars = {"magic":21,"runes":[],"relics":[]}
	var opened: Dictionary = session.open_story_event(id,"well",true)
	check(session.story_event_action(id,"record",opened.event.conversation).ok,"Create production reward request")
	var r: Dictionary = session.pending_story_request(id)
	var ack := {"request_id":r.request_id,"event_id":r.event_id,"stage":r.stage,"branch":r.branch,"kind":r.kind,"outcome":"success","committed":true}
	var path: String = session.save_path
	session.save_path += "/blocked.json"
	before = session.data.duplicate(true)
	check(not session.commit_story_receipt(ack,service.apply) and session.data==before,"Real resource adapter rolls back with failed persistence")
	session.save_path = path
	check(session.commit_story_receipt(ack,service.apply) and session.data.magic==before.magic+21,"Retry commits actual reward exactly once")
	var money: float = session.data.magic
	check(session.commit_story_receipt(ack,service.apply) and session.data.magic==money,"Durable receipt prevents double credit")
	var restored := SESSION.new()
	restored.save_path = path
	check(restored.load_save() and restored.data.magic==money and restored.story_event_view(id).completed,"Reward, inventory and event completion reload together")
	print("STORY_EVENT_RESOURCES_", "PASSED" if failures==0 else "FAILED", " checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
