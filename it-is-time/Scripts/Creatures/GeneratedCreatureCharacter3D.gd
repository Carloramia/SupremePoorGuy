@tool
extends "res://Scripts/Creatures/PhysicalCharacterController.gd"

const PERFORMANCE_STATS = preload("res://Scripts/Debug/ControlPerformanceStats.gd")
var _control_perf: PERFORMANCE_STATS = PERFORMANCE_STATS.new()

const PART_SCENE: PackedScene = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
const DAMAGE_SCENE: PackedScene = preload("res://Scenes/Creatures/Components/CharacterDamageController3D.tscn")
const GEOMETRY = preload("res://Scripts/Creatures/CreatureBoxGeometry.gd")
const BODY_PART = preload("res://Scripts/Creatures/PhysicalBodyParts.gd")

@export_group("Generation")
@export_tool_button("生成框架与物理角色", "Node3D") var generate_character_button: Callable:
	get:
		return generate_creature
@export var generate_on_ready: bool = true
@export var show_framework: bool = false:
	set(value):
		show_framework = value
		var generator := get_node_or_null("CreatureGenerator") as Node3D
		if generator != null:
			generator.visible = value

@export_group("Physical Parts")
## Mass is density times volume, clamped to limit the mass ratio of small Neck and large Torso blocks.
@export_range(0.01, 100.0, 0.01, "or_greater") var mass_density: float = 1.0
@export_range(0.01, 10.0, 0.01, "or_greater") var minimum_part_mass: float = 0.1
@export_range(0.01, 100.0, 0.01, "or_greater") var maximum_part_mass: float = 10.0
@export_range(0.0, 10.0, 0.01, "or_greater") var part_linear_damping: float = 0.15
@export_range(0.0, 10.0, 0.01, "or_greater") var part_angular_damping: float = 1.0

@export_group("Joint Settings")
@export_range(0.0, 90.0, 0.1) var limb_angular_limit_degrees: float = 35.0
@export_range(0.0, 90.0, 0.1) var neck_angular_limit_degrees: float = 20.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var angular_spring_stiffness: float = 30.0
@export_range(0.0, 100.0, 0.1, "or_greater") var angular_spring_damping: float = 5.0

@export_group("Body Segments")
## One connected segment grows from each generated SubTorso.
@export var segmented_torso_enabled: bool = true
@export var segment_free_rotation: bool = false
@export_range(0.0, 90.0, 0.5) var segment_angular_limit_degrees: float = 25.0
@export_range(0.0, 1000.0, 0.1) var segment_angular_stiffness: float = 8.0
@export_range(0.0, 100.0, 0.1) var segment_angular_damping: float = 5.0

var _last_generation_succeeded: bool = false
var _rebuilding: bool = false

func _ensure_control_performance_stats() -> void:
	# An editor script reload can leave a member uninitialized on an existing node.
	if not is_instance_valid(_control_perf):
		_control_perf = PERFORMANCE_STATS.new()
		if is_inside_tree(): _control_perf.register(self)

func _ready() -> void:
	_ensure_control_performance_stats()
	_control_perf.register(self)
	super._ready()
	_connect_generator()
	if not Engine.is_editor_hint():
		if generate_on_ready:
			call_deferred("generate_creature")
		elif has_node("GeneratedParts"):
			_configure_body_part_collision_exceptions()
			_reset_damage_controller()
			_activate_parts(get_node("GeneratedParts"))

func _connect_generator() -> void:
	var generator := get_node_or_null("CreatureGenerator") as Node3D
	if generator == null:
		return
	generator.visible = show_framework
	if not generator.is_connected(&"framework_generated", _on_framework_generated):
		generator.connect(&"framework_generated", _on_framework_generated)

func generate_creature() -> bool:
	_ensure_control_performance_stats()
	var started: int = _control_perf.start()
	var result: bool = _perf_impl_generate_creature()
	_control_perf.finish(&"generation_total", started)
	return result

