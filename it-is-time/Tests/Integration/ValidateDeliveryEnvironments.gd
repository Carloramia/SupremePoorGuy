extends SceneTree
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const ADAPTER = preload("res://Scripts/Application/DeliveryBattleEnvironmentAdapter.gd")
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("ENVIRONMENT_CHECK ",ok," ",message)
	if not ok: failed=true; push_error(message)
func run() -> void:
	var count := 0
	for id: String in CATALOG.index().maps:
		if CATALOG.map_data(id).kind!="battle": continue
		var host := preload("res://Scripts/Application/BattleHost.gd").new()
		host.delivery_settings = preload("res://Resources/Application/FrontierDeliveryBattle.tres").duplicate(true)
		var roster := EnemyRosterData.new()
		roster.definitions.assign(["human","wolf","snake","spider"])
		host.delivery_settings.enemy_rosters["deployment_test"] = roster
		# Rat maps stay disabled in gameplay; use a local mixed roster for geometry checks.
		host.delivery_request = {"battle_map_id":id,"enemy_config_id":"deployment_test","deployment_id":""}
		root.add_child(host)
		var records: Array = []
		for species: String in ["human","stump_beast","wolf","snake","horned_beast","spider"]: records.append(FACTORY.template(species))
		var adapter := ADAPTER.new()
		var built := adapter.build(host,records)
		check(built,id+" six party slots: "+host.last_error)
		if not built: host.queue_free(); await process_frame; continue
		_check_deployment(adapter,host,records)
		host.add_child(host._geometry)
		await physics_frame
		await physics_frame
		_check_parts(host._geometry,adapter.layout)
		print("GROUND_BODY ",host._geometry.get_node("PhysicalGround").global_transform," faces=",host._geometry.get_node("PhysicalGround").get_child(0).shape.get_faces().size()," paused=",paused)
		var state := host.get_world_3d().direct_space_state
		var ray := PhysicsRayQueryParameters3D.create(Vector3(0.37,20,0.41),Vector3(0.37,-50,0.41),1)
		var hit := state.intersect_ray(ray)
		print("GROUND_RAY ",id," ",hit)
		check(not hit.is_empty() and absf(hit.position.y)<0.01,id+" real ground y=0")
		for pit: Dictionary in adapter.pits:
			var centre := CATALOG.v(pit.object.position)*adapter.scale
			ray.from = Vector3(centre.x,2,centre.y)
			ray.to = Vector3(centre.x,-100,centre.y)
			hit = state.intersect_ray(ray)
			print("PIT_RAY ",id," ",hit)
			check(not hit.is_empty() and hit.position.y< -1.0,id+" pit is a physical hole")
		var navigation := NavigationRegion3D.new()
		navigation.navigation_mesh = NavigationMesh.new()
		navigation.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		host.remove_child(host._geometry)
		navigation.add_child(host._geometry)
		host.add_child(navigation)
		var completed: Array = []
		navigation.bake_finished.connect(func():completed.append(true),CONNECT_ONE_SHOT)
		navigation.bake_navigation_mesh(false)
		for tick: int in 120:
			if not completed.is_empty(): break
			await process_frame
		check(navigation.navigation_mesh.get_polygon_count()>0,id+" navigation bake")
		print("DELIVERY_ENVIRONMENT ",id," polygons=",navigation.navigation_mesh.get_polygon_count()," pits=",adapter.pits.size())
		host.queue_free()
		await process_frame
		await process_frame
		count+=1
	check(count==13,"All 13 native battle environments checked")
	var small := ADAPTER.new()
	small.layout = CATALOG.map_data("camp_battle_01")
	small.scale = 1.0
	check(small.place(FACTORY.template("snake"),false).is_empty() and small.occupied.is_empty(),"Oversized creatures are rejected without crossing the centre or falling back to the map edge")
	print("DELIVERY_ENVIRONMENTS_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _check_deployment(adapter: RefCounted, host: Node3D, records: Array) -> void:
	var radius: float = adapter.layout.radius*adapter.scale
	var previous: Array[AABB] = []
	var ok := true
	for index: int in adapter.occupied.size():
		var bounds: AABB = adapter.occupied[index]
		var enemy := index>=records.size()
		var placed: Dictionary = host._enemy_positions[index-records.size()] if enemy else host._deployment[index]
		ok = ok and (bounds.position.x>0.0 if enemy else bounds.end.x<0.0)
		ok = ok and absf(bounds.position.x)<=radius*0.45+0.001 and absf(bounds.end.x)<=radius*0.45+0.001
		ok = ok and absf(bounds.position.z)<=radius*0.35+0.001 and absf(bounds.end.z)<=radius*0.35+0.001
		ok = ok and is_equal_approx(float(placed.facing),PI if enemy else 0.0)
		for other: AABB in previous: ok = ok and not bounds.grow(0.5).intersects(other)
		previous.append(bounds)
		var rectangle := PackedVector2Array([Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.end.x,bounds.position.z),Vector2(bounds.end.x,bounds.end.z),Vector2(bounds.position.x,bounds.end.z)])
		for object: Dictionary in adapter.layout.objects:
			if object.type in ["mud","thorns","web","pit"] and object.get("region",{}).get("enabled",false):
				ok = ok and Geometry2D.intersect_polygons(rectangle,adapter.shape_polygon(object,object.region)).is_empty()
	check(ok,adapter.layout.id+" mixed creatures spawn left/right near centre, face opponents and avoid overlap/hazards")
	print("CENTRAL_DEPLOYMENT ",adapter.layout.id," allies=",host._deployment," enemies=",host._enemy_positions)

