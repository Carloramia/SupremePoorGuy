extends SceneTree
## A deliberately fragile enemy fixture ends through real AI/physics, not finish().
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	var profiles:=preload("res://Scripts/Events/StoryCreatureProfiles.gd").new()
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://Content/Events/GrasslandEvents.json"))
	var viewport:=SubViewport.new(); viewport.own_world_3d=true; root.add_child(viewport)
	var battle:=preload("res://Scripts/Application/BattleHost.gd").new()
	battle.story_request={"battle_map_id":config.bindings.battles.carlod.battle_map_id,"mode":"spectator"}
	var fragile:=profiles.make("rat","fragile")
	for part: Dictionary in fragile.parts.values(): part.hp=1
	fragile.hp=fragile.parts.size()
	battle.story_enemy_records=[fragile]; viewport.add_child(battle)
	if not await battle.deploy([profiles.make("magic_eye","eye")],"natural"):
		push_error(battle.last_error); quit(1); return
	var results: Array=[]
	battle.finished.connect(func(result):results.append(result))
	if not battle.start_combat(): push_error("Natural combat cannot start"); quit(1); return
	for frame in 2400:
		if battle.ended: break
		await physics_frame
	var passed: bool=not results.is_empty() and results[0].outcome in ["victory","defeat"] and results[0].get("winner") in ["one","two"]
	if not passed: push_error("Real autonomous battle did not produce a winner within 40 seconds")
	print("STORY_NATURAL_BATTLE_","PASSED" if passed else "FAILED"," result=",results[0].outcome if passed else "timeout")
	viewport.queue_free(); await process_frame
	quit(0 if passed else 1)
