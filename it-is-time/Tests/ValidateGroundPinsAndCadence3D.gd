extends SceneTree
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
const BASE = preload("res://Scripts/Creatures/LegStepMovementControllerBase3D.gd")
const DATA = preload("res://Scripts/Creatures/LegMovementData.gd")
var failed := false
func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var data = DATA.new()
	data.automatic_motion = true
	data.maximum_step_frequency = 2.0
	var profile: Dictionary = data.calculate_motion_profile(6.6, 8.0, 6)
	check(profile.frequency * 6.0 <= 2.00001, "Whole-character cadence must respect its cap")
	check(absf(profile.reachable_speed - profile.stride / profile.cycle) < 0.001, "Low cadence must reduce reachable speed after stride reaches its limit")
	data.maximum_step_frequency = 0.0
	check(data.calculate_motion_profile(6.6, 8.0, 6).frequency * 6.0 > 2.0, "Zero cadence cap must restore automatic frequency")
	var fixture := Node3D.new()
	fixture.name = "Fixture"
	root.add_child(fixture)
	var terrain := StaticBody3D.new()
	terrain.name = "Terrain"
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	collision.shape = box
	terrain.add_child(collision)
	terrain.position.y = -0.5
	root.add_child(terrain)
	var foot: PhysicalBodyPart3D = PART.instantiate()
	foot.name = "Foot"
	foot.tags.assign([PhysicalBodyPart3D.BodyPartTag.Leg])
	foot.left_distance = 0.2
	foot.right_distance = 0.2
	foot.top_distance = 0.1
	foot.bottom_distance = 0.1
	foot.collision_thickness = 0.4
	foot.mass = 1.0
	foot.position.y = 0.11
	fixture.add_child(foot)
	var controller = BASE.new()
	controller.parts_root_path = NodePath("..")
	fixture.add_child(controller)
	controller.set_physics_process(false)
	for frame: int in range(5): await physics_frame
	controller._legs.assign([foot])
	controller.update_leg_surface_adhesion()
	check(controller.get_support_foot_diagnostics(foot).locked, "A stationary grounded foot must get a linear pin")
	var anchor := foot.global_position
	foot.apply_central_impulse(Vector3(5, 1, 5))
	for frame: int in range(120): await physics_frame
	check(foot.global_position.distance_to(anchor) < 0.005, "Pinned foot must resist tangential and lifting impulses")
	print("GROUND_PIN drift=", foot.global_position.distance_to(anchor))
	controller.set_leg_slipping(foot, true)
	check(controller._support_pins.is_empty(), "Entering slip must release the pin immediately")
	foot.apply_central_impulse(Vector3(5, 0, 0))
	for frame: int in range(30): await physics_frame
	check(foot.global_position.distance_to(anchor) > 0.05, "Slipping feet must be physically free to slide")
	controller.set_leg_slipping(foot, false)
	controller.update_leg_surface_adhesion()
	check(controller.get_support_foot_diagnostics(foot).locked, "Ending slip must capture the current contact point")
	var moving_anchor := foot.global_position
	terrain.position.x += 0.2
	for frame: int in range(60): await physics_frame
	controller.update_leg_surface_adhesion()
	check(absf(foot.global_position.x - moving_anchor.x - 0.2) < 0.01, "Pin must follow the contacted terrain instead of the world origin")
	var torso: PhysicalBodyPart3D = PART.instantiate()
	torso.name = "Torso"
	torso.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso])
	torso.position = Vector3(10, 2, 0)
	fixture.add_child(torso)
	controller._body_cache_dirty = true
	check(controller.try_surface_burst(), "Grounded feet must still authorize jump")
	check(controller._support_pins.is_empty(), "Jump must release every foot before the torso impulse")
	controller._adhesion_release_time_remaining = 0.0
	controller.update_leg_surface_adhesion()
	controller._begin_leg_motion(foot, foot.global_position + Vector3.RIGHT * 0.2)
	check(controller._support_pins.is_empty(), "Starting a step must synchronously release its ground pin")
	controller.cancel_step(&"test")
	controller.update_leg_surface_adhesion()
	foot.break_part()
	check(controller._support_pins.is_empty(), "Breaking a foot must synchronously release its pin")
	controller.slow_gait_data = data
	data.maximum_step_frequency = 2.0
	controller._last_shared_step_start = 1.0
	controller._physics_elapsed = 1.1
	check(not controller._automatic_step_cadence_allows(), "Turn and walk must share the same cadence deadline")
	controller._physics_elapsed = 1.5
	check(controller._automatic_step_cadence_allows(), "Cadence must permit the next event at its deadline")
	data.maximum_step_frequency = 1.0
	check(not controller._automatic_step_cadence_allows(), "Lowering the cap during runtime must enforce the longer interval immediately")
	fixture.queue_free()
	terrain.queue_free()
	await process_frame
	print("GROUND_PIN_CADENCE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
