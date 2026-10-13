extends SceneTree

const MOVEMENT = preload("res://Scripts/Creatures/SpiderLegStepMovementController3D.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var profiles: Array[Dictionary] = []
	var distances := [1.61724, 1.60076, 1.62363, 1.60277, 1.79889, 1.72367, 1.87769, 1.67897]
	var durations := [0.29349, 0.30911, 0.29349, 0.31077, 1.11055, 0.28846, 0.92765, 0.59804]
	for index: int in 8: profiles.append({"stride": distances[index], "occupied_step_duration": durations[index]})
	var budget := MOVEMENT.calculate_spider_motion_budget(profiles, 3.0, 4, 32.0)
	check(is_equal_approx(budget.speed, 3.0) and budget.occupied_slots < 3.6, "Unequal leg durations must share the real capacity without the slowest equal-share cap")
	var limited := MOVEMENT.calculate_spider_motion_budget(profiles, 3.0, 2, 32.0)
	check(limited.speed < 3.0 and limited.occupied_slots <= 1.80001, "Overloaded gait must reduce speed to the support budget")
	var cadence := MOVEMENT.calculate_spider_motion_budget(profiles, 3.0, 4, 4.0)
	check(cadence.speed < 3.0 and cadence.frequency <= 4.00001, "Reference cadence must constrain the feasible speed calculation")
	check(MOVEMENT.calculate_spider_motion_budget(profiles, 0.0, 4, 0.0).speed == 0.0, "Zero demand must produce zero speed")
	check(MOVEMENT.calculate_spider_motion_budget(profiles, 3.0, 0, 0.0).speed == 0.0, "No free step slots must produce zero walking budget")
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Spider.tscn").instantiate()
	root.add_child(actor)
	await process_frame
	actor.set_physics_process(false)
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D: body.freeze = true
	for refresh: int in 2:
		movement.refresh_physics_query_cache()
		for foot: RigidBody3D in movement._chains:
			var chain: Dictionary = movement._chains[foot]
			var joint: Generic6DOFJoint3D = chain.joints[-1]
			var data: Dictionary = joint.get_meta(&"spider_world_angle")
			var bound := deg_to_rad(actor.spider_leg_bend_limit_degrees)
			check(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT), -bound - float(data.initial_angle)), "Refresh must restore absolute root limits before capturing geometry")
			check(float(movement.get_spider_stride_limits(foot).half_travel) > 1.0, "Geometry must not cache the overwritten relative limits")
		movement._spider_step_times.clear()
		for index: int in movement._legs.size(): movement._spider_step_times[movement._legs[index]] = durations[index] / 1.1
		movement._spider_profile_context.clear()
		var speed: float = movement.get_expected_horizontal_speed()
		var diagnostics: Dictionary = movement.get_automatic_motion_diagnostics()
		check(diagnostics.has("spider_motion_budget") and speed > 0.0 and speed <= 3.0, "Live controller must use and expose the aggregate budget")
		check(diagnostics.spider_motion_budget.occupied_slots <= diagnostics.spider_motion_budget.slot_budget + 0.001, "Observed step durations must remain inside the support capacity")
		var frequency := 0.0
		for profile: Dictionary in diagnostics.legs: frequency += float(profile.frequency)
		check(is_equal_approx(frequency, movement.get_planned_step_frequency()), "Per-leg cycles must sum to the reported frequency")
		check(not is_equal_approx(float(diagnostics.legs[0].cycle), float(diagnostics.legs[4].cycle)), "Different occupied durations must retain different cycles")
	actor.free()
	await process_frame
	print("SPIDER_BUDGET_TEST ", JSON.stringify(budget))
	if not failed: print("PASS: Spider cache restores absolute limits and heterogeneous legs share a bounded motion budget.")
	quit(1 if failed else 0)
