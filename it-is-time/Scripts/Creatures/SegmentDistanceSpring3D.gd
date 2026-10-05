@tool
extends Node
## Logical cross-segment connection. Applies only central forces, never torque.
@export var enabled: bool = true
@export var node_a: NodePath
@export var node_b: NodePath
@export_range(0.0, 1000.0, 0.01) var rest_distance: float = 0.0
@export_range(0.1, 20.0, 0.1) var frequency: float = 3.0
@export_range(0.0, 2.0, 0.05) var damping_ratio: float = 1.0
@export_range(0.0, 500.0, 0.1) var maximum_acceleration: float = 50.0
@export var maximum_distance_lock_enabled: bool = true
@export_range(1.0, 3.0, 0.01, "or_greater") var maximum_distance_ratio: float = 1.15
var _distance_lock_active := false
var _distance_lock_correction := 0.0
## Initial frame is saved independently of subsequent heading changes.
@export var rest_reference_yaw: float = 0.0
var layout_enabled: bool = false
var layout_frequency: float = 1.0
var layout_damping_ratio: float = 1.0
var layout_maximum_acceleration: float = 12.0
var _layout_yaw: float = 0.0
var _layout_yaw_speed: float = 0.0
var _rest_offset := Vector3.ZERO
var _layout_force := Vector3.ZERO
var _layout_error := Vector3.ZERO
var _layout_angle_error: float = 0.0
var _layout_limited: bool = false
var _combined_limited: bool = false
var _a: RigidBody3D
var _b: RigidBody3D
var _bodies_a: Array[RigidBody3D] = []
var _bodies_b: Array[RigidBody3D] = []
var last_force := Vector3.ZERO
var last_distance := 0.0
var _valid := true
func is_segment_spring() -> bool: return true
func _ready() -> void:
	_a = get_node_or_null(node_a) as RigidBody3D
	_b = get_node_or_null(node_b) as RigidBody3D
	if _a == null or _b == null:
		_valid = false
		return
	var first := int(_a.get_meta(&"body_segment_id", -1))
	var second := int(_b.get_meta(&"body_segment_id", -1))
	for node: Node in get_parent().get_parent().get_children():
		if not node is RigidBody3D: continue
		if int(node.get_meta(&"body_segment_id", -2)) == first: _bodies_a.append(node)
		if int(node.get_meta(&"body_segment_id", -2)) == second: _bodies_b.append(node)
	if _a.has_signal("broken"): _a.connect("broken", _on_endpoint_broken)
	if _b.has_signal("broken"): _b.connect("broken", _on_endpoint_broken)
	var a := _state(_bodies_a)
	var b := _state(_bodies_b)
	_rest_offset = Basis(Vector3.UP, rest_reference_yaw).inverse() * Vector3(b.center - a.center)
	_layout_yaw = rest_reference_yaw
	if rest_distance <= 0.0: rest_distance = Vector3(a.center).distance_to(b.center)
	set_physics_process(not Engine.is_editor_hint())
func _on_endpoint_broken(_source: Node) -> void:
	_valid = false
	last_force = Vector3.ZERO
	queue_free()
func _state(bodies: Array[RigidBody3D]) -> Dictionary:
	var mass := 0.0
	var center := Vector3.ZERO
	var velocity := Vector3.ZERO
	for body: RigidBody3D in bodies:
		if not is_instance_valid(body) or body.is_queued_for_deletion() or bool(body.get("is_broken")): continue
		mass += body.mass
		center += body.global_position * body.mass
		velocity += body.linear_velocity * body.mass
	return {"mass": mass, "center": center / maxf(mass, 0.001), "velocity": velocity / maxf(mass, 0.001)}
func set_layout_reference(yaw: float, yaw_speed: float, active: bool, hz: float, damping: float, acceleration_limit: float) -> void:
	_layout_yaw = yaw
	_layout_yaw_speed = yaw_speed
	layout_enabled = active
	layout_frequency = hz
	layout_damping_ratio = damping
	layout_maximum_acceleration = acceleration_limit

