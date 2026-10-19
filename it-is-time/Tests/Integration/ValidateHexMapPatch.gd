extends SceneTree
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const RUNTIME = preload("res://Modules/FrontierDelivery/Scripts/Map/WorldMapRuntime.gd")
const SIGHT = preload("res://Scripts/Application/HexMapSight.gd")
const BASE := "res://Content/Maps/FrontierEditor_20261019/"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("HEX_PATCH_TIMEOUT"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	CATALOG.select_version("20261019")
	var migration: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(BASE+"Migration/patch.json"))
	check(migration.payload_files_verified==123 and migration.reused_dependencies_verified==659,"verified overlay and base dependencies")
	var world := CATALOG.world()
	check(world.hex_cells.size()==10877 and world.objects.size()>630 and world.mountain_surfaces.size()==10,"full world and precise mountain surfaces")
	check(world.spawn_site_id=="layout_summoning_hut" and CATALOG.v(world.spawn).distance_to(Vector2(3220,11372))<0.01,"hut-relative entry")
	var runtime := RUNTIME.new()
	check(not runtime.blocked(runtime.player()),"new game spawn is passable")
	var hut := CATALOG.location("layout_summoning_hut")
	check(runtime.known(hut) and runtime.interaction_error(hut).is_empty(),"initial hut is visible and interactive at its authored entry")
	check(not runtime.hex.route(runtime.player(),CATALOG.v(hut.position),true).is_empty(),"hut reachable from spawn")
	var saved := runtime.snapshot()
	check(RUNTIME.valid_snapshot(saved) and RUNTIME.new(saved).snapshot().player==saved.player,"existing hex save format preserved")
	var repair_found := false
	for row: Dictionary in CATALOG.index().assets.values():
		if str(row.path).contains("left_boulder_completion"): repair_found=true
	# Runtime assets use content hashes; the source table retains the original name.
	var paths: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(BASE+"Migration/asset_paths.json"))
	for source: String in paths:
		if "left_boulder_completion" in source: repair_found=FileAccess.file_exists(paths[source])
	check(repair_found,"new boulder completion asset imported")
	for surface: Dictionary in runtime.hex.art_surfaces:
		var near: Vector2=surface._polygon[0]
		check(surface._rings.size()>0 and near.is_finite(),"precise contour "+str(surface.site_id))
	var scene := load(CATALOG.index().maps.frontier_layout.scene).instantiate() as Node2D
	root.add_child(scene)
	check(scene.has_node("Objects/layout_summoning_hut/GroundPatch"),"landmark footing installed")
	var layer_order := false
	for object: Dictionary in world.objects:
		for layer: Dictionary in object.get("source_visual",{}).get("layers",[]):
			if layer.get("z_index",0)<0:
				var holder := scene.get_node("Objects/"+str(object.id))
				for child: Node in holder.get_children():
					if child is Sprite2D and child.name!="Visual" and child.z_index<0: layer_order=true
	check(layer_order,"repair layers render below main art")
	scene.free()
	var view := preload("res://Modules/FrontierDelivery/Scripts/Map/FrontierMapView.gd").new()
	view.battle_preview_enabled=false
	view.size=Vector2(1280,720)
	root.add_child(view)
	view._layout()
	check(view._hex_fog.buffer.size==Vector2i(427,240),"fog buffer matches final UI dimensions")
	view.size=Vector2(960,540)
	view.zoom=0.35
	view._layout()
	check(view._hex_fog.buffer.size==Vector2i(320,180) and view.world_scene._faces.transform.is_equal_approx(view.world_scene.transform),"fog and mountain overlays follow resize/zoom")
	view.free()
	var count := 0
	var tilted := 0
	var ground := 0
	for id: String in CATALOG.index().maps:
		if id=="frontier_layout": continue
		var data := CATALOG.map_data(id)
		check(data.presentation.camera_pitch_degrees==-50 and data.deployment_layout.axis=="x","presentation/deployment metadata "+id)
		var battle := load(CATALOG.index().maps[id].scene_3d).instantiate() as Node3D
		root.add_child(battle)
		for object: Dictionary in data.objects:
			var part := battle.get_node_or_null("Objects/"+str(object.id)+"/Visual") as Sprite3D
			if part==null: continue
			check(part.find_children("*","CollisionShape3D",true,false).is_empty(),"scenery stays non-colliding")
			var mode: String=part.get_meta("surface_mode","")
			var axis := part.global_basis.y.normalized()
			var visual: Dictionary=object.visual
			if mode=="ground":
				ground+=1
				check(absf(axis.y)<0.0001,"ground decals remain flat")
			else:
				tilted+=1
				var angle := deg_to_rad(float(visual.get("tilt_degrees",60)))
				check(absf(axis.y-sin(angle))<0.0001,"paper tilt from ground")
				var bottom: Vector3=part.global_transform*Vector3(0,-part.texture.get_height()*0.5,0)
				var host := part.get_parent() as Node3D
				check(Vector2(bottom.x,bottom.z).distance_to(Vector2(host.global_position.x,host.global_position.z))<0.0001,"bottom contact retains X/Z")
		battle.free()
		count+=1
	check(count==41 and tilted>100 and ground>0,"all battle scenery compiled")
	# Two channels expose the first rock face without revealing objects behind it.
	var obstacle: Dictionary=SIGHT.occluder(PackedVector2Array([Vector2(10,-10),Vector2(20,-10),Vector2(20,10),Vector2(10,10)]))
	check(SIGHT.ray_distances(Vector2.ZERO,Vector2(30,0),[obstacle]).is_equal_approx(Vector2(10,20)),"near-face sight and rear-face presentation are separate")
	check(not SIGHT.visible(Vector2.ZERO,Vector2(30,0),[obstacle]),"rock never reveals terrain behind it")
	CATALOG.select_version("20261015")
	check(CATALOG.index().maps.size()==14 and CATALOG.world().objects.size()==293,"legacy map retained")
	print("HEX_MAP_PATCH_","PASSED" if failures.is_empty() else "FAILED"," checks=",checks," maps=",count," tilted=",tilted," ground=",ground)
	quit(0 if failures.is_empty() else 1)
