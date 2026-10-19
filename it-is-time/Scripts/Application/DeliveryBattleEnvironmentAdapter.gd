extends RefCounted
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const DEPLOYMENT_X_RATIO := 0.45
const DEPLOYMENT_Z_RATIO := 0.35
const DEPLOYMENT_OFFSET_RATIO := 0.25
const DEPLOYMENT_CENTRE_GAP_RATIO := 0.03
var scale := 8.0
var layout := {}
var floor_polygon := PackedVector2Array()
var pits: Array[Dictionary] = []
var occupied: Array[AABB] = []

func build(host: Node3D, records: Array) -> bool:
	scale = host.delivery_settings.unit_scale
	if not is_finite(scale) or scale<=0.0: host.last_error = "战场单位倍率无效。"; return false
	var request: Dictionary = host.delivery_request
	var error: String = host.delivery_settings.availability_error(str(request.get("enemy_config_id","")))
	if not error.is_empty(): host.last_error = error; return false
	layout = CATALOG.map_data(str(request.get("battle_map_id","")))
	if layout.get("kind")!="battle": host.last_error = "战场ID无效。"; return false
	var packed := load(CATALOG.index().maps[layout.id].scene_3d) as PackedScene
	if packed==null: host.last_error = "战场资源无法加载。"; return false
	var scene: Node3D = packed.instantiate()
	scene.set_script(null)
	scene.name = "DeliveryEnvironment"
	for name: String in ["Ground","Camera","WorldEnvironment","Party"]:
		scene.get_node(name).free()
	scene.scale = Vector3.ONE*scale
	# Transparent ground must render before interior decals, including in orthographic views.
	for visual: MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		if visual.name=="GroundVisual" or visual.get_parent().name=="ExteriorBackground":
			visual.material_override = visual.material_override.duplicate()
			visual.material_override.render_priority = -120 if visual.name=="GroundVisual" else -125 if visual.name=="Halo" else -124
	for area: Area3D in scene.find_children("*","Area3D",true,false):
		area.monitoring = false
		area.monitorable = false
	var angle := deg_to_rad(30.0 if layout.orientation=="pointy" else 0.0)
	for index: int in 6: floor_polygon.append(Vector2.from_angle(angle+TAU*index/6)*float(layout.radius)*scale)
	for object: Dictionary in layout.objects:
		if object.type=="pit": pits.append({"object":object,"polygon":shape_polygon(object,object.region)})
	var ground := _floor()
	scene.add_child(ground)
	# Ground vertices are already in world units, unlike the preserved source artwork.
	ground.scale = Vector3.ONE/scale
	host._geometry = scene
	host._floor_polygon = floor_polygon
	var deployment := {}
	for object: Dictionary in layout.objects:
		if object.type=="deployment" and (request.get("deployment_id","").is_empty() or object.id==request.deployment_id): deployment=object; break
	if deployment.is_empty(): host.last_error = "战场没有对应的玩家部署区域。"; return false
	var radius := float(layout.radius)*scale
	var gap := maxf(1.0,radius*DEPLOYMENT_CENTRE_GAP_RATIO)
	host.deployment_polygon = PackedVector2Array([Vector2(-radius*DEPLOYMENT_X_RATIO,-radius*DEPLOYMENT_Z_RATIO),Vector2(-gap,-radius*DEPLOYMENT_Z_RATIO),Vector2(-gap,radius*DEPLOYMENT_Z_RATIO),Vector2(-radius*DEPLOYMENT_X_RATIO,radius*DEPLOYMENT_Z_RATIO)])
	for record: Dictionary in records:
		var placed := place(record,false)
		if placed.is_empty(): host.last_error = "地图中部左侧无法安全放入出战队伍，请减少队伍或调整战场单位倍率。"; return false
		host._deployment.append(placed)
	var roster: EnemyRosterData = host.delivery_settings.enemy_rosters[request.enemy_config_id]
	host.enemy_definitions.assign(roster.definitions)
	var order: Array[int] = []
	var areas := {}
	for index: int in roster.definitions.size():
		order.append(index)
		var bounds := FACTORY.local_bounds(FACTORY.template(roster.definitions[index]))
		areas[index]=bounds.size.x*bounds.size.z
	if CATALOG.is_hex():
		# Place large bodies before small ones; preserve roster/actor indices in the result.
		order.sort_custom(func(a,b): return a<b if is_equal_approx(areas[a],areas[b]) else areas[a]>areas[b])
	var positions := {}
	for index: int in order:
		var species: String=roster.definitions[index]
		var placed := place(FACTORY.template(species),true)
		if placed.is_empty(): host.last_error = "地图中部右侧没有足够的合法敌方部署位置。"; return false
		positions[index]=placed
	for index: int in roster.definitions.size(): host._enemy_positions.append(positions[index])
	for title: String in ["Ground"]: host.get_node(title).free()
	return true

