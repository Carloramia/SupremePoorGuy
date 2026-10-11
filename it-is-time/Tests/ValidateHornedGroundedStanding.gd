extends SceneTree
const LEVEL = preload("res://Scenes/Levels/TestLevel.tscn")
const SCRIPT = preload("res://Scripts/Creatures/HornedBeastCharacter3D.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var level := LEVEL.instantiate()
	root.add_child(level)
	var actor := level.get_node("GenerateHornedBeastNPC")
	assert(actor.get_script() == SCRIPT, "TestLevel must inherit the HornedBeast-specific script")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	for tick in range(480): await physics_frame
	var diagnostics: Array = actor.get_standing_pose_diagnostics()
	assert(diagnostics.size() == 8)
	var maximum_error := 0.0
	for row: Dictionary in diagnostics:
		maximum_error = maxf(maximum_error, absf(row.error_degrees))
		assert(row.torque.length() <= row.limit + 0.001)
	assert(maximum_error < 35.0, "Standing joint error should improve on the logged 44.5 degrees")
	var recovery: Dictionary = actor.get_node("CreatureRecoveryStateMachine3D").get_recovery_diagnostics()
	assert(recovery.state == "STANDING")
	assert(recovery.metrics.grounded == 4)
	assert(recovery.height_ratio > 0.9, "Higher stance should exceed 90% of the reference height")
	for foot: RigidBody3D in movement.get_leg_parts():
		assert(foot.linear_velocity.length() < 0.05)
		var lower: RigidBody3D = actor.get_node("GeneratedParts/" + str(foot.name) + "_Limb_1")
		assert(lower.mass >= 0.149)
	print("[horned_standing] maximum_error=", maximum_error, " recovery=", recovery)
	# An action must immediately release the standing servo, then ramp it back in.
	var action := actor.get_node("CreatureActionController3D")
	assert(action.try_start_npc_attack(&"foreleg_stomp", null, 0.0))
	for tick in range(3): await physics_frame
	assert(actor.get_standing_pose_diagnostics().is_empty())
	action.cancel_action()
	for tick in range(30): await physics_frame
	assert(not actor.get_standing_pose_diagnostics().is_empty())
	level.free()
	await process_frame
	print("PASS: TestLevel inherits Horned physics; standing is grounded, bounded and releases for actions.")
	quit()
