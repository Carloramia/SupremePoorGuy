extends SceneTree
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const RULES = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var session := SESSION.new()
	session.save_path = "res://Tests/.runtime/integration/new_player_tasks_%d.json" % Time.get_ticks_usec()
	session.task_definitions[0].reward = {"magic":13,"runes":["attack"],"relics":["taunt-bell"]}
	session.data.known_runes = ["health"]
	session.data.known_relics = []
	var notifications := {"count":0}
	session.new_player_tasks_completed.connect(func(ids): notifications.count += ids.size())
	check(session.save(),"New session saves before tutorial activation")
	check(not session.data.new_player_tasks.enabled,"Main-menu save does not activate tasks")
	check(session.enable_new_player_tasks(),"First world entry activates and saves task state")
	check(session.data.new_player_tasks.completed.is_empty(),"Activation fabricates no completed objectives")
	var path: String = session.save_path
	var before: Dictionary = session.data.duplicate(true)
	session.save_path = path+"/blocked.json"
	check(not session.record_task_arrival("frontier_layout","summoning_hut"),"Arrival reward save failure is propagated")
	check(session.data==before and notifications.count==0,"Failed save rolls back facts, reward, completion and notification")
	session.save_path = path
	check(session.record_task_arrival("frontier_layout","summoning_hut"),"Actual arrival is committed")
	check(session.data.magic==313 and session.data.known_runes.has("attack") and session.data.known_relics==["taunt-bell"],"Reward types commit with task completion")
	check(notifications.count==1,"Notification is emitted only after successful save")
	check(session.record_task_arrival("frontier_layout","summoning_hut") and session.data.magic==313 and notifications.count==1,"Repeated arrival never repeats reward or notification")
	var rules := RULES.new()
	rules.extend([-1,0]); rules.extend([0,0]); rules.extend([1,0]); rules.commit()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	check(session.summon(rules,"frontier_layout","world",rng),"A real supported summon succeeds")
	check(not session.data.new_player_tasks.completed.has("complete_summon"),"Generation alone does not complete settlement task")
	var id: String = session.data.pending[0]
	check(session.move_monster(id,"team"),"An actual generated unit can join the party")
	check(not session.data.new_player_tasks.completed.has("prepare_party"),"Party objective remains locked until results are settled")
	check(session.store_pending(),"Remaining actual results are stored")
	check(session.data.new_player_tasks.completed.has("complete_summon") and session.data.new_player_tasks.completed.has("prepare_party"),"Settlement automatically unlocks and credits proved party setup")
	check(session.move_monster(id,"warehouse") and session.data.new_player_tasks.completed.has("prepare_party"),"Emptying the party does not revoke completion")
	check(session.move_monster(id,"team"),"Party can be restored for battle")
	var world_state := WorldMapRuntimeState.new()
	world_state.map_id = &"frontier"
	world_state.pending_battle = {"map_id":"frontier","location_id":"bandits"}
	var world := world_state.to_dict()
	check(session.save_world(world),"A real session battle request captures party IDs")
	var result := {"battle_id":session.data.battle.battle_id,"outcome":"victory","reward":20,"parts":{}}
	world.pending_battle = {}
	before = session.data.duplicate(true)
	session.save_path = path+"/blocked.json"
	check(not session.commit_battle(result,world) and session.data==before,"Failed settlement rolls back battle and task together")
	session.save_path = path
	check(session.commit_battle(result,world) and session.data.new_player_tasks.completed.has("win_battle"),"Persisted victory completes the final task")
	check(session.data.new_player_tasks.completed.size()==4 and session.new_player_task_rows().size()==4,"All completed task rows remain visible")
	var completed_magic: int = session.data.magic
	check(session.commit_battle(result,world) and session.data.magic==completed_magic,"Duplicate battle receipt remains idempotent")
	var reloaded := SESSION.new()
	reloaded.save_path = path
	check(reloaded.load_save() and reloaded.data.new_player_tasks.completed.size()==4,"Task receipts reload with the real session")
	reloaded.task_definitions[0].reward.magic = 500
	check(reloaded.enable_new_player_tasks() and reloaded.data.magic==completed_magic,"Reload and reward edits do not repay completed tasks")
	check(reloaded.new_player_task_action("win_battle").is_empty(),"Completed task cannot execute an obsolete action")
	# Produce a genuine pre-feature save from the same valid business records.
	var legacy_path := path+".legacy.json"
	var legacy_data: Dictionary = reloaded.data.duplicate(true)
	legacy_data.erase("new_player_tasks")
	var legacy_world: Dictionary = legacy_data.worlds.frontier
	legacy_world.location_runtime_states["town"] = {"visits":1,"discovered":true,"lifecycle":0,"custom_data":{}}
	var file := FileAccess.open(legacy_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy_data)); file.close()
	var legacy := SESSION.new()
	legacy.save_path = legacy_path
	legacy.task_definitions[0].reward.magic = 7
	check(legacy.load_save() and not legacy.data.has("new_player_tasks"),"Old save loads without eagerly changing the file")
	check(legacy.enable_new_player_tasks() and legacy.data.new_player_tasks.completed.size()==4,"Reliable old achievements are credited at activation")
	check(legacy.data.magic==completed_magic+7,"Old save receives its configured reward once")
	check(legacy.enable_new_player_tasks() and legacy.data.magic==completed_magic+7,"Repeated activation does not repay migration reward")
	var corrupt: Dictionary = legacy.data.duplicate(true)
	corrupt.new_player_tasks.completed.explore_frontier.reward.magic = -1
	check(not legacy._valid_save(corrupt),"Malformed task receipts are rejected before load/save")
	legacy.reset()
	check(legacy.save() and legacy.data.new_player_tasks.completed.is_empty() and not legacy.data.new_player_tasks.enabled,"Starting a new session resets tasks and receipts")
	check(legacy.data.magic==300 and legacy.data.known_runes==["health"] and legacy.data.known_relics.is_empty(),"New game preserves 300 magic and owns only basic life")
	print("NEW_PLAYER_TASK_SESSION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
