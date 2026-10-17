extends SceneTree

var failed := false
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("RATS_GALLOP_CHECK: " + message)

func run() -> void:
	var world: Node3D = load("res://Scenes/Levels/RatsTestLevel.tscn").instantiate()
	var other := world.get_node("GenerateRat2NPC")
	world.remove_child(other)
	other.free()
	var actor := world.get_node("GenerateRat1NPC")
	var ai := actor.get_node("NPCStateMachine3D")
	ai.behavior = ai.behavior.duplicate(true)
	ai.behavior.auto_find_enemies = false
	ai.attack_execution_enabled = false
	root.add_child(world)
	current_scene = world
	for tick: int in 180: await physics_frame
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	var data: Resource = movement.slow_gait_data
	check(data.gallop_enabled and data.automatic_gallop_enabled and data.traction_gallop_enabled, "Saved preset enables automatic gallop and relief")
	check(is_equal_approx(movement.grounded_stance_travel_ratio, 0.12), "Rat inherits the bounded stance budget")
	var feet: Array = movement.get_leg_parts().filter(func(foot): return movement.is_leg_grounded(foot) and not movement.is_leg_stepping(foot))
	check(not feet.is_empty(), "A real grounded foot is available")
	if not feet.is_empty():
		var foot: RigidBody3D = feet[0]
		var saved_traction: Dictionary = movement._wolf_traction.duplicate(true)
		var saved_gallop: bool = movement._wolf_auto_gallop
		movement._wolf_traction[foot] = {"confirmed": true}
		movement._wolf_auto_gallop = false
		check(not movement._wolf_needs_support_relief(foot), "Walking traction cannot independently start gallop")
		movement._wolf_auto_gallop = true
		check(movement._wolf_needs_support_relief(foot), "An existing gallop retains the parent's traction relief")
		movement._wolf_traction = saved_traction
		movement._wolf_auto_gallop = saved_gallop
	world.free()
	await process_frame
	print("RATS_GALLOP_VALIDATION passed=", not failed, " checks=", checks)
	quit(1 if failed else 0)