func _perf_impl_generate_creature() -> bool:
	if not is_inside_tree() or _rebuilding:
		return false
	var generator := get_node_or_null("CreatureGenerator") as Node3D
	if generator == null or not _valid_settings(generator):
		push_warning("[generated_creature] Invalid settings or scaled character/generator; previous physics retained.")
		return false
	_connect_generator()
	_last_generation_succeeded = false
	if not generator.generate_torso():
		return false
	return _last_generation_succeeded

func _valid_settings(generator: Node3D) -> bool:
	if not global_basis.get_scale().is_equal_approx(Vector3.ONE) or not generator.transform.basis.get_scale().is_equal_approx(Vector3.ONE):
		return false
	for value: float in [mass_density, minimum_part_mass, maximum_part_mass, part_linear_damping, part_angular_damping, limb_angular_limit_degrees, neck_angular_limit_degrees, angular_spring_stiffness, angular_spring_damping]:
		if not is_finite(value) or value < 0.0:
			return false
	return mass_density > 0.0 and minimum_part_mass > 0.0 and maximum_part_mass >= minimum_part_mass

func _on_framework_generated(plan: Dictionary) -> void:
	_ensure_control_performance_stats()
	var started: int = _control_perf.start()
	_perf_impl__on_framework_generated(plan)
	_control_perf.finish(&"physics_assembly", started)

func _perf_impl__on_framework_generated(plan: Dictionary) -> void:
	if _rebuilding:
		return
	var generator := get_node("CreatureGenerator") as Node3D
	if not _valid_settings(generator):
		push_warning("[generated_creature] Physics assembly requires unit scale and finite settings.")
		return
	_rebuilding = true
	var blueprint_started: int = _control_perf.start()
	var blueprint := _build_blueprint(plan, float(generator.torso_connection_distance))
	_control_perf.finish(&"blueprint", blueprint_started)
	if blueprint.is_empty():
		push_warning("[generated_creature] Frame connectivity could not be converted; previous physics retained.")
		_rebuilding = false
		return
	var bodies_started: int = _control_perf.start()
	var staging := _instantiate_blueprint(blueprint, generator.transform)
	_control_perf.finish(&"instantiate_bodies_joints", bodies_started)
	if staging == null:
		_rebuilding = false
		return
	var previous := get_node_or_null("GeneratedParts")
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	staging.name = "GeneratedParts"
	add_child(staging)
	var scene_owner := _scene_owner()
	staging.owner = scene_owner
	for part: Node in staging.get_children():
		part.owner = scene_owner
		if part.name == &"Joints":
			for joint: Node in part.get_children():
				joint.owner = scene_owner
	_control_perf.count(&"generated_parts", blueprint.parts.size())
	_control_perf.count(&"generated_joints", blueprint.connections.size())
	var exceptions_started: int = _control_perf.start()
	_configure_body_part_collision_exceptions()
	_control_perf.finish(&"collision_exceptions", exceptions_started)
	if body_parts_ignore_each_other:
		_control_perf.count(&"collision_exception_pairs", blueprint.parts.size() * (blueprint.parts.size() - 1) / 2)
	if not Engine.is_editor_hint():
		_reset_damage_controller()
		_activate_parts(staging)
	else:
		EditorInterface.mark_scene_as_unsaved()
	var collision_audit := get_internal_collision_diagnostics()
	print("[generated_collision] ", collision_audit)
	if body_parts_ignore_each_other and collision_audit.missing_pairs > 0:
		push_warning("[generated_collision] Internal collision exceptions are incomplete.")
	_last_generation_succeeded = true
	_rebuilding = false
	print("[generated_creature] character=%s parts=%d joints=%d connected=true internal_collisions_ignored=%s" % [name, blueprint.parts.size(), blueprint.connections.size(), body_parts_ignore_each_other])

func _scene_owner() -> Node:
	if Engine.is_editor_hint():
		var edited := get_tree().edited_scene_root
		if edited != null and (edited == self or edited.is_ancestor_of(self)):
			return edited
	return self

