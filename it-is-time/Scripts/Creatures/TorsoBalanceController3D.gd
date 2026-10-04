extends Node

## Applies a damped corrective torque to keep a planar RigidBody3D upright.
@export_group("Balance")
@export var balance_enabled: bool = true
@export_range(-180.0, 180.0, 0.1) var target_angle_degrees: float = 0.0
@export_range(0.0, 500.0, 0.1, "or_greater") var balance_strength: float = 25.0
@export_range(0.0, 100.0, 0.1, "or_greater") var balance_damping: float = 6.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var maximum_balance_torque: float = 80.0
@export var controlled_body_path: NodePath = NodePath("..")

var _controlled_body: RigidBody3D

func _ready() -> void:
	_resolve_controlled_body()

func _physics_process(_delta: float) -> void:
	if not balance_enabled:
		return
	if not is_instance_valid(_controlled_body):
		_resolve_controlled_body()
	if not is_instance_valid(_controlled_body):
		return
	if _controlled_body is PhysicalBodyPart3D and _controlled_body.is_broken:
		return

	var torque := calculate_upright_torque(_controlled_body.global_basis, _controlled_body.angular_velocity)
	if not torque.is_zero_approx():
		_controlled_body.sleeping = false
		_controlled_body.apply_torque(torque)

func calculate_upright_torque(body_basis: Basis, angular_velocity: Vector3) -> Vector3:
	var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	var forward := body_basis.z.slide(up).normalized()
	if forward.is_zero_approx():
		forward = body_basis.x.cross(up).normalized()
	var target_up := up.rotated(forward, deg_to_rad(target_angle_degrees))
	var current_up := body_basis.y.normalized()
	var cross := current_up.cross(target_up)
	var error := cross.normalized() * atan2(cross.length(), current_up.dot(target_up))
	var torque := error * balance_strength - angular_velocity.slide(up) * balance_damping
	return torque.limit_length(maximum_balance_torque)

func calculate_balance_torque(current_angle: float, angular_velocity: float) -> float:
	var target_angle := deg_to_rad(target_angle_degrees)
	var angle_error := wrapf(target_angle - current_angle, -PI, PI)
	return clampf(
		angle_error * balance_strength - angular_velocity * balance_damping,
		-maximum_balance_torque,
		maximum_balance_torque
	)

func get_controlled_body() -> RigidBody3D:
	return _controlled_body

func _resolve_controlled_body() -> void:
	_controlled_body = get_node_or_null(controlled_body_path) as RigidBody3D
