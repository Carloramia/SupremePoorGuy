extends SceneTree
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed=true; push_error(message)
func run() -> void:
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = false
	app.save_path = "res://Tests/.runtime/integration/gameplay_"+str(Time.get_ticks_usec())+".json"
	root.add_child(app)
	app.ui.animate_panels = false
	app.start_new_game()
	for tick: int in 600:
		if app.phase=="world": break
		await physics_frame
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	var location: WorldMapLocation = app.world_map.get_location(&"bandits")
	location.state.discovered = true
	app.world_map.player.global_position = location.interaction_point()
	check(app.world_map.interaction.begin(location),"Open real battle location")
	app.world_map.interaction.request_battle()
	for tick: int in 600:
		if app.phase=="deployment": app.start_battle()
		if app.phase=="battle": break
		await physics_frame
	check(app.phase=="battle","Battle initialized")
	if app.battle==null: quit(1); return
	var host: Node3D = app.battle
	host.ended = true
	check(get_nodes_in_group(&"player_controller_3d").is_empty(),"Battle has no player Controller or wheel")
	var enemy: Node3D = host.actors[1]
	var initial: Vector3 = enemy.get_combat_anchor().global_position
	for actor: Node3D in host.actors:
		check(actor.get_node("NPCStateMachine3D").is_physics_processing(),"Both sides retain active AI without attaching a player")
	var saw_attack := false
	for tick: int in 1500:
		await physics_frame
		for actor: Node3D in host.actors:
			var inventory := actor.get_node("InventoryController3D")
			var weapon: SampleWeapon3D = inventory.get_equipped_item()
			if weapon!=null: saw_attack = saw_attack or weapon.swing_sequence>0
	check(enemy.get_combat_anchor().global_position.distance_to(initial)>2.0,"Enemy actually moves over imported navigation")
	if not saw_attack:
		for actor: Node3D in host.actors:
			print("BATTLE_AI_DIAGNOSTIC ",actor.name," ",actor.get_node("NPCStateMachine3D").get_state_diagnostics())
	check(saw_attack,"Runtime NPC approaches and opens a real attack damage window")
	app.queue_free()
	await process_frame
	await process_frame
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var mixed := preload("res://Scripts/Application/BattleHost.gd").new()
	mixed.enemy_definitions.assign(["wolf","snake","human"])
	viewport.add_child(mixed)
	var records: Array = []
	for species: String in ["human","wolf","snake"]:
		var record := FACTORY.template(species)
		record.id = "mixed_"+species
		record.speed_multiplier = 1.25
		record.damage_multiplier = 1.4
		record.interval_multiplier = 0.8
		records.append(record)
	check(await mixed.deploy(records,"mixed"),"Human/Wolf/Snake records deploy together without rerunning generators")
	check(mixed.start_combat(),"Explicitly finish deployment before testing combat")
	check(mixed.actors.size()==6,"Mixed battle contains each configured side")
	for index: int in mini(3,mixed.actors.size()):
		var actor: Node3D = mixed.actors[index]
		check(actor.generate_on_ready==false and actor.get_meta(&"creature_instance_id")==records[index].id,"Frozen blueprint identity survives deployment")
		check(actor.get_meta(&"summon_damage_multiplier")==1.4,"Damage multiplier reaches the existing damage source")
		for component: Node in actor.find_children("*","",true,false):
			var gait: Variant = component.get("slow_gait_data")
			if gait is Resource: check(is_equal_approx(float(gait.target_speed),float(records[index].speed)*1.25),"Summon speed reaches Node-based movement controller")
	mixed.ended = true
	for tick: int in 60: await physics_frame
	viewport.queue_free()
	await process_frame
	await process_frame
	print("BATTLE_GAMEPLAY_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