func _reset_damage_controller() -> void:
	var previous := get_node_or_null("CharacterDamageController3D")
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	# Add after all Part ready callbacks, so initial discovery sees the complete character.
	var damage := DAMAGE_SCENE.instantiate()
	add_child(damage)
	damage.owner = _scene_owner()

func _migrate_saved_body_segments(container: Node) -> void:
	var bodies: Array[PhysicalBodyPart3D] = []
	var layouts: Array[Dictionary] = []
	var indices: Array[int] = []
	var needs_migration := false
	for node: Node in container.get_children():
		if not node is PhysicalBodyPart3D or BODY_PART.BodyPartTag.Torso not in node.tags: continue
		needs_migration = needs_migration or not node.has_meta(&"body_segment_id")
		indices.append(bodies.size())
		bodies.append(node)
		layouts.append({"sub_torso": BODY_PART.BodyPartTag.SubTorso in node.tags})
	if not needs_migration or bodies.is_empty(): return
	var edges: Array[Dictionary] = []
	for node: Node in container.find_children("*", "Generic6DOFJoint3D", true, false):
		var a := node.get_node_or_null(node.node_a) as PhysicalBodyPart3D
		var b := node.get_node_or_null(node.node_b) as PhysicalBodyPart3D
		if a not in bodies or b not in bodies: continue
		edges.append({"a": bodies.find(a), "b": bodies.find(b), "distance": a.position.distance_squared_to(b.position), "joint": node})
	var owners := _partition_torso_graph(layouts, indices, edges)
	if owners.is_empty(): return
	for index: int in range(bodies.size()): bodies[index].set_meta(&"body_segment_id", owners[index])
	var parents: Array[int] = []
	for index: int in range(bodies.size()): parents.append(index)
	for cross_segment: bool in [false, true]:
		for edge: Dictionary in edges:
			var crosses: bool = owners[edge.a] != owners[edge.b]
			if crosses != cross_segment: continue
			var a := _root(parents, edge.a)
			var b := _root(parents, edge.b)
			var joint: Generic6DOFJoint3D = edge.joint
			if a == b:
				joint.queue_free()
				continue
			parents[a] = b
			if not crosses: continue
			joint.name = str(joint.name).replace("_Torso", "_Segment")
			for axis: String in ["x", "y", "z"]:
				joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, not segment_free_rotation)
				joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -deg_to_rad(segment_angular_limit_degrees))
				joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(segment_angular_limit_degrees))
				joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, not segment_free_rotation)
				joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, segment_angular_stiffness)
				joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, segment_angular_damping)

func _activate_parts(container: Node) -> void:
	for part: Node in container.get_children():
		if part is PhysicalBodyPart3D:
			# Migrate already-saved generated scenes as well as newly generated parts.
			if part.get_meta(&"generated_role", "") == "Limb" and BODY_PART.BodyPartTag.LegLimb not in part.tags:
				part.tags.append(BODY_PART.BodyPartTag.LegLimb)
		if part is PhysicalBodyPart3D and str(part.name).begins_with("SubTorso") and BODY_PART.BodyPartTag.SubTorso not in part.tags:
			part.tags.append(BODY_PART.BodyPartTag.SubTorso)
		if part is RigidBody3D:
			(part as RigidBody3D).freeze = false
	_migrate_saved_body_segments(container)
	for node: Node in container.find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		var body_a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var body_b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if body_a == null or body_b == null: continue
		if BODY_PART.BodyPartTag.LegLimb not in body_a.tags or BODY_PART.BodyPartTag.LegLimb not in body_b.tags: continue
		for axis: String in ["x", "y"]:
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
	# Future optional controllers can refresh their queries after regeneration.
	for node: Node in find_children("*", "", true, false):
		if node.has_method("refresh_physics_query_cache"):
			node.call("refresh_physics_query_cache")

func _append_part(parts: Array[Dictionary], node_name: String, role: String, size: Vector3, transform: Transform3D) -> int:
	parts.append({"name": node_name, "role": role, "size": size, "transform": transform})
	return parts.size() - 1

