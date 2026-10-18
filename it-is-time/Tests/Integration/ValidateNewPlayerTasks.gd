extends SceneTree
const TASKS = preload("res://Scripts/Application/NewPlayerTasks.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)

func fixture(enabled := true) -> Dictionary:
	var data := {"magic":300, "serial":0, "last_summon":{}, "monsters":[], "pending":[], "worlds":{}, "battle_results":{}}
	TASKS.ensure_progress(data).enabled = enabled
	return data

func done(data: Dictionary, id: String) -> bool:
	return data.new_player_tasks.completed.has(id)

func _initialize() -> void:
	_test_unlocks_and_facts()
	_test_history()
	_test_rewards_and_validation()
	print("NEW_PLAYER_TASKS checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func _test_unlocks_and_facts() -> void:
	var data := fixture(false)
	check(TASKS.validate_definitions(TASKS.DEFINITIONS).is_empty(),"Default configuration is valid")
	check(TASKS.reconcile(data).ok and data.new_player_tasks.completed.is_empty(),"Disabled guide awards nothing")
	check(TASKS.rows(data).size()==4 and TASKS.rows(data).all(func(row): return row.locked),"All four tasks are visible before activation")
	data.new_player_tasks.enabled = true
	data.worlds.demo = {"backend":"frontier_delivery_v1", "visited":[], "discovered":["hut"]}
	TASKS.reconcile(data)
	check(not done(data,"explore_frontier"),"A saved map and discovered marker do not prove arrival")
	TASKS.record_location(data,"demo","hut")
	TASKS.reconcile(data)
	check(done(data,"explore_frontier"),"An actual arrival completes exploration")
	check(TASKS.rows(data)[0].done and TASKS.rows(data).size()==4,"Completed tasks remain in the list")
	check(TASKS.rows(data)[2].locked and TASKS.rows(data)[2].prerequisite_text.contains("完成召唤"),"Locked task identifies its prerequisite")
	data.monsters = [{"position":"team"}]
	data.battle_results.battle_1 = {"outcome":"victory"}
	TASKS.reconcile(data)
	check(not done(data,"prepare_party") and not done(data,"win_battle"),"Facts do not bypass prerequisites")
	data.monsters.clear()
	data.battle_results.clear()
	data.serial = 1
	data.last_summon = {"succeeded":1}
	data.pending = ["unit_1"]
	TASKS.reconcile(data)
	check(not done(data,"complete_summon"),"A successful summon with pending units is not settled")
	data.pending.clear()
	var result := TASKS.reconcile(data)
	check(result.completed.size()==3,"Previously proved party and victory are credited after summon unlock")
	check(done(data,"complete_summon") and done(data,"prepare_party") and done(data,"win_battle"),"Dependency chain settles automatically")
	data.last_summon = {"succeeded":0}
	data.serial = 0
	TASKS.reconcile(data)
	check(data.new_player_tasks.completed.size()==4,"Later state changes never revoke completed tasks")
	check(data.magic==300,"Default tasks grant no reward")
	check(TASKS.valid_progress(JSON.parse_string(JSON.stringify(data))),"Task receipts survive JSON save/load")
	check(TASKS.reconcile(data).completed.is_empty(),"Repeated reconciliation is idempotent")
	var old_batch := fixture()
	old_batch.serial = 2
	old_batch.last_summon = {"succeeded":0}
	old_batch.monsters = [{"id":"summon_1_0","batch_id":"batch_1","source_layout":{},"position":"warehouse"}]
	TASKS.reconcile(old_batch)
	check(done(old_batch,"complete_summon"),"An older settled batch remains provable after a later all-failed summon")
	old_batch.last_summon = {"succeeded":5}
	old_batch.serial = 1
	TASKS.reconcile(old_batch)
	check(old_batch.new_player_tasks.facts.summon_batches.size()==1,"Report and creature evidence count the same batch only once")
	var fresh := fixture()
	fresh.serial = 2
	fresh.last_summon = {"succeeded":0}
	TASKS.reconcile(fresh)
	check(not done(fresh,"complete_summon"),"All-failed summon does not complete summon task")
	fresh.last_summon.clear()
	TASKS.reconcile(fresh)
	check(not done(fresh,"complete_summon"),"A serial alone does not prove successful settlement")
	var reordered: Array = TASKS.DEFINITIONS.duplicate(true)
	reordered.reverse()
	data.new_player_tasks.completed.clear()
	check(TASKS.reconcile(data,reordered).completed.size()==4,"Configuration order does not prevent dependency chaining")

func _test_history() -> void:
	var legacy := fixture()
	legacy.erase(TASKS.SAVE_KEY)
	legacy.worlds.map_1 = {"backend":"legacy_frontier", "location_runtime_states":{"town":{"visits":1}}}
	legacy.serial = 3
	legacy.last_summon = {"succeeded":2}
	legacy.monsters = [{"position":"team"}]
	legacy.battle_results.old_win = {"outcome":"victory"}
	check(TASKS.valid_progress(legacy),"Saves without task fields are accepted")
	TASKS.ensure_progress(legacy).enabled = true
	check(TASKS.reconcile(legacy).completed.size()==4,"Reliable old world, summon, party and victory records are credited")
	var delivery := fixture()
	delivery.worlds.frontier_layout = {"backend":"frontier_delivery_v1", "visited":["hut"]}
	TASKS.reconcile(delivery)
	check(done(delivery,"explore_frontier"),"Delivery visited history proves arrival")
	var unknown := fixture()
	unknown.worlds.map_1 = {"backend":"legacy_frontier", "location_runtime_states":{"town":{"discovered":true,"visits":0}}}
	unknown.battle_results.loss = {"outcome":"defeat"}
	TASKS.reconcile(unknown)
	check(unknown.new_player_tasks.completed.is_empty(),"Unproven legacy progress and defeats remain incomplete")
	TASKS.record_location(delivery,"frontier_layout","hut")
	TASKS.record_location(delivery,"frontier_layout","hut")
	check(delivery.new_player_tasks.facts.locations.size()==1,"Arrival facts are deduplicated")
	var counted: Array = TASKS.DEFINITIONS.duplicate(true)
	counted[0].condition.count = 2
	var counted_data := fixture()
	TASKS.record_location(counted_data,"map","one")
	TASKS.reconcile(counted_data,counted)
	check(not done(counted_data,"explore_frontier"),"Configurable counts require sufficient distinct evidence")
	TASKS.record_location(counted_data,"map","two")
	TASKS.reconcile(counted_data,counted)
	check(done(counted_data,"explore_frontier"),"Count threshold completes after sufficient evidence")

func _test_rewards_and_validation() -> void:
	var definitions: Array = TASKS.DEFINITIONS.duplicate(true)
	definitions[0].reward = {"magic":17, "runes":["iron"], "relics":["bone-die"]}
	var data := fixture()
	data.known_runes = ["armor"]
	data.known_relics = []
	TASKS.record_location(data,"map","hut")
	TASKS.reconcile(data,definitions)
	check(data.magic==317 and "iron" in data.known_runes and "bone-die" in data.known_relics,"Configured magic and reference unlocks are granted")
	check(data.new_player_tasks.completed.explore_frontier.reward.magic==17,"Completion contains the original reward receipt")
	definitions[0].reward.magic = 99
	TASKS.reconcile(data,definitions)
	check(data.magic==317,"Editing reward configuration does not repay completed tasks")
	var reloaded: Dictionary = JSON.parse_string(JSON.stringify(data))
	TASKS.reconcile(reloaded,definitions)
	check(reloaded.magic==317 and reloaded.known_runes.count("iron")==1,"Loading and rechecking do not duplicate rewards")
	var all_unlocked := fixture()
	TASKS.record_location(all_unlocked,"map","hut")
	TASKS.reconcile(all_unlocked,definitions)
	check(all_unlocked.known_runes.size()==TASKS.RULES.RUNES.size() and all_unlocked.known_relics.size()==TASKS.RULES.RELICS.size(),"Missing reference lists preserve the all-unlocked policy")
	check(all_unlocked.magic==399,"Already-owned unlocks grant no compensation")
	check(TASKS.reward_text(definitions[0].reward).contains("骨骰"),"Rewards have readable reference names")
	for error_kind: String in ["duplicate", "missing", "cycle", "negative", "fraction", "unknown_rune", "unsupported_reward"]:
		var invalid: Array = TASKS.DEFINITIONS.duplicate(true)
		match error_kind:
			"duplicate": invalid[1].id = invalid[0].id
			"missing": invalid[0].prerequisites = ["missing_id"]
			"cycle": invalid[0].prerequisites = ["explore_frontier"]
			"negative": invalid[0].reward.magic = -1
			"fraction": invalid[0].reward.magic = 1.5
			"unknown_rune": invalid[0].reward.runes = ["not_a_rune"]
			"unsupported_reward": invalid[0].reward.gold = 10
		var unchanged := fixture()
		var snapshot := unchanged.duplicate(true)
		check(not TASKS.reconcile(unchanged,invalid).ok and unchanged==snapshot,"Invalid configuration is rejected without mutation: "+error_kind)
	var corrupt := fixture()
	corrupt.new_player_tasks.facts.locations = ["duplicate","duplicate"]
	check(not TASKS.valid_progress(corrupt) and not TASKS.reconcile(corrupt).ok,"Corrupt task facts are rejected")
