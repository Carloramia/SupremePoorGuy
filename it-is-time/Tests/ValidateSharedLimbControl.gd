extends SceneTree

const CONTROL = preload("res://Scripts/Creatures/GeneratedLimbControl3D.gd")
const PHYSICS = preload("res://Scripts/Creatures/HornedBeastPhysicsData.gd")
var failed := false

class MovementProbe extends Node:
	var _chains: Dictionary = {}
	var _support_pins: Dictionary = {}
	var grounded := true
	var stepping := false
	func _chain_is_intact(_foot: RigidBody3D) -> bool: return true
	func is_leg_grounded(_foot: RigidBody3D) -> bool: return grounded
	func is_leg_stepping(_foot: RigidBody3D) -> bool: return stepping
	func is_leg_slipping(_foot: RigidBody3D) -> bool: return false
	func _stance_rotation_error(_child: RigidBody3D, _parent: RigidBody3D, _rest: Quaternion) -> Vector3:
		return Vector3(0.0, 0.0, deg_to_rad(15.0))
	func _stance_inverse_inertia(_body: RigidBody3D) -> Basis: return Basis.IDENTITY

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var movement := MovementProbe.new()
	host.add_child(movement)
	var bodies: Array[RigidBody3D] = []
	for index: int in 3:
		var body := RigidBody3D.new()
		body.gravity_scale = 0.0
		host.add_child(body)
		bodies.append(body)
	var ankle := Generic6DOFJoint3D.new()
	var knee := Generic6DOFJoint3D.new()
	host.add_child(ankle)
	host.add_child(knee)
	for joint: Generic6DOFJoint3D in [ankle, knee]:
		joint.set_meta(&"authored_walk_limits", Vector3(0, 0, deg_to_rad(30.0)))
	knee.set_meta(&"passive_hinge_axis_parent", Vector3.BACK)
	movement._chains[bodies[0]] = {"bodies": bodies, "joints": [ankle, knee], "rest_rotations": [Quaternion.IDENTITY, Quaternion.IDENTITY]}
	movement._support_pins[bodies[0]] = true
	var physics := PHYSICS.new()
	physics.standing_strength = 100.0
	physics.standing_damping = 4.0
	physics.standing_dead_zone_degrees = 5.0
	physics.standing_maximum_acceleration = 100.0
	physics.standing_maximum_torque = 2.0
	physics.standing_blend_time = 0.4
	bodies[1].angular_velocity = Vector3.BACK * 3.0
	bodies[2].angular_velocity = Vector3.BACK
	var control := CONTROL.new()
	for scale: float in [0.5, 1.0, 4.0]:
		control.reset_standing()
		control.apply_standing(movement, physics, scale, 0.1, false)
		var rows: Array = control.get_standing_pose_diagnostics()
		check(rows.size() == 1, "Only the knee receives the standing servo; the pinned foot/ankle is excluded")
		# 10 degrees outside the dead zone, relative speed 2, inverse inertia sum 2.
		var expected := minf((deg_to_rad(10.0) * 100.0 - 8.0) / 2.0, 2.0 * pow(scale, 5.0)) * 0.25
		check(Vector3(rows[0].torque).is_equal_approx(Vector3.BACK * expected), "Standing torque preserves dead zone, inertia conversion, scale^5 cap and blend order")
		control.apply_standing(movement, physics, scale, 0.1, true)
		check(control.get_standing_pose_diagnostics().is_empty(), "Recovery/actions must release standing support immediately")
		control.apply_standing(movement, physics, scale, 0.1, false)
		check(is_equal_approx(control.get_standing_pose_diagnostics()[0].blend, 0.25), "Support ramps from zero after an interruption")
	movement.grounded = false
	control.apply_standing(movement, physics, 1.0, 0.1, false)
	check(control.get_standing_pose_diagnostics().is_empty(), "Airborne feet cannot provide standing torque")
	var feet: Array[RigidBody3D] = [bodies[0]]
	knee.set_meta(&"protected_bend", true)
	var protected_keys: Array[StringName] = [&"protected_bend"]
	control.expand_action_limits(movement, feet, 75.0, protected_keys)
	check(control.action_joint_limits.size() == 1 and not control.action_joint_limits.has(knee), "Protected anti-reverse joints keep their authored limits")
	check(is_equal_approx(ankle.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), deg_to_rad(75.0)), "Unprotected joints keep the existing action range")
	control.restore_action_limits()
	check(control.action_joint_limits.is_empty() and is_equal_approx(ankle.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), deg_to_rad(30.0)), "Action end restores authored limits")
	host.free()
	print("SHARED_LIMB_CONTROL ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
