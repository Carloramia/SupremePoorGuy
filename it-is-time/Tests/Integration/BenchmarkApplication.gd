extends SceneTree
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
func _initialize() -> void: call_deferred("run")
func battle_definition() -> SceneDefinition:
	var definition: SceneDefinition = load("res://Content/Maps/IntegrationFrontier_v1/camp_battle_01/SceneDefinition.tres").duplicate(true)
	var objects: Array = definition.metadata.editor_data.map.objects
	var enemy: Dictionary = objects[1].duplicate(true)
	for index: int in range(1,4):
		var copy := enemy.duplicate(true)
		copy.id = "enemy_"+str(index)
		copy.position[1] = [0,-20,20,-40][index]
		objects.append(copy)
	return definition
func records() -> Array:
	var result: Array = []
	for index: int in 4:
		var record := FACTORY.template("human")
		record.id = "benchmark_"+str(index)
		record.position = "team"
		record.traits = []
		result.append(record)
	return result
func measure(host: Node, label: String) -> Dictionary:
	host.ended = true
	for tick: int in 120: await physics_frame
	var physics_ms: Array[float] = []
	var process_ms: Array[float] = []
	for tick: int in 600:
		await physics_frame
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
	physics_ms.sort(); process_ms.sort()
	var result := {"label":label,"actors":host.actors.size(),"physics_median_ms":physics_ms[300],"physics_p95_ms":physics_ms[570],"process_median_ms":process_ms[300],"process_p95_ms":process_ms[570]}
	print("APPLICATION_BENCHMARK ",JSON.stringify(result))
	return result
func run() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var host := preload("res://Scripts/Application/BattleHost.gd").new()
	host.definition = battle_definition()
	host.monster_config_definitions = {"demo_guard":"human"}
	viewport.add_child(host)
	assert(await host.deploy(records(),"baseline"))
	var baseline := await measure(host,"battle_without_shell")
	viewport.queue_free()
	await process_frame; await process_frame
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.default_battle_definition = battle_definition()
	app.save_path = "res://Tests/.runtime/integration/benchmark_"+str(Time.get_ticks_usec())+".json"
	root.add_child(app)
	app.ui.animate_panels = false
	app.start_new_game()
	for tick: int in 600:
		if app.phase=="world": break
		await physics_frame
	app.session.data.monsters = records()
	assert(app.session.save())
	var location: WorldMapLocation = app.world_map.get_location(&"bandits")
	location.state.discovered = true
	app.world_map.player.global_position = location.interaction_point()
	assert(app.world_map.interaction.begin(location))
	app.world_map.interaction.request_battle()
	for tick: int in 600:
		if app.phase=="battle": break
		await physics_frame
	assert(app.battle!=null and app.phase=="battle")
	var integrated := await measure(app.battle,"battle_with_shell")
	var result := {"baseline":baseline,"integrated":integrated,"headless":DisplayServer.get_name()=="headless"}
	var file := FileAccess.open("D:/GameJamWorkspace/Reports/ApplicationIntegration_2026-10-15/benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t")); file.close()
	app.queue_free()
	await process_frame; await process_frame
	print("APPLICATION_BENCHMARK_PASSED")
	quit()