func _check_parts(environment: Node3D, definition: Dictionary) -> void:
	var count := 0
	var ok := true
	for object: Dictionary in definition.objects:
		var origin := environment.get_node("Objects/"+str(object.id)) as Node3D
		if object.type == "edge_decoration":
			ok = ok and origin.get_node_or_null("Visual") != null and origin.get_node_or_null("PhysicalPart") == null
			continue
		if str(object.visual.asset).is_empty(): continue
		var id: String = CATALOG.index().battle_art.object_assets.get(definition.id,{}).get(object.id,object.visual.asset)
		var part := origin.get_node_or_null("Visual") as MeshInstance3D
		if part == null: check(false,object.id+" missing source visual"); ok=false; continue
		ok = ok and origin.get_node_or_null("PhysicalPart") == null and part.mesh is PlaneMesh
		ok = ok and origin.position.is_equal_approx(Vector3(object.position[0],object.get("height",0),object.position[1]))
		ok = ok and is_equal_approx(origin.rotation.y,-deg_to_rad(float(object.rotation)))
		var material := part.material_override as StandardMaterial3D
		ok = ok and is_equal_approx(material.albedo_color.a,object.visual.opacity)
		ok = ok and part.visible == (object.visual.visible and not object.get("layout_review_only",false))
		var size := CATALOG.v(object.visual.size)
		var art: Dictionary = CATALOG.index().battle_art.assets[id]
		if art.get("demo_art",false):
			var fit := minf(size.x/float(art.width),size.y/float(art.height))
			size = Vector2(art.width,art.height)*fit
		ok = ok and part.mesh.size.is_equal_approx(size)
		ok = ok and material.albedo_texture.resource_path == art.get("render_path",art.path)
		ok = ok and part.global_basis.y.normalized().dot(Vector3.UP)>0.999
		var legacy := origin.get_node_or_null("collision") as StaticBody3D
		if legacy != null:
			ok = ok and legacy.collision_layer == 0
			for shape: CollisionShape3D in legacy.find_children("*","CollisionShape3D",true,false): ok = ok and shape.disabled
		count += 1
	check(ok,definition.id+" source references, dimensions, opacity, orientation and disabled collisions")
	print("BATTLE_SOURCE_SCENERY ",definition.id," count=",count)
