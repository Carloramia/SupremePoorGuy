extends SceneTree
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed=true; push_error(message)
func run() -> void:
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path = "res://Tests/.runtime/integration/frontier_"+str(Time.get_ticks_usec())+".json"
	app.world_scene = load("res://Content/Maps/IntegrationFrontier_v1/frontier/frontier.tscn")
	app.battle_definitions = {"camp_battle_01":app.default_battle_definition}
	root.add_child(app)
	app.ui.animate_panels = false
	app.start_new_game()
	for tick: int in 600:
		if app.phase=="world": break
		await physics_frame
	check(app.phase=="world","Imported 2D map initializes")
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	var location: WorldMapLocation = app.world_map.get_location(&"monster_camp_01")
	check(location!=null,"Imported camp metadata remains addressable")
	if location==null: quit(1); return
	location.state.discovered = true
	app.world_map.player.global_position = location.interaction_point()
	check(app.world_map.interaction.begin(location),"Imported camp opens only after arrival")
	app.world_map.interaction.request_battle()
	for tick: int in 600:
		if app.phase=="battle": break
		await physics_frame
	check(app.phase=="battle" and app.battle!=null,"Imported battle definition deploys actual NPCs")
	if app.battle==null: quit(1); return
	check(app.battle.definition.scene_id==&"camp_battle_01","Encounter consumes its configured battle_map_id")
	var region: NavigationRegion3D = app.battle.get_node("NavigationRegion3D")
	check(region.navigation_mesh.get_polygon_count()>0,"Navigation is baked from imported ground collision")
	check(app.battle._geometry.get_node("AirWalls").get_child_count()==6,"Imported air-wall collisions remain active")
	check(not app.battle._geometry.has_node("Objects/camp_guard_01"),"No duplicate editor stand-in beside the actual enemy")
	app.battle.ended = true
	for tick: int in 120: await physics_frame
	for actor: Node3D in app.battle.actors:
		check(actor.get_combat_anchor().global_position.y>0,"Imported floor supports actual physical creatures")
	app.queue_free()
	await process_frame
	await process_frame
	print("FRONTIER_IMPORT_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
