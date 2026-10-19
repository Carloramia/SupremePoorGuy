extends SceneTree
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const RULES = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; push_error(message)
func run() -> void:
	var session := SESSION.new()
	session.save_path = "res://Tests/.runtime/integration/session_"+str(Time.get_ticks_usec())+".json"
	check(session.data.monsters.is_empty() and session.data.pending.is_empty(),"New game has no gifted creatures")
	check(session._valid_save(session.data),"An empty new-game roster is valid")
	check(session.save(),"Save formal session")
	var rules := RULES.new()
	check(rules.import_layout({"version":4,"stage":1,"placed":[{"uid":"test","runeId":"health","cells":[[-1,0],[0,0],[1,0]],"enabled":true}],"placedRelics":[]}),"Load current health layout")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	check(session.summon(rules,"frontier","world",rng),"Summon actual creature descriptors")
	check(session.data.pending.size()==5 and session.data.monsters.size()==5,"One batch creates five stable descriptors")
	var saved := session.data.duplicate(true)
	check(not session.summon(rules,"frontier","world",rng) and session.data==saved,"Pending batch rejects duplicate spending")
	var reload_session := SESSION.new()
	reload_session.save_path = session.save_path
	check(reload_session.load_save(),"Reload formal records and source hashes")
	check(reload_session.data.pending==session.data.pending and reload_session.data.magic==session.data.magic,"Reload preserves IDs and cost")
	for original: Dictionary in session.data.monsters:
		var restored: Dictionary = reload_session.monster_by_id(original.id)
		check(is_equal_approx(float(restored.hp),float(original.hp)) and restored.template_hash==original.template_hash,"Reload preserves attributes and source version")
		for path: String in original.poses:
			check(session.FACTORY.unpack_transform(original.poses[path])==session.FACTORY.unpack_transform(restored.poses[path]),"Reload preserves exact physics transform: "+path)
	var id: String = session.data.pending[0]
	check(session.move_monster(id,"team"),"Transfer the same creature ID into the party")
	check(session.monster_by_id(id).position=="team" and id not in session.data.pending,"Transfer consumes pending ID, no copied creature")
	var pose: Dictionary = session.monster_by_id(id).poses.duplicate(true)
	check(session.rename_monster(id,"改名测试") and session.monster_by_id(id).poses==pose,"Rename does not regenerate the creature")
	check(session.store_pending(),"Store remaining batch")
	var real_path: String = session.save_path
	session.save_path = real_path+"/blocked.json"
	var before := session.data.duplicate(true)
	check(not session.move_monster(id,"warehouse") and session.data==before,"Save failure rolls back roster transfer")
	session.save_path = real_path
	check(not session.supported_layout(rules).length(),"Supported health effect remains enabled")
	var unknown := RULES.new()
	unknown.placed = [{"uid":"bad","runeId":"burn","cells":[[0,0]],"enabled":true}]
	check(not session.supported_layout(unknown).is_empty(),"Unowned damage-over-time is rejected before spending")
	var world_state := WorldMapRuntimeState.new()
	world_state.map_id = &"frontier"
	world_state.pending_battle = {"map_id":"frontier","location_id":"bandits"}
	var world := world_state.to_dict()
	check(session.save_world(world) and session.data.battle.party_ids.size()==1,"Battle request atomically captures party IDs")
	var battle_id: String = session.data.battle.battle_id
	session.data.battle.event_id="QST_GRASS_011"
	check(session.save(),"Save the event provenance on the real battle request")
	var result := {"battle_id":battle_id,"outcome":"victory","reward":20,"parts":{},"content_source":"caller_cannot_override_request"}
	var magic: float = session.data.magic
	world.pending_battle = {}
	check(session.commit_battle(result,world),"Commit battle receipt, world and reward together")
	check(session.data.battle_results[battle_id].content_source=="QST_GRASS_011" and session.data.battle.result.content_source=="QST_GRASS_011","Reward source comes only from the committed battle request")
	check(session.claim_content_reward("QST_GRASS_011",battle_id,{"battle_id":battle_id}) and session.data.known_runes.has("multiply") and session.data.known_runes.has("bloodblade"),"Real saved event battle can grant swarm and biting curse together")
	check(session.commit_battle(result,world) and session.data.magic==magic+20,"Duplicate battle receipt never pays twice")
	var invalid := session.data.duplicate(true)
	invalid.worlds.frontier.player_position.x = "invalid"
	check(not session._valid_save(invalid),"Malformed map coordinates are rejected before load/save")
	invalid = session.data.duplicate(true)
	invalid.monsters[0].speed_multiplier = -1
	check(not session._valid_save(invalid),"Invalid physical movement multiplier is rejected")
	check(session.save(),"Create rotating backup")
	var corrupt := FileAccess.open(session.save_path,FileAccess.WRITE)
	corrupt.store_string("{broken"); corrupt.close()
	var recovery := SESSION.new()
	recovery.save_path = session.save_path
	check(recovery.load_save() and recovery._recovered_backup,"Corrupt main file recovers from validated backup")
	check(recovery.save(),"Recovery save preserves valid backup")
	var parser := JSON.new()
	parser.parse(FileAccess.get_file_as_string(session.save_path+".bak"))
	check(recovery._valid_save(parser.data),"Good backup is not replaced by the corrupt main file")
	_check_summon_pool(rules)
	print("APPLICATION_SESSION_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _check_summon_pool(rules: RefCounted) -> void:
	var seen := {}
	for seed_value: int in 8:
		var session := SESSION.new()
		session.save_path = "res://Tests/.runtime/integration/summon_pool_%d_%d.json" % [Time.get_ticks_usec(),seed_value]
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		check(session.summon(rules,"frontier","world",rng),"Summon from the five-species pool")
		for record: Dictionary in session.data.monsters:
			check(record.definition_id in ["stump_beast","wolf","snake","horned_beast","spider"],"New summons exclude Human")
			seen[record.definition_id] = true
		check(session.store_pending(),"All summoned species can enter the warehouse")
		var restored := SESSION.new()
		restored.save_path = session.save_path
		check(restored.load_save() and restored.data.monsters.size()==5,"New species survive save/load")
	check(seen.size()==5,"Seeded batches can produce every requested species")
	var legacy := SESSION.new()
	legacy.save_path = "res://Tests/.runtime/integration/legacy_human_"+str(Time.get_ticks_usec())+".json"
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(legacy)
	var restored := SESSION.new()
	restored.save_path = legacy.save_path
	check(restored.load_save() and restored.monsters("team")[0].definition_id=="human","Existing Human inventory remains loadable")