func shape_polygon(object: Dictionary, shape: Dictionary) -> PackedVector2Array:
	var local: Array = shape.get("points",[]).duplicate()
	var half := CATALOG.v(shape.size)*0.5
	if shape.shape=="circle":
		local.clear()
		for index: int in 32: local.append([cos(TAU*index/32)*half.x,sin(TAU*index/32)*half.y])
	elif local.is_empty(): local=[[-half.x,-half.y],[half.x,-half.y],[half.x,half.y],[-half.x,half.y]]
	var result := PackedVector2Array()
	for point: Array in local: result.append(CATALOG.world_point(object,CATALOG.v(point).rotated(deg_to_rad(shape.rotation))+CATALOG.v(shape.offset))*scale)
	return result

func _floor() -> StaticBody3D:
	var ground := StaticBody3D.new()
	ground.name = "PhysicalGround"
	ground.add_to_group(&"scenario_ground")
	var faces := PackedVector3Array()
	var radius := float(layout.radius)*scale
	# Small cells allow geometric holes without triangulating a polygon containing inner rings.
	var step := scale
	for x: float in range(-ceili(radius/step),ceili(radius/step)):
		for z: float in range(-ceili(radius/step),ceili(radius/step)):
			var tile := PackedVector2Array([Vector2(x,z),Vector2(x+1,z),Vector2(x+1,z+1),Vector2(x,z+1)])
			for index: int in tile.size(): tile[index]*=step
			var pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(tile,floor_polygon)
			for pit: Dictionary in pits:
				var next: Array[PackedVector2Array] = []
				for piece: PackedVector2Array in pieces: next.append_array(Geometry2D.clip_polygons(piece,pit.polygon))
				pieces = next
			for piece: PackedVector2Array in pieces: _triangles(piece,0.0,faces)
	for pit: Dictionary in pits:
		var depth := maxf(float(pit.object.region.get("depth",2.0))*scale,1.0)
		_triangles(pit.polygon,-depth,faces)
		for index: int in pit.polygon.size():
			var a: Vector2 = pit.polygon[index]
			var b: Vector2 = pit.polygon[(index+1)%pit.polygon.size()]
			faces.append_array(PackedVector3Array([Vector3(a.x,0,a.y),Vector3(b.x,-depth,b.y),Vector3(b.x,0,b.y),Vector3(a.x,0,a.y),Vector3(a.x,-depth,a.y),Vector3(b.x,-depth,b.y)]))
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision.shape = shape
	ground.add_child(collision)
	return ground

func _triangles(polygon: PackedVector2Array, y: float, faces: PackedVector3Array) -> void:
	var indices := Geometry2D.triangulate_polygon(polygon)
	for index: int in range(0,indices.size(),3):
		var a := polygon[indices[index]]
		var b := polygon[indices[index+1]]
		var c := polygon[indices[index+2]]
		if (b-a).cross(c-a)<0.0: var swap:=b; b=c; c=swap
		# Godot front faces use clockwise winding when viewed from above.
		faces.append_array(PackedVector3Array([Vector3(a.x,y,a.y),Vector3(b.x,y,b.y),Vector3(c.x,y,c.y)]))

