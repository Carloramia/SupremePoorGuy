extends SceneTree

const MOVEMENT = preload("res://Scripts/Creatures/LegStepMovementControllerBase3D.gd")

class TestController extends Node:
	var _active_steps: Array = []
	var feet: Array[RigidBody3D] = []
	var foot_ground_offset: float = 0.02
	func get_leg_parts() -> Array[RigidBody3D]: return feet
	func _get_foot_world_position(foot: RigidBody3D) -> Vector3: return foot.global_position - Vector3.UP * 0.5

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var console := root.get_node("RuntimeConsole")
	assert(console._step_target_display == null)
	assert(console.execute_command("help").contains("showsteptargets"))
	assert(console.execute_command("showsteptargets invalid") == "Usage: showsteptargets [on|off]")
	assert(console._step_target_display == null)
	assert(console.execute_command("showsteptargets on") == "Step target rings enabled.")
	var display = console._step_target_display
	display.set_physics_process(false)
	var controller := TestController.new()
	root.add_child(controller)
	controller.add_to_group(&"leg_step_movement_controllers")
	for i in 2:
		var foot := RigidBody3D.new()
		foot.freeze = true
		controller.add_child(foot)
		foot.position = Vector3(i, 3.0, 2.0)
		controller.feet.append(foot)
		var motion := MOVEMENT.StepMotion.new()
		motion.leg = foot
		motion.target = Vector3(i + 5.0, 6.0, 7.0)
		motion.normal = Vector3(0.0, 1.0, 1.0).normalized()
		controller._active_steps.append(motion)
	display._physics_process(0.016)
	assert(display._markers.size() == 2)
	var markers: Array = display._markers.values()
	assert(markers[0].color != markers[1].color)
	var normal: Vector3 = controller._active_steps[0].normal
	assert(markers[0].mesh.global_position.is_equal_approx(Vector3(5.0, 5.48, 7.0) + normal * 0.015))
	assert(markers[0].mesh.global_basis.y.is_equal_approx(normal))
	assert(markers[0].mesh is MeshInstance3D)
	var color: Color = markers[0].color
	controller._active_steps[0].target.x += 2.0
	display._physics_process(0.016)
	assert(is_equal_approx(markers[0].mesh.global_position.x, 7.0))
	assert(markers[0].color == color)
	controller._active_steps.clear()
	display._physics_process(0.25)
	assert(display._markers.size() == 2)
	assert(is_equal_approx(markers[0].material.albedo_color.a, 0.5))
	display._physics_process(0.26)
	assert(display._markers.is_empty())
	var motion := MOVEMENT.StepMotion.new()
	motion.leg = controller.feet[0]
	controller._active_steps.append(motion)
	display._physics_process(0.016)
	assert(display._markers.size() == 1)
	assert(console.execute_command("showsteptargets off") == "Step target rings disabled.")
	assert(display._markers.is_empty() and display.get_child_count() == 0)
	assert(not display.is_physics_processing())
	assert(console.execute_command("showsteptargets") == "Step target rings enabled.")
	console.execute_command("showsteptargets off")
	controller.free()
	print("PASS: step target console toggle, distinct foot colors, world landing positions, normals, retargeting, fade and immediate cleanup.")
	quit()