func _add_connection(connections: Array[Dictionary], first: int, second: int, anchor: Vector3, kind: String, basis: Basis = Basis.IDENTITY) -> void:
	connections.append({"a": first, "b": second, "anchor": anchor, "kind": kind, "basis": basis})

## Multi-source shortest-path growth keeps each seed's region connected.
func _partition_torso_graph(parts: Array[Dictionary], indices: Array[int], edges: Array[Dictionary]) -> Array[int]:
	var owners: Array[int] = []
	var distances: Array[float] = []
	var visited: Array[bool] = []
	var seed_count := 0
	for index: int in indices:
		var seed: bool = segmented_torso_enabled and bool(parts[index].get("sub_torso", false))
		owners.append(seed_count if seed else -1)
		distances.append(0.0 if seed else INF)
		visited.append(false)
		if seed: seed_count += 1
	if seed_count == 0:
		owners[0] = 0
		distances[0] = 0.0
	for iteration: int in range(indices.size()):
		var nearest := -1
		var best := INF
		for index: int in range(indices.size()):
			if not visited[index] and distances[index] < best:
				nearest = index
				best = distances[index]
		if nearest < 0: return []
		visited[nearest] = true
		for edge: Dictionary in edges:
			var other: int = edge.b if edge.a == nearest else (edge.a if edge.b == nearest else -1)
			if other < 0 or visited[other]: continue
			var cost := best + maxf(sqrt(float(edge.distance)), 0.0001)
			if cost < distances[other]:
				distances[other] = cost
				owners[other] = owners[nearest]
	for index: int in range(indices.size()): parts[indices[index]]["segment_id"] = owners[index]
	return owners