func place(record: Dictionary, enemy: bool) -> Dictionary:
	var bounds := FACTORY.local_bounds(record)
	var facing := PI if enemy else 0.0
	var basis := Basis(Vector3.UP,facing)
	var rotated := Transform3D(basis,Vector3.ZERO)*bounds
	var radius := float(layout.radius)*scale
	var centre_gap := maxf(1.0,radius*DEPLOYMENT_CENTRE_GAP_RATIO)
	# Fit the whole body in a central half, including asymmetrical saved snake poses.
	var minimum := Vector2(centre_gap if enemy else -radius*DEPLOYMENT_X_RATIO,-radius*DEPLOYMENT_Z_RATIO)+Vector2(rotated.size.x,rotated.size.z)*0.5
	var maximum := Vector2(radius*DEPLOYMENT_X_RATIO if enemy else -centre_gap,radius*DEPLOYMENT_Z_RATIO)-Vector2(rotated.size.x,rotated.size.z)*0.5
	if minimum.x>maximum.x or minimum.y>maximum.y: return {}
	var preferred := Vector2(radius*DEPLOYMENT_OFFSET_RATIO*(1.0 if enemy else -1.0),0.0).clamp(minimum,maximum)
	var xs := _deployment_axis(minimum.x,maximum.x,preferred.x,maxf(2.0,scale*0.5))
	var zs := _deployment_axis(minimum.y,maximum.y,preferred.y,maxf(rotated.size.z+3.0,scale))
	var candidates: Array[Vector2] = []
	# Prefer a front line along Z before putting allies behind one another along X.
	for x: float in xs:
		for z: float in zs: candidates.append(Vector2(x,z))
	for centre: Vector2 in candidates:
		var at := Vector3(centre.x-rotated.get_center().x,0.2-rotated.position.y,centre.y-rotated.get_center().z)
		var world := AABB(rotated.position+at,rotated.size)
		var legal := true
		for corner: int in 8:
			var point := world.get_endpoint(corner)
			if not Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),floor_polygon): legal=false; break
		if not legal: continue
		var rectangle := PackedVector2Array([Vector2(world.position.x,world.position.z),Vector2(world.end.x,world.position.z),Vector2(world.end.x,world.end.z),Vector2(world.position.x,world.end.z)])
		for pit: Dictionary in pits:
			if not Geometry2D.intersect_polygons(rectangle,pit.polygon).is_empty(): legal=false; break
		if not legal: continue
		for obstacle: Dictionary in layout.objects:
			if obstacle.get("collision",{}).get("enabled",false):
				if not Geometry2D.intersect_polygons(rectangle,shape_polygon(obstacle,obstacle.collision)).is_empty(): legal=false; break
			if obstacle.type in ["mud","thorns","web"] and obstacle.get("region",{}).get("enabled",false):
				if not Geometry2D.intersect_polygons(rectangle,shape_polygon(obstacle,obstacle.region)).is_empty(): legal=false; break
		if not legal: continue
		for other: AABB in occupied:
			if world.grow(0.5).intersects(other): legal=false; break
		if legal:
			occupied.append(world)
			return {"position":at,"facing":facing}
	return {}

func _deployment_axis(minimum: float, maximum: float, preferred: float, spacing: float) -> Array[float]:
	var values: Array[float] = [preferred]
	for index: int in range(1,ceili((maximum-minimum)/spacing)+1):
		for direction: float in [-1.0,1.0]:
			var value := preferred+direction*index*spacing
			if value>=minimum and value<=maximum: values.append(value)
	for edge: float in [minimum,maximum]:
		if edge not in values: values.append(edge)
	return values
