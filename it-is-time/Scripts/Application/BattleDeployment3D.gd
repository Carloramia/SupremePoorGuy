extends Node3D
## Deployment moves frozen assemblies as a whole; no saved creature pose is edited.
signal changed

var host: Node3D
var dragged: Node3D
var placement_error := ""
var _drag_origin := Vector3.ZERO
var _drag_pointer := Vector3.ZERO
var _drag_ground_height := 0.0
var _last_pointer := Vector2(INF,INF)
var _body_poses: Dictionary = {}
var _body_freeze: Dictionary = {}
var _process_modes: Dictionary = {}
var _moved: Array[Node3D] = []
var _ground_rids: Array[RID] = []
var _probe_exclusions: Array[RID] = []

func begin(battle: Node3D) -> void:
	host = battle
	name = "Deployment"
	for actor: Node3D in host.actors:
		for node: Node in actor.find_children("*", "", true, false):
			if node.process_mode != Node.PROCESS_MODE_INHERIT:
				_process_modes[node] = node.process_mode
				node.process_mode = Node.PROCESS_MODE_INHERIT
			if node is RigidBody3D:
				_body_freeze[node] = node.freeze
				node.freeze = true
				node.linear_velocity = Vector3.ZERO
				node.angular_velocity = Vector3.ZERO
	for body: CollisionObject3D in host.find_children("*", "CollisionObject3D", true, false):
		if body.is_in_group(&"scenario_ground"): _ground_rids.append(body.get_rid())
		else: _probe_exclusions.append(body.get_rid())
	host.cursor.set_deployment_mode(true)
	_draw_boundary()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(dragged) or not host.cursor.is_gameplay_cursor_active(): return
	update_drag()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"MouseLeft") or not host.cursor.is_gameplay_cursor_active(): return
	if is_instance_valid(dragged): place_dragged()
	else: pick_up(host.cursor.get_selected_character())
	get_viewport().set_input_as_handled()

func pick_up(actor: Node3D) -> bool:
	if is_instance_valid(dragged) or not is_instance_valid(actor) or actor not in host.actors or actor.get_faction_id() != 0: return false
	dragged = actor
	_drag_origin = actor.global_position
	_drag_pointer = host.cursor.get_mouse_ground_position()
	_last_pointer = Vector2(INF,INF)
	_body_poses.clear()
	for body: RigidBody3D in actor.find_children("*", "RigidBody3D", true, false): _body_poses[body] = body.global_transform
	var ground := _ground_at(_drag_bounds(Vector3.ZERO).get_center())
	_drag_ground_height = float(ground.position.y) if not ground.is_empty() else 0.0
	host.cursor.set_deployment_drag_target(actor)
	placement_error = ""
	_trace("deployment_pickup", {"actor":str(actor.name)})
	changed.emit()
	return true

func update_drag(force: bool = false) -> void:
	var pointer: Vector3 = host.cursor.get_mouse_ground_position()
	var horizontal := Vector2(pointer.x,pointer.z)
	if not force and horizontal.is_equal_approx(_last_pointer): return
	_last_pointer = horizontal
	var at := _drag_origin + Vector3(pointer.x-_drag_pointer.x, 0.0, pointer.z-_drag_pointer.z)
	var offset := at-_drag_origin
	var bounds := _drag_bounds(offset)
	var hit := _ground_at(bounds.get_center())
	if not hit.is_empty():
		offset.y = float(hit.position.y)-_drag_ground_height
		host.cursor.deployment_ground_height = float(hit.position.y)+host.cursor.surface_offset
	dragged.global_position = _drag_origin+offset
	for body: RigidBody3D in _body_poses:
		var pose: Transform3D = _body_poses[body]
		pose.origin += offset
		body.global_transform = pose
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	var error := validate_placement(dragged)
	if error != placement_error:
		placement_error = error
		changed.emit()

func place_dragged() -> bool:
	if not is_instance_valid(dragged): return false
	update_drag(true)
	if not placement_error.is_empty():
		_trace("deployment_rejected", {"actor":str(dragged.name),"reason":placement_error})
		changed.emit()
		return false
	_trace("deployment_placed", {"actor":str(dragged.name),"position":dragged.position})
	if not dragged.global_position.is_equal_approx(_drag_origin) and dragged not in _moved: _moved.append(dragged)
	dragged = null
	_body_poses.clear()
	host.cursor.set_deployment_drag_target(null)
	changed.emit()
	return true

func can_start() -> bool:
	return not is_instance_valid(dragged)

