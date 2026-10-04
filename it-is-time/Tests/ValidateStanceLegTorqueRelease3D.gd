extends SceneTree
const CONTROLLER = preload("res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func make_body(tag: int, x: float) -> PhysicalBodyPart3D:
	var body := PhysicalBodyPart3D.new()
	body.tags.append(tag)
	body.gravity_scale = 0.0
	body.angular_damp = 0.0
	body.position.x = x
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	body.add_child(sprite)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	root.add_child(body)
	return body
func run() -> void:
	# Free bodies isolate the controller's applied torque from joint reactions.
	var leg := make_body(1, 0.0)
	var foreleg := make_body(4, 15.0)
	var limb := make_body(5, 5.0)
	var other_limb := make_body(5, 10.0)
	var controller := CONTROLLER.new()
	await physics_frame
	await physics_frame
	controller._apply_stance_joint_torque(leg, limb, Vector3.RIGHT * 10.0)
	await physics_frame
	await physics_frame
	check(leg.angular_velocity.length() < 0.001, "Support torque must not rotate the Leg")
	check(limb.angular_velocity.x < -0.01, "Support torque must still rotate LegLimb")
	leg.angular_velocity = Vector3.ZERO
	limb.angular_velocity = Vector3.ZERO
	controller._apply_stance_joint_torque(limb, leg, Vector3.RIGHT * 10.0)
	await physics_frame
	await physics_frame
	check(leg.angular_velocity.length() < 0.001, "Reversed joint ordering must also release Leg")
	check(limb.angular_velocity.x > 0.01, "Reversed joint ordering must preserve limb torque")
	limb.angular_velocity = Vector3.ZERO
	controller._apply_stance_joint_torque(foreleg, limb, Vector3.RIGHT * 10.0)
	await physics_frame
	await physics_frame
	check(foreleg.angular_velocity.length() < 0.001, "Support torque must not rotate ForeLeg")
	check(limb.angular_velocity.x < -0.01, "ForeLeg limb must still receive support torque")
	limb.angular_velocity = Vector3.ZERO
	controller._apply_stance_joint_torque(limb, foreleg, Vector3.RIGHT * 10.0)
	await physics_frame
	await physics_frame
	check(foreleg.angular_velocity.length() < 0.001, "Reversed ForeLeg joint must release the sole")
	check(limb.angular_velocity.x > 0.01, "Reversed ForeLeg joint must preserve limb support")
	limb.angular_velocity = Vector3.ZERO
	controller._apply_stance_joint_torque(limb, other_limb, Vector3.RIGHT * 10.0)
	await physics_frame
	await physics_frame
	check(limb.angular_velocity.x > 0.01 and other_limb.angular_velocity.x < -0.01, "Other support joints must retain paired torques")
	controller.free()
	if not failed: print("STANCE_LEG_TORQUE_RELEASE_VALIDATION_PASSED")
	quit(1 if failed else 0)
