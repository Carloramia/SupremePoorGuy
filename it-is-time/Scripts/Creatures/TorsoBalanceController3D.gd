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

	var current_angle := _controlled_body.global_basis.get_euler().z
	var torque := calculate_balance_torque(current_angle, _controlled_body.angular_velocity.z)
	if not is_zero_approx(torque):
		_controlled_body.sleeping = false
		_controlled_body.apply_torque(Vector3(0.0, 0.0, torque))

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