func _physics_process(_delta: float) -> void:
	last_force = Vector3.ZERO
	_distance_lock_active = false
	_distance_lock_correction = 0.0
	_layout_force = Vector3.ZERO
	_layout_error = Vector3.ZERO
	_layout_angle_error = 0.0
	_layout_limited = false
	_combined_limited = false
	if not enabled or not _valid or not is_instance_valid(_a) or not is_instance_valid(_b): return
	if bool(_a.get("is_broken")) or bool(_b.get("is_broken")): return
	var a := _state(_bodies_a)
	var b := _state(_bodies_b)
	if a.mass <= 0.0 or b.mass <= 0.0: return
	_enforce_maximum_distance(a, b, _delta)
	a = _state(_bodies_a)
	b = _state(_bodies_b)
	var offset: Vector3 = b.center - a.center
	last_distance = offset.length()
	var direction := offset.normalized()
	if direction.is_zero_approx(): direction = Vector3.RIGHT
	var reduced_mass: float = a.mass * b.mass / (a.mass + b.mass)
	var omega := TAU * frequency
	var relative_speed: float = Vector3(b.velocity - a.velocity).dot(direction)
	var magnitude: float = reduced_mass * (omega * omega * (last_distance - rest_distance) + 2.0 * damping_ratio * omega * relative_speed)
	magnitude = clampf(magnitude, -maximum_acceleration * reduced_mass, maximum_acceleration * reduced_mass)
	last_force = direction * magnitude
	var desired := Basis(Vector3.UP, _layout_yaw) * _rest_offset
	_layout_error = (offset - desired).slide(Vector3.UP)
	if layout_enabled and layout_frequency > 0.0:
		var horizontal := offset.slide(Vector3.UP)
		var target := desired.slide(Vector3.UP)
		if not target.is_zero_approx():
			# A polar spring corrects even an antipodal displacement. Vector-error
			# projection alone has zero tangential force at exactly 180 degrees.
			var current_yaw := atan2(-horizontal.z, horizontal.x) if not horizontal.is_zero_approx() else _layout_yaw
			_layout_angle_error = wrapf(atan2(-target.z, target.x) - current_yaw, -PI, PI)
			var tangent := Vector3.UP.cross(horizontal.normalized() if not horizontal.is_zero_approx() else target.normalized())
			var target_speed := _layout_yaw_speed * horizontal.length()
			var speed_error := Vector3(b.velocity - a.velocity).dot(tangent) - target_speed
			var layout_omega := TAU * layout_frequency
			var acceleration := layout_omega * layout_omega * _layout_angle_error * maxf(horizontal.length(), target.length() * 0.25) - 2.0 * layout_damping_ratio * layout_omega * speed_error
			_layout_limited = absf(acceleration) > layout_maximum_acceleration
			# Equal/opposite central forces preserve linear momentum; no body torque is applied.
			_layout_force = -tangent * clampf(acceleration, -layout_maximum_acceleration, layout_maximum_acceleration) * reduced_mass
			last_force += _layout_force
	var force_scale := minf(1.0, maximum_acceleration * reduced_mass / maxf(last_force.length(), 0.000001))
	_combined_limited = force_scale < 1.0
	last_force *= force_scale
	_layout_force *= force_scale
	for body: RigidBody3D in _bodies_a:
		if is_instance_valid(body) and not body.freeze and not bool(body.get("is_broken")): body.apply_central_force(last_force * body.mass / a.mass)
	for body: RigidBody3D in _bodies_b:
		if is_instance_valid(body) and not body.freeze and not bool(body.get("is_broken")): body.apply_central_force(-last_force * body.mass / b.mass)
## Unilateral distance constraint: preserve the pair COM and remove only outward speed.
## Translate each segment uniformly so its internal rigid joints retain their pose.
func _enforce_maximum_distance(a: Dictionary, b: Dictionary, delta: float) -> void:
	_distance_lock_active = false
	_distance_lock_correction = 0.0
	if not maximum_distance_lock_enabled: return
	var offset: Vector3 = b.center - a.center
	var distance := offset.length()
	var maximum := rest_distance * maxf(1.0, maximum_distance_ratio)
	if distance <= 0.000001 or maximum <= 0.0: return
	var direction := offset / distance
	var movable_a := _movable_mass(_bodies_a)
	var movable_b := _movable_mass(_bodies_b)
	var inverse_a: float = 1.0 / a.mass if movable_a > 0.0 else 0.0
	var inverse_b: float = 1.0 / b.mass if movable_b > 0.0 else 0.0
	var inverse_sum: float = inverse_a + inverse_b
	if inverse_sum <= 0.0: return
	var outward: float = Vector3(b.velocity - a.velocity).dot(direction)
	var allowed_speed := maxf(0.0, maximum - distance) / maxf(delta, 0.000001)
	var speed_correction := maxf(0.0, outward - allowed_speed)
	_distance_lock_correction = maxf(0.0, distance - maximum)
	_distance_lock_active = speed_correction > 0.0 or _distance_lock_correction > 0.0
	for pair: Array in [[_bodies_a, a.mass, inverse_a, 1.0], [_bodies_b, b.mass, inverse_b, -1.0]]:
		var share: float = pair[2] / inverse_sum
		for body: RigidBody3D in pair[0]:
			if not is_instance_valid(body) or body.freeze or bool(body.get("is_broken")): continue
			body.global_position += direction * _distance_lock_correction * share * float(pair[3])
			body.apply_central_impulse(direction * speed_correction * share * float(pair[3]) * body.mass)

func _movable_mass(bodies: Array[RigidBody3D]) -> float:
	var mass := 0.0
	for body: RigidBody3D in bodies:
		if not is_instance_valid(body) or body.is_queued_for_deletion() or bool(body.get("is_broken")): continue
		# A frozen member anchors its rigid segment.
		if body.freeze: return 0.0
		mass += body.mass
	return mass

func get_spring_diagnostics() -> Dictionary:
	return {"name": name, "enabled": enabled, "maximum_distance": rest_distance * maximum_distance_ratio, "distance_lock_enabled": maximum_distance_lock_enabled, "distance_lock_active": _distance_lock_active, "distance_lock_correction": _distance_lock_correction, "rest_distance": rest_distance, "distance": last_distance, "extension": last_distance - rest_distance, "force": last_force, "valid": _valid, "layout_enabled": layout_enabled, "rest_offset": _rest_offset, "layout_yaw_degrees": rad_to_deg(_layout_yaw), "layout_yaw_speed_degrees": rad_to_deg(_layout_yaw_speed), "layout_error": _layout_error, "layout_angle_error_degrees": rad_to_deg(_layout_angle_error), "layout_force": _layout_force, "layout_limited": _layout_limited, "combined_force_limited": _combined_limited}
