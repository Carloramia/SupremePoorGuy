extends "res://Scripts/Application/DeliveryBattleEnvironmentAdapter.gd"
const VISUALS=preload("res://Modules/HexFrontier/BattleVisuals.gd")
const ROOT:="res://Content/Maps/HexFrontier_20261019/"
func build_story(host: Node3D, left: Array, right: Array) -> bool:
	scale=8.0
	var map_id: String=host.story_request.get("battle_map_id","")
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"hex_battles.json"))
	for entry: Dictionary in source.maps:
		if entry.id==map_id: layout=entry; break
	if layout.is_empty(): host.last_error="事件战场ID无效。"; return false
	var renderer:=VISUALS.new()
	host.add_child(renderer)
	var scene: Node3D=renderer.build_geometry(map_id)
	renderer.free()
	if scene==null: host.last_error="事件战场美术无法加载。"; return false
	var objects:=Node3D.new(); objects.name="Objects"; scene.add_child(objects)
	for object: Dictionary in layout.objects:
		var origin:=scene.get_node_or_null(NodePath(str(object.id))) as Node3D
		if origin!=null: origin.reparent(objects,false)
		else: origin=Node3D.new(); origin.name=object.id; origin.position=Vector3(object.position[0],object.get("height",0),object.position[1]); objects.add_child(origin)
		if object.get("collision",{}).get("enabled",false):
			var body:=StaticBody3D.new(); body.name="collision"; origin.add_child(body)
			var shape:=CollisionShape3D.new(); shape.shape=_volume(object,object.collision,origin.position); body.add_child(shape)
		if object.get("region",{}).get("enabled",false):
			var area:=Area3D.new(); area.name="region"; area.collision_layer=0; origin.add_child(area)
			var shape:=CollisionShape3D.new(); shape.name="Shape"; shape.shape=_volume(object,object.region,origin.position); area.add_child(shape)
	var start:=deg_to_rad(30.0 if layout.orientation=="pointy" else 0.0)
	for i: int in 6: floor_polygon.append(Vector2.from_angle(start+TAU*i/6)*float(layout.radius)*scale)
	for object: Dictionary in layout.objects:
		if object.type=="pit": pits.append({"object":object,"polygon":shape_polygon(object,object.region)})
	var ground:=_floor(); scene.add_child(ground); ground.scale=Vector3.ONE/scale
	scene.scale=Vector3.ONE*scale
	host._geometry=scene; host._floor_polygon=floor_polygon
	var radius: float=float(layout.radius)*scale
	host.deployment_polygon=PackedVector2Array([Vector2(-radius*.8,-radius*.65),Vector2(-1,-radius*.65),Vector2(-1,radius*.65),Vector2(-radius*.8,radius*.65)])
	for record: Dictionary in left:
		var positioned:=place(record,false)
		if positioned.is_empty(): scene.free(); host._geometry=null; host.last_error="己方怪物无法安全部署。"; return false
		host._deployment.append(positioned)
	for record: Dictionary in right:
		var positioned:=place(record,true)
		if positioned.is_empty(): scene.free(); host._geometry=null; host.last_error="敌方怪物无法安全部署。"; return false
		host._enemy_positions.append(positioned)
	for title: String in ["Ground"]: host.get_node(title).free()
	return true

func _volume(object: Dictionary, shape_data: Dictionary, offset: Vector3) -> ConvexPolygonShape3D:
	var points:=PackedVector3Array()
	var contour:=shape_polygon(object,shape_data)
	var height: float=maxf(.2,float(shape_data.get("height",object.get("max_height",3))))
	for p: Vector2 in contour:
		points.append(Vector3(p.x/scale,0,p.y/scale)-offset)
		points.append(Vector3(p.x/scale,height,p.y/scale)-offset)
	var shape:=ConvexPolygonShape3D.new(); shape.points=points
	return shape

func place(record: Dictionary, enemy: bool) -> Dictionary:
	var bounds := FACTORY.local_bounds(record)
	var facing := PI if enemy else 0.0
	var basis := Basis(Vector3.UP,facing)
	var rotated := Transform3D(basis,Vector3.ZERO)*bounds
	var radius := float(layout.radius)*scale
	var centre_gap := maxf(1.0,radius*DEPLOYMENT_CENTRE_GAP_RATIO)
	# Fit the whole body in a central half, including asymmetrical saved snake poses.
	var minimum := Vector2(centre_gap if enemy else -radius*0.78,-radius*0.60)+Vector2(rotated.size.x,rotated.size.z)*0.5
	var maximum := Vector2(radius*0.78 if enemy else -centre_gap,radius*0.60)-Vector2(rotated.size.x,rotated.size.z)*0.5
	if minimum.x>maximum.x or minimum.y>maximum.y: return {}
	var preferred := Vector2(radius*0.42*(1.0 if enemy else -1.0),0.0).clamp(minimum,maximum)
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