func _build_blueprint(plan: Dictionary, connection_distance: float) -> Dictionary:
	var parts: Array[Dictionary] = []
	var connections: Array[Dictionary] = []
	var torso_indices: Array[int] = []
	var torso_boxes: Array[Dictionary] = []
	for key: String in ["torsos", "network_torsos"]:
		var layouts: Array = plan[key]
		for index: int in range(layouts.size()):
			var layout: Dictionary = layouts[index]
			var node_name := ("SubTorso" if key == "torsos" else "Torso") + ("" if index == 0 else "_%d" % [index + 1])
			var transform := Transform3D(layout.get("basis", Basis.IDENTITY), layout.position)
			torso_indices.append(_append_part(parts, node_name, "Torso", layout.size, transform))
			parts.back()["sub_torso"] = key == "torsos"
			torso_boxes.append(GEOMETRY.box(layout.size, transform))
	if torso_indices.is_empty():
		return {}
	# Kruskal: connect only legal body neighbors, with N-1 links instead of redundant loops.
	var candidates: Array[Dictionary] = []
	for first: int in range(torso_boxes.size()):
		for second: int in range(first):
			if GEOMETRY.connected(torso_boxes[first], torso_boxes[second], maxf(connection_distance, 0.0)):
				var points := _nearest_box_points(torso_boxes[first].aabb, torso_boxes[second].aabb)
				candidates.append({"a": first, "b": second, "anchor": (points[0] + points[1]) * 0.5, "distance": points[0].distance_squared_to(points[1])})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	var segments := _partition_torso_graph(parts, torso_indices, candidates)
	if segments.is_empty(): return {}
	# First build a rigid tree inside every segment, then a tree between segments.
	var parents: Array[int] = []
	for index: int in range(torso_indices.size()): parents.append(index)
	var body_links := 0
	for cross_segment: bool in [false, true]:
		for edge: Dictionary in candidates:
			var crosses: bool = segments[edge.a] != segments[edge.b]
			if crosses != cross_segment: continue
			var first := _root(parents, edge.a)
			var second := _root(parents, edge.b)
			if first == second: continue
			parents[first] = second
			_add_connection(connections, torso_indices[edge.a], torso_indices[edge.b], edge.anchor, "Segment" if crosses else "Torso")
			body_links += 1
	if body_links != torso_indices.size() - 1: return {}
	var counts := {"Leg": 0, "ForeLeg": 0}
	for layout: Dictionary in plan.layouts:
		var role: String = layout.role
		counts[role] += 1
		var node_name := "%s_%d" % [role, counts[role]]
		var size: Vector3 = layout.size
		var horizontal: Vector2 = layout.final_position
		var position := Vector3(horizontal.x, size.y * 0.5, horizontal.y)
		var previous := _append_part(parts, node_name, role, size, Transform3D(Basis.IDENTITY, position))
		var points: PackedVector3Array = layout.limb_points
		for index: int in range(points.size() - 1):
			var start := position + points[index]
			var end := position + points[index + 1]
			var direction := end - start
			var basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
			var block_size: Vector3 = layout.limb_block_sizes[index]
			var next := _append_part(parts, "%s_Limb_%d" % [node_name, index + 1], "Limb", block_size, Transform3D(basis, (start + end) * 0.5))
			_add_connection(connections, previous, next, start, "Limb", basis)
			previous = next
		var tip := position + points[-1]
		var nearest := _nearest_torso(tip, torso_indices, torso_boxes)
		_add_connection(connections, int(nearest.index), previous, (tip + Vector3(nearest.point)) * 0.5, "Limb")
	for index: int in range(plan.necks.size()):
		var neck: Dictionary = plan.necks[index]
		var points: PackedVector3Array = neck.points
		var nearest := _nearest_torso(points[0], torso_indices, torso_boxes)
		var previous: int = nearest.index
		for segment: int in range(neck.blocks.size()):
			var block: Dictionary = neck.blocks[segment]
			var is_head: bool = block.name == "Head"
			var node_name := "Head_%d" % [index + 1] if is_head else "Neck_%d_%d" % [index + 1, segment + 1]
			var next := _append_part(parts, node_name, "Head" if is_head else "Neck", block.size, Transform3D(block.basis, block.position))
			var anchor := points[mini(segment, points.size() - 1)]
			if segment == 0:
				anchor = (anchor + Vector3(nearest.point)) * 0.5
			_add_connection(connections, previous, next, anchor, "Neck", block.basis)
			previous = next
	# Bake size into geometry/positions; rigid bodies and joint bases retain unit scale.
	var multiplier: float = plan.get(&"overall_scale", 1.0)
	for part: Dictionary in parts:
		part.size *= multiplier
		var transform: Transform3D = part.transform
		transform.origin *= multiplier
		part.transform = transform
	for connection: Dictionary in connections:
		connection.anchor *= multiplier
	return {"parts": parts, "connections": connections}

func _root(parents: Array[int], index: int) -> int:
	while parents[index] != index:
		index = parents[index]
	return index

func _nearest_box_points(first: AABB, second: AABB) -> PackedVector3Array:
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	for axis: int in range(3):
		if first.end[axis] < second.position[axis]:
			a[axis] = first.end[axis]
			b[axis] = second.position[axis]
		elif second.end[axis] < first.position[axis]:
			a[axis] = first.position[axis]
			b[axis] = second.end[axis]
		else:
			a[axis] = (maxf(first.position[axis], second.position[axis]) + minf(first.end[axis], second.end[axis])) * 0.5
			b[axis] = a[axis]
	return PackedVector3Array([a, b])

func _nearest_torso(point: Vector3, indices: Array[int], boxes: Array[Dictionary]) -> Dictionary:
	var result := {"index": indices[0], "point": Vector3.ZERO}
	var distance := INF
	for index: int in range(boxes.size()):
		var bounds: AABB = boxes[index].aabb
		var closest := point.clamp(bounds.position, bounds.end)
		if closest.is_equal_approx(point):
			var face_distance := INF
			for axis: int in range(3):
				for face: float in [bounds.position[axis], bounds.end[axis]]:
					var next := absf(point[axis] - face)
					if next < face_distance:
						face_distance = next
						closest = point
						closest[axis] = face
		var next := point.distance_squared_to(closest)
		if next < distance:
			distance = next
			result = {"index": indices[index], "point": closest}
	return result

