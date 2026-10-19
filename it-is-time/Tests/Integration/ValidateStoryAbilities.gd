extends SceneTree
var checks:=0
var failed:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failed=true; push_error(label)
func hp(actor: Node) -> float:
	var total:=0.0
	for part: Node in actor.find_children("*","PhysicalBodyPart3D",true,false): total+=part.current_hp
	return total
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	var profiles:=preload("res://Scripts/Events/StoryCreatureProfiles.gd").new()
	var configs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://Content/Events/GrasslandEvents.json"))
	for profile in ["magic_eye","two_head"]:
		var viewport:=SubViewport.new(); viewport.own_world_3d=true; root.add_child(viewport)
		var battle:=preload("res://Scripts/Application/BattleHost.gd").new()
		battle.story_request={"battle_map_id":configs.bindings.battles.carlod.battle_map_id,"mode":"spectator"}
		battle.story_enemy_records=[profiles.make("wolf","target")]; viewport.add_child(battle)
		check(await battle.deploy([profiles.make(profile,"attacker")],profile),"Deploy actual "+profile)
		check(battle.start_combat(),"Start real combat "+profile)
		await physics_frame
		var ability: Node=battle.actors[0].get_node_or_null("StoryCreatureAbilities")
		check(ability!=null and ability.head!=null,"Real physical attack head exists "+profile)
		var target: Node=battle.actors[1]
		var before:=hp(target)
		check(ability._strike(target,profile=="magic_eye") and hp(target)<before,"Ability damages actual opposing body "+profile)
		if profile=="two_head": check(battle.actors[0].find_children("*","PhysicalBodyPart3D",true,false).size()==24,"Two real extra head parts")
		for frame in 420:
			await physics_frame
			if battle.ended: break
		check(hp(target)<before,"Physical simulation retains real damage "+profile)
		viewport.queue_free(); await process_frame
	print("STORY_ABILITIES_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
