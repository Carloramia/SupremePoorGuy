extends SceneTree
const HOST=preload("res://Scripts/Application/BattleHost.gd")
const PROFILES=preload("res://Scripts/Events/StoryCreatureProfiles.gd")
var checks:=0
var failed:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failed=true; push_error(label)
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	var profiles:=PROFILES.new()
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://Content/Events/GrasslandEvents.json"))
	var configs: Array=config.bindings.battles.values()
	for round: Dictionary in config.bindings.bet_rounds:
		configs.append(round.one); configs.append(round.two)
	for index in configs.size():
		var c: Dictionary=configs[index]
		var viewport:=SubViewport.new(); viewport.own_world_3d=true; root.add_child(viewport)
		var battle:=HOST.new(); battle.story_request={"battle_map_id":c.battle_map_id,"mode":"spectator"}
		battle.story_enemy_records=profiles.roster(c,"right")
		var left:=profiles.roster(c.get("other_side",{"profiles":["wolf"]}),"left")
		viewport.add_child(battle)
		var ok: bool=await battle.deploy(left,"approved_%d"%index)
		check(ok,"Actual deployment "+str(index)+" "+c.battle_map_id+" "+battle.last_error)
		if ok:
			var error: String=battle.deployment.placement_error
			check(battle.start_combat(),"Deployment allows combat "+str(index)+" "+error)
			for frame in 8: await physics_frame
			var snapshot:=battle.checkpoint()
			check(snapshot.actors.size()==left.size()+battle.story_enemy_records.size(),"Physical checkpoint preserves each actor")
			battle.restore_checkpoint(snapshot)
		print("BATTLE_CONFIG ",index," ","OK" if ok else "FAILED")
		viewport.queue_free(); await process_frame; await physics_frame
	print("APPROVED_BATTLES_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