func _instantiate_blueprint(blueprint: Dictionary, generator_transform: Transform3D) -> Node3D:
	var container := Node3D.new()
	var bodies: Array[RigidBody3D] = []
	for layout: Dictionary in blueprint.parts:
		var part := PART_SCENE.instantiate() as PhysicalBodyPart3D
		if part == null:
			container.free()
			return null
		part.name = layout.name
		part.freeze = true
		part.transform = generator_transform * Transform3D(layout.transform)
		var size: Vector3 = layout.size
		part.left_distance = size.x * 0.5
		part.right_distance = size.x * 0.5
		part.top_distance = size.y * 0.5
		part.bottom_distance = size.y * 0.5
		part.collision_thickness = size.z
		part.sprite_visible = false
		part.mesh_visible = true
		part.mass = clampf(size.x * size.y * size.z * mass_density, minimum_part_mass, maximum_part_mass)
		part.linear_damp = part_linear_damping
		part.angular_damp = part_angular_damping
		part.tags.clear()
		match layout.role:
			"Torso": part.tags.append(BODY_PART.BodyPartTag.Torso)
			"Leg": part.tags.append(BODY_PART.BodyPartTag.Leg)
			"ForeLeg": part.tags.append(BODY_PART.BodyPartTag.ForeLeg)
			"Limb": part.tags.append(BODY_PART.BodyPartTag.LegLimb)
			"Head": part.tags.append(BODY_PART.BodyPartTag.Head)
		if bool(layout.get("sub_torso", false)): part.tags.append(BODY_PART.BodyPartTag.SubTorso)
		if layout.has("segment_id"): part.set_meta(&"body_segment_id", int(layout.segment_id))
		part.set_meta(&"generated_role", layout.role)
		part.set_meta(&"generated_size", size)
		container.add_child(part)
		bodies.append(part)
	var joints := Node3D.new()
	joints.name = "Joints"
	container.add_child(joints)
	for index: int in range(blueprint.connections.size()):
		var connection: Dictionary = blueprint.connections[index]
		var joint := Generic6DOFJoint3D.new()
		joint.name = "Joint_%03d_%s" % [index + 1, connection.kind]
		joint.transform = generator_transform * Transform3D(connection.basis, connection.anchor)
		joint.exclude_nodes_from_collision = true
		var a: RigidBody3D = bodies[connection.a]
		var b: RigidBody3D = bodies[connection.b]
		# Keep the generated rest pose across gait-cache refreshes and participation changes.
		var rest_a := a.basis.orthonormalized().get_rotation_quaternion()
		var rest_b := b.basis.orthonormalized().get_rotation_quaternion()
		joint.set_meta(&"generated_rest_b_relative_a", rest_a.inverse() * rest_b)
		joint.node_a = NodePath("../../" + str(a.name))
		joint.node_b = NodePath("../../" + str(b.name))
		var angle := 0.0 if connection.kind == "Torso" else deg_to_rad(segment_angular_limit_degrees if connection.kind == "Segment" else (neck_angular_limit_degrees if connection.kind == "Neck" else limb_angular_limit_degrees))
		for axis: String in ["x", "y", "z"]:
			var locked_limb_axis: bool = axis != "z" and BODY_PART.BodyPartTag.LegLimb in a.tags and BODY_PART.BodyPartTag.LegLimb in b.tags
			var axis_angle := 0.0 if locked_limb_axis else angle
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, not (connection.kind == "Segment" and segment_free_rotation))
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -axis_angle)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, axis_angle)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, connection.kind != "Torso" and not locked_limb_axis and not (connection.kind == "Segment" and segment_free_rotation))
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, segment_angular_stiffness if connection.kind == "Segment" else angular_spring_stiffness)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, segment_angular_damping if connection.kind == "Segment" else angular_spring_damping)
		joints.add_child(joint)
	return container

func set_control_performance_tracking_enabled(enabled: bool) -> void:
	_ensure_control_performance_stats()
	_control_perf.set_enabled(enabled)

func consume_control_performance_stats() -> Dictionary:
	_ensure_control_performance_stats()
	return _control_perf.consume()
