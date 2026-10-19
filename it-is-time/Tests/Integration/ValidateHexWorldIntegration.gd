extends SceneTree
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const RUNTIME = preload("res://Modules/FrontierDelivery/Scripts/Map/WorldMapRuntime.gd")
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const NAV = preload("res://Scripts/Application/HexWorldNavigation.gd")
const BASE := "res://Content/Maps/FrontierEditor_20261019/Runtime/"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("HEX_INTEGRATION_TIMEOUT"); quit(1))
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	CATALOG.select_version("20261015")
	var legacy := RUNTIME.new()
	var old := legacy.snapshot()
	old.erase("map_version")
	check(CATALOG.world().objects.size()==293 and RUNTIME.valid_snapshot(old),"legacy data and unversioned saves remain valid")
	CATALOG.select_version("20261019")
	check(RUNTIME.valid_snapshot(old),"legacy validation does not use the active new-world bounds")
	var runtime := RUNTIME.new()
	var world := CATALOG.world()
	var graph: RefCounted=runtime.hex
	graph.sync(runtime.data,0)
	check(CATALOG.v(world.spawn).is_equal_approx(Vector2(3220,11372)) and CATALOG.index().maps.size()==42,"new world and all 41 battles registered")
	check(graph.cells.size()==10877 and graph.nav.get_point_count()==10877,"navigation uses exactly the source hex cells")
	for coordinate: Vector2i in graph.cells:
		check(graph.axial(graph.centre(coordinate))==coordinate,"hex coordinate round trip "+str(coordinate))
		var cell: Dictionary=graph.cells[coordinate]
		if cell.get("control")=="outside" or cell.get("feature") in ["wall","river"]:
			check(not graph.can_pass(coordinate),"permanent barriers stay closed")
	check(not runtime.blocked(runtime.player()),"authored spawn is walkable")
	var hut := CATALOG.location("layout_summoning_hut")
	check(hut.location_id=="summoning_hut","summon UI retains its existing location interface")
	var path: PackedVector2Array=graph.route(runtime.player(),CATALOG.v(hut.position),true)
	check(not path.is_empty(),"spawn has a route to the summon hut")
	for point: Vector2 in path: check(graph.can_pass(graph.axial(point)),"hut path remains on walkable cells")
	check(not runtime.visible_hexes.is_empty() and not runtime.data.explored_cells.is_empty(),"initial visible and explored cells recorded")
	var restored := RUNTIME.new(runtime.snapshot())
	check(restored.data.explored_cells==runtime.data.explored_cells,"hex exploration survives reload")
	var invalid := runtime.snapshot()
	invalid.map_version=null
	check(not RUNTIME.valid_snapshot(invalid),"invalid map version is rejected without a typed assignment error")
	invalid=runtime.snapshot()
	invalid.explored_cells=["99999,99999"]
	check(not RUNTIME.valid_snapshot(invalid),"unknown exploration cells are rejected")
	var save := SESSION.new()
	save.data.delivery_map_version="20261019"
	save.save_path="D:/GameJamWorkspace/RuntimeChecks/HexMapIntegration/session_"+str(Time.get_ticks_usec())+".json"
	check(save.save_delivery_world(runtime.snapshot()),"new-world snapshot commits to unified save")
	var loaded := SESSION.new()
	loaded.save_path=save.save_path
	check(loaded.load_save() and loaded.delivery_version()=="20261019","new save reload selects explicit map version")
	var corrupt: Dictionary=loaded.data.duplicate(true)
	corrupt.worlds.frontier_layout.map_version="20261015"
	check(not loaded._valid_save(corrupt),"mixed-version snapshot is rejected")
	var old_session := SESSION.new()
	old_session.save_path=save.save_path+"_old.json"
	check(old_session.save_delivery_world(old),"old unversioned snapshot can still be saved")
	check(old_session.delivery_snapshot().player==old.player and CATALOG.version=="20261015","old session retains old position and map")
	CATALOG.select_version("20261019")
	_test_constraints(world)
	var settings := load(BASE+"BattleSettings.tres") as DeliveryBattleSettings
	var enabled := 0
	var blocked := 0
	for object: Dictionary in world.objects:
		if object.type!="camp": continue
		var error := settings.availability_error(object.enemy_config_id)
		if error.is_empty(): enabled+=1
		else: blocked+=1; check(not object.encounter.enabled,"unbound species never auto-start battles")
		if int(object.get("difficulty",0))==3: check(not object.encounter.enabled,"tier III stays manual")
	check(enabled==31 and blocked==8,"31 bound camps and 8 explicitly blocked camps")
	var count := 0
	var parts := 0
	for id: String in CATALOG.index().maps:
		if id=="frontier_layout": continue
		var map := CATALOG.map_data(id)
		check(map.kind=="battle","battle data normalized "+id)
		var scene := load(CATALOG.index().maps[id].scene_3d) as PackedScene
		check(scene!=null,"battle scene loads "+id)
		if scene==null: continue
		var instance := scene.instantiate()
		for title: String in ["Ground","GroundVisual","ExteriorBackground","Objects","Camera","WorldEnvironment","Party"]:
			check(instance.has_node(title),"battle adapter contract "+id+"/"+title)
		for node: Node in instance.find_children("PhysicalPart","",true,false):
			var mesh := node.get_node("Visual") as MeshInstance3D
			check(mesh.mesh.get_surface_count()==3 and node.get_child_count()==1,"thick paper scenery has no decoration collision")
			parts+=1
		instance.free()
		count+=1
	check(count==41 and parts>500,"all battles and thick scenery are available")
	print("HEX_WORLD_INTEGRATION checks=",checks," failures=",failures.size()," battles=",count," paper_instances=",parts)
	if failures.is_empty(): print("HEX_WORLD_INTEGRATION_PASSED")
	CATALOG.select_version("20261015")
	quit(0 if failures.is_empty() else 1)

func _test_constraints(world: Dictionary) -> void:
	var synthetic := world.duplicate(false)
	synthetic.hex_cells=[{"q":0,"r":0,"region":"grass"},{"q":1,"r":0,"region":"grass","feature":"breakable","control":"breakable","obstacle_ids":["a","b"]},
		{"q":2,"r":0,"region":"grass","feature":"wall","obstacle_ids":["a"]}]
	var nav := NAV.new(synthetic)
	var snapshot := {"destroyed":["a"],"enabled_conditions":[]}
	nav.sync(snapshot,1)
	check(not nav.can_pass(Vector2i(1,0)),"shared stone cell stays blocked after only one owner breaks")
	snapshot.destroyed.append("b")
	nav.sync(snapshot,1)
	check(nav.can_pass(Vector2i(1,0)) and not nav.can_pass(Vector2i(2,0)),"all owners clear the gate, never a permanent mountain")
	synthetic.hex_cells=[{"q":0,"r":0,"region":"grass"},{"q":1,"r":0,"region":"grass","feature":"wall"},{"q":2,"r":0,"region":"grass"}]
	nav=NAV.new(synthetic)
	check(not nav.line_of_sight(nav.centre(Vector2i(0,0)),nav.centre(Vector2i(2,0))),"mountains occlude distant cells")
	synthetic.hex_cells[1].region="pit"
	nav=NAV.new(synthetic)
	check(nav.line_of_sight(nav.centre(Vector2i(0,0)),nav.centre(Vector2i(2,0))),"small pit clusters block movement without blocking sight")