func complete() -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)
	host.cursor.set_deployment_mode(false)
	# Controllers cached world-space foot anchors/path samples before deployment.
	for actor: Node3D in _moved:
		for node: Node in actor.find_children("*", "", true, false):
			if node.is_in_group(&"snake_movement_controllers"): node.refresh_parts()
			elif node.is_in_group(&"leg_step_movement_controllers"): node.refresh_physics_query_cache()
	for node: Node in _process_modes:
		if is_instance_valid(node): node.process_mode = _process_modes[node]
	for body: RigidBody3D in _body_freeze:
		if is_instance_valid(body) and not body is PhysicalBodyPart3D: body.freeze = _body_freeze[body]
	queue_free()

func _drag_bounds(offset: Vector3) -> AABB:
	var bounds := AABB()
	var found := false
	for body: RigidBody3D in _body_poses:
		if not body is PhysicalBodyPart3D: continue
		for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", false, false):
			if shape.disabled or shape.shape == null: continue
			var pose: Transform3D = _body_poses[body] * body.global_transform.affine_inverse() * shape.global_transform
			pose.origin += offset
			var box := pose * shape.shape.get_debug_mesh().get_aabb()
			bounds = bounds.merge(box) if found else box
			found = true
	return bounds

func validate_placement(actor: Node3D) -> String:
	var footprint := PackedVector2Array()
	var collisions: Array[CollisionShape3D] = []
	var exclude: Array[RID] = _ground_rids.duplicate()
	for body: CollisionObject3D in actor.find_children("*", "CollisionObject3D", true, false): exclude.append(body.get_rid())
	var bounds := AABB()
	var found := false
	for shape: CollisionShape3D in actor.find_children("*", "CollisionShape3D", true, false):
		if shape.disabled or shape.shape == null or not shape.get_parent() is PhysicsBody3D: continue
		collisions.append(shape)
		if not shape.get_parent() is PhysicalBodyPart3D: continue
		var box := shape.global_transform * shape.shape.get_debug_mesh().get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
		for corner: int in 8:
			var point := host.to_local(box.get_endpoint(corner))
			footprint.append(Vector2(point.x,point.z))
	if not found: return "生物没有可用的碰撞体。"
	footprint = Geometry2D.convex_hull(footprint)
	if not Geometry2D.clip_polygons(footprint,host.deployment_polygon).is_empty(): return "完整生物必须位于蓝色友方部署区内。"
	if not Geometry2D.clip_polygons(footprint,host._floor_polygon).is_empty(): return "不能放置到战场外。"
	if host.delivery_adapter != null:
		for pit: Dictionary in host.delivery_adapter.pits:
			if not Geometry2D.intersect_polygons(footprint,pit.polygon).is_empty(): return "不能放置到坑洞中。"
		for object: Dictionary in host.delivery_adapter.layout.objects:
			if object.type in ["mud","thorns","web"] and object.get("region",{}).get("enabled",false):
				if not Geometry2D.intersect_polygons(footprint,host.delivery_adapter.shape_polygon(object,object.region)).is_empty(): return "不能放置到危险地形中。"
	var ground := _ground_at(bounds.get_center())
	if ground.is_empty(): return "当前位置没有可放置的地面。"
	for point: Vector2 in footprint:
		var hit := _ground_at(host.to_global(Vector3(point.x,host.to_local(bounds.get_center()).y,point.y)))
		if hit.is_empty() or absf(float(hit.position.y)-float(ground.position.y)) > 0.5: return "地面不连续或高度差过大。"
	for shape: CollisionShape3D in collisions:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.collision_mask = 0xFFFFFFFF
		query.exclude = exclude
		query.collide_with_areas = false
		for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,1):
			return "不能与其他生物或启用碰撞的障碍重叠。"
	return ""

func _ground_at(point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2000.0,point-Vector3.UP*2000.0,0xFFFFFFFF,_probe_exclusions)
	query.collide_with_areas = false
	for attempt: int in 16:
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): return {}
		if hit.collider.is_in_group(&"scenario_ground"): return hit
		var excluded := query.exclude
		excluded.append(hit.rid)
		query.exclude = excluded
	return {}

func _draw_boundary() -> void:
	var polygon: PackedVector2Array = host.deployment_polygon
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.15,0.6,1.0)
	material.no_depth_test = true
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for index: int in polygon.size():
		for point: Vector2 in [polygon[index],polygon[(index+1)%polygon.size()]]:
			var at: Vector3 = host.to_global(Vector3(point.x,0,point.y))
			var hit := _ground_at(at)
			if not hit.is_empty(): at.y = float(hit.position.y)
			mesh.surface_add_vertex(to_local(at+Vector3.UP*0.08))
	mesh.surface_end()
	var visual := MeshInstance3D.new()
	visual.name = "DeploymentBoundary"
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)

func _trace(event: String, detail: Dictionary) -> void:
	if is_instance_valid(host.application): host.application.trace_map_event(event,detail)
