extends SceneTree
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const DEFINITION = preload("res://Scripts/Quests/QuestDefinition.gd")
const OBJECTIVE = preload("res://Scripts/Quests/QuestObjectiveData.gd")
const SERVICE = preload("res://Scripts/Quests/QuestService.gd")
const EXAMPLE = preload("res://Resources/Quests/Examples/FirstVictory.tres")
var failed := false
var notifications := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; push_error(message)

func definitions() -> Array[DEFINITION]:
	var visit := OBJECTIVE.new()
	visit.id = &"visit"
	visit.event_key = &"map.visited"
	visit.target_id = &"camp"
	visit.required_count = 2
	var ready := OBJECTIVE.new()
	ready.id = &"ready"
	ready.event_key = &"party.ready"
	ready.count_mode = OBJECTIVE.CountMode.MAXIMUM
	ready.required_count = 2
	ready.count_history = true
	var first := DEFINITION.new()
	first.id = &"first"
	first.objectives = [visit, ready]
	first.reward_magic = 15
	first.reward_rune_ids = [&"health"]
	var followup: DEFINITION = EXAMPLE.duplicate(true)
	followup.prerequisite_ids = [&"first"]
	followup.auto_accept = false
	return [first, followup]

func new_session() -> RefCounted:
	var session := SESSION.new()
	session.save_path = "res://Tests/.runtime/quests/session_%d_%d.json" % [Time.get_ticks_usec(),randi()]
	check(session.configure_quests(definitions()), "Configure valid resource definitions")
	return session

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var session = new_session()
	session.quests_changed.connect(func(): notifications += 1)
	check(session.save(), "Save initialized quests")
	check(session.get_quest(&"first").state == "active" and session.get_quest(EXAMPLE.id).state == "locked", "Auto accept and prerequisite lock")
	check(session.get_quest(&"missing").is_empty(), "Unknown quest has no mutable placeholder")
	check(not session.accept_quest(EXAMPLE.id), "Locked quest cannot be accepted")
	check(session.record_quest_event(&"map.visited", "wrong_target", &"town"), "Unmatched target is a harmless no-op")
	check(session.record_quest_event(&"map.visited", "old_visit", &"camp", 2, true), "Disallowed historical progress is ignored")
	check(session.get_quest(&"first").objectives[0].count == 0, "Visits require current matching events")
	check(session.record_quest_event(&"map.visited", "visit_1", &"camp"), "Add unique visit")
	var before: Dictionary = session.data.duplicate(true)
	var notices_before := notifications
	check(session.record_quest_event(&"map.visited", "visit_1", &"camp") and session.data == before and notifications == notices_before, "Duplicate receipt changes nothing and emits no notification")
	check(session.record_quest_event(&"map.visited", "visit_2", &"camp"), "Second visit satisfies one objective")
	check(session.get_quest(&"first").state == "active", "All objectives must finish")
	check(session.record_quest_event(&"party.ready", "ready_history", &"", 2, true), "Opt-in historical total accepted")
	check(session.get_quest(&"first").state == "completed" and session.get_quest(EXAMPLE.id).state == "available", "Completion unlocks followup before reward claim")
	check(session.record_quest_event(&"party.ready", "empty_party", &"", 0) and session.get_quest(&"first").state == "completed", "Completion never regresses")
	var view: Dictionary = session.get_quest(&"first")
	view.objectives[0].count = 999
	check(session.get_quest(&"first").objectives[0].count == 2, "Read model cannot mutate saved progress")
	check(session.get_quests(PackedStringArray(["completed"])).size() == 1, "UI may filter states")
	check(session.record_quest_event(&"battle.victory", "too_early"), "Unaccepted quest ignores events")
	check(session.get_quest(EXAMPLE.id).objectives[0].count == 0, "Manual quest does not progress before acceptance")
	check(session.accept_quest(EXAMPLE.id), "Accept manual quest")
	check(session.record_quest_event(&"battle.victory", "battle_1"), "Complete configured example")
	session.data.known_runes = []
	var magic := int(session.data.magic)
	check(session.claim_quest_reward(&"first"), "Claim completed quest")
	check(session.data.magic == magic + 15 and "health" in session.data.known_runes and "quest:first" in session.data.completed and session.get_quest(&"first").state == "claimed", "Reward, unlock and claim marker share one save")
	check(not session.claim_quest_reward(&"first") and session.data.magic == magic + 15, "No double reward")
	_check_rollback(session)
	_check_reload(session)
	_check_old_save()
	_check_validation()
	_check_event_order()
	_check_business_transaction()
	print("QUEST_INTERFACES_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _check_rollback(session: RefCounted) -> void:
	var real_path: String = session.save_path
	session.save_path = real_path+"/blocked.json"
	var before: Dictionary = session.data.duplicate(true)
	check(not session.claim_quest_reward(EXAMPLE.id) and session.data == before, "Save failure rolls back both money and claim status")
	session.save_path = real_path
	check(session.claim_quest_reward(EXAMPLE.id), "Failed claim remains retryable")
	var progress = new_session()
	check(progress.save(), "Create progress rollback fixture")
	real_path = progress.save_path
	progress.save_path += "/blocked.json"
	before = progress.data.duplicate(true)
	check(not progress.record_quest_event(&"map.visited", "retry", &"camp") and progress.data == before, "Failed save does not consume event ID")
	progress.save_path = real_path
	check(progress.record_quest_event(&"map.visited", "retry", &"camp") and progress.get_quest(&"first").objectives[0].count == 1, "Retry of rolled-back receipt counts exactly once")

func _check_reload(session: RefCounted) -> void:
	var restored = new_session()
	restored.save_path = session.save_path
	check(restored.load_save(), "Reload quest state")
	check(restored.get_quest(&"first").state == "claimed" and restored.get_quest(EXAMPLE.id).state == "claimed", "Claimed states survive JSON roundtrip")
	check(not restored.claim_quest_reward(&"first") and restored.data.magic == session.data.magic, "Reload never regrants rewards")
	check(restored.configure_quests([]) and restored.save(), "Temporarily removed definitions keep saved entries")
	check(restored.configure_quests(definitions()) and restored.get_quest(&"first").state == "claimed", "Restoring a definition retains the claimed receipt")
	restored.reset()
	check(restored.get_quest(&"first").state == "active" and restored.get_quest(EXAMPLE.id).state == "locked", "New game clears progress but keeps configured resources")

func _check_old_save() -> void:
	var old = new_session()
	old.data.erase("quests")
	check(old._valid_save(old.data), "Old save without quests remains structurally valid")
	var fixture := FileAccess.open(old.save_path,FileAccess.WRITE)
	fixture.store_string(JSON.stringify(old.data))
	fixture.close()
	var restored = new_session()
	restored.save_path = old.save_path
	check(restored.load_save() and restored._needs_quest_backup, "Missing quest field migrates without a false completion")
	check(restored.get_quest(&"first").state == "active" and restored.save(), "Migrated old save can be written")
	var backup: String = old.save_path+".pre_quests_v1.bak"
	check(FileAccess.file_exists(backup) and not JSON.parse_string(FileAccess.get_file_as_string(backup)).has("quests"), "First upgrade keeps the original pre-quest backup")

func _check_validation() -> void:
	var session = new_session()
	var previous: Dictionary = session.data.duplicate(true)
	var bad := definitions()
	bad[0].prerequisite_ids = [EXAMPLE.id]
	check(not session.configure_quests(bad) and session.data == previous, "Cyclic definitions rejected without changing active registry")
	bad = definitions()
	bad[0].reward_rune_ids = [&"missing"]
	check(not session.configure_quests(bad), "Invalid reward rejected before runtime")
	check(not session.configure_quests([false]) and not session.record_quest_events([false]), "Untyped public arrays reject invalid elements safely")
	check(not session.record_quest_events([{"event_key":"party.ready", "event_id":"bad", "amount":-1}]), "Invalid amounts rejected")
	check(not session.record_quest_events([{"event_key":"map.visited", "event_id":"valid", "target_id":"camp"}, {"event_key":"", "event_id":"invalid"}]) and session.data == previous, "Malformed batch cannot partially advance a quest")
	var corrupt: Dictionary = previous.duplicate(true)
	corrupt.quests.entries.first.objectives.visit.count = "bad"
	check(not session._valid_save(corrupt), "Malformed quest save is rejected")

func _check_event_order() -> void:
	var first := DEFINITION.new()
	first.id = &"one"
	var goal := OBJECTIVE.new()
	goal.id = &"goal"
	goal.event_key = &"event"
	first.objectives = [goal]
	var second: DEFINITION = first.duplicate(true)
	second.id = &"two"
	second.prerequisite_ids = [&"one"]
	var session := SESSION.new()
	session.save_path = "res://Tests/.runtime/quests/order_%d.json" % Time.get_ticks_usec()
	check(session.configure_quests([first,second]) and session.record_quest_event(&"event", "receipt"), "Process shared event in dependency chain")
	check(session.get_quest(&"one").state == "completed" and session.get_quest(&"two").state == "active", "One receipt cannot finish a newly unlocked successor")
	check(session.record_quest_event(&"event", "receipt") and session.get_quest(&"two").state == "active", "Replaying that receipt cannot finish the successor either")
	check(session.record_quest_event(&"event", "receipt_2") and session.get_quest(&"two").state == "completed", "A new receipt advances the successor")

func _check_business_transaction() -> void:
	var session := SESSION.new()
	session.save_path = "res://Tests/.runtime/quests/business_%d.json" % Time.get_ticks_usec()
	check(session.configure_quests([EXAMPLE]), "Configure transaction example")
	var fixture = preload("res://Tests/Integration/ApplicationFixtures.gd")
	fixture.add_human(session)
	var world_state := WorldMapRuntimeState.new()
	world_state.map_id = &"frontier"
	world_state.pending_battle = {"map_id":"frontier", "location_id":"bandits"}
	var world := world_state.to_dict()
	check(session.save_world(world), "Open real session battle")
	var id: String = session.data.battle.battle_id
	var result := {"battle_id":id, "outcome":"victory", "reward":20, "parts":{}}
	var events := [{"event_key":"battle.victory", "event_id":id}]
	world.pending_battle = {}
	var before := session.data.duplicate(true)
	var real_path: String = session.save_path
	session.save_path += "/blocked.json"
	check(not session.commit_battle(result,world,events) and session.data == before, "Battle receipt, reward, world and quest progress roll back together")
	session.save_path = real_path
	check(session.commit_battle(result,world,events) and session.get_quest(EXAMPLE.id).state == "completed", "Battle commit can carry quest events in the same save")
	before = session.data.duplicate(true)
	check(session.commit_battle(result,world,events) and session.data == before, "Duplicate battle receipt cannot replay quest effects")
