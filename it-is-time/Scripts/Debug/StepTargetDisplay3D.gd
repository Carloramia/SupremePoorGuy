extends Node3D

const FADE_TIME: float = 0.5
var _markers: Dictionary = {}
var _colors: Dictionary = {}
var _next_color: int = 0
var enabled: bool = false

func _ready() -> void:
	# Read completed physics updates, including derived controllers' retargeting.
	process_physics_priority = 1000
	set_physics_process(enabled)

func set_enabled(value: bool) -> void:
	enabled = value
	set_physics_process(value)
	if not value:
		for row: Dictionary in _markers.values(): row.mesh.free()
		_markers.clear()
		_colors.clear()
		_next_color = 0

func _physics_process(delta: float) -> void:
	var seen: Dictionary = {}
	var feet: Dictionary = {}
	for controller: Node in get_tree().get_nodes_in_group(&"leg_step_movement_controllers"):
		if not controller.can_process(): continue
		for foot: RigidBody3D in controller.get_leg_parts():
			if is_instance_valid(foot): feet[foot.get_instance_id()] = true
		for motion in controller._active_steps:
			if not is_instance_valid(motion.leg): continue
			var foot: RigidBody3D = motion.leg
			var key := "%d:%d" % [controller.get_instance_id(), foot.get_instance_id()]
			seen[key] = true
			if not _markers.has(key): _create_marker(key, foot)
			var row: Dictionary = _markers[key]
			row.remaining = FADE_TIME
			var normal: Vector3 = motion.normal.normalized()
			if normal.is_zero_approx(): normal = Vector3.UP
			# Motion targets are body origins; convert them to the foot's terrain point.
			var target: Vector3 = motion.target
			var wolf: Dictionary = motion.extra.get("wolf_step", {})
			if wolf.get("phase", "") == "brake": target = wolf.get("completion", {}).get("target", target)
			var ground: Vector3 = target + controller._get_foot_world_position(foot) - foot.global_position - Vector3.UP * controller.foot_ground_offset
			row.mesh.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, normal)), ground + normal * 0.015)
			row.material.albedo_color = row.color
	for key in _markers.keys():
		if seen.has(key): continue
		var row: Dictionary = _markers[key]
		row.remaining -= delta
		if row.remaining <= 0.0 or not feet.has(row.foot_id):
			row.mesh.free()
			_markers.erase(key)
		else:
			var color: Color = row.color
			color.a = row.remaining / FADE_TIME
			row.material.albedo_color = color
	for id in _colors.keys():
		if not feet.has(id): _colors.erase(id)

func _create_marker(key: String, foot: RigidBody3D) -> void:
	var id := foot.get_instance_id()
	if not _colors.has(id):
		_colors[id] = Color.from_hsv(fmod(_next_color * 0.618034, 1.0), 0.75, 1.0)
		_next_color += 1
	var color: Color = _colors[id]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	var ring := TorusMesh.new()
	ring.inner_radius = 0.18
	ring.outer_radius = 0.21
	ring.rings = 32
	ring.ring_segments = 6
	var mesh := MeshInstance3D.new()
	mesh.mesh = ring
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	_markers[key] = {"mesh": mesh, "material": material, "color": color, "remaining": FADE_TIME, "foot_id": id}
