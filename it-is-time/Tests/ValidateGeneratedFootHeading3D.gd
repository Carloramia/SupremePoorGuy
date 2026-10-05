extends SceneTree

const CONTROLLER = preload("res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd")
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")

class HeadingFixture extends CONTROLLER:
	var heading: float = 0.0
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void:
		_update_foot_heading_constraints()
	func _get_physical_heading_yaw() -> float: return heading
	func _chain_is_intact(foot: RigidBody3D) -> bool:
		return is_instance_valid(foot) and not foot.get_meta(&"test_broken",false)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var controller := HeadingFixture.new()
	fixture.add_child(controller)
	for angle: float in [45.0,-35.0]:
		var foot := RigidBody3D.new()
		foot.gravity_scale = 0.0
		foot.axis_lock_angular_x = true
		foot.axis_lock_angular_z = true
		foot.rotation.y = deg_to_rad(angle)
		foot.position.x = controller._legs.size() * 3.0
		var collision := CollisionShape3D.new()
		collision.shape = BoxShape3D.new()
		foot.add_child(collision)
		fixture.add_child(foot)
		controller._legs.append(foot)
	for frame: int in range(180): await physics_frame
	for foot: RigidBody3D in controller._legs:
		assert(absf(foot.global_rotation.y) < deg_to_rad(0.6), "Yaw torque must physically align feet")
		assert(foot.axis_lock_angular_y, "Aligned feet must lock yaw")
		foot.apply_torque_impulse(Vector3.UP * 10.0)
	for frame: int in range(15): await physics_frame
	for foot: RigidBody3D in controller._legs:
		assert(absf(foot.global_rotation.y) < deg_to_rad(0.6), "Lock must resist disturbance")
	controller._turn_planning_active = true
	await physics_frame
	await physics_frame
	for foot: RigidBody3D in controller._legs:
		assert(not foot.axis_lock_angular_y, "Turn must release yaw without touching pitch/roll locks")
		assert(foot.axis_lock_angular_x and foot.axis_lock_angular_z)
	controller._turn_planning_active = false
	controller.heading = PI * 0.5
	for frame: int in range(210): await physics_frame
	for foot: RigidBody3D in controller._legs:
		assert(absf(wrapf(foot.global_rotation.y - PI * 0.5,-PI,PI)) < deg_to_rad(0.6))
		assert(foot.axis_lock_angular_y)
	var broken: RigidBody3D = controller._legs[0]
	broken.set_meta(&"test_broken",true)
	controller._update_foot_heading_constraints()
	assert(not broken.axis_lock_angular_y)
	controller.foot_heading_lock_enabled = false
	controller._update_foot_heading_constraints()
	assert(not controller._legs[1].axis_lock_angular_y)
	fixture.queue_free()
	await process_frame
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.neck_number = 0
	generator.unsymmetrie = 0.0
	generator._random.seed = 43
	assert(actor.generate_creature())
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	movement._segment_heading_initialized = false
	movement._turn_planning_active = false
	movement._layout_turn_owned = false
	movement._update_foot_heading_constraints()
	var rear := 0
	var front := 0
	for foot: RigidBody3D in movement._legs:
		if movement._has_body_tag(foot,1): rear += 1
		if movement._has_body_tag(foot,4): front += 1
		assert(foot.axis_lock_angular_y)
		assert(movement.get_support_foot_diagnostics(foot).foot_heading.state == &"locked")
	assert(rear > 0 and front > 0)
	movement._turn_planning_active = true
	movement._update_foot_heading_constraints()
	for foot: RigidBody3D in movement._legs: assert(not foot.axis_lock_angular_y)
	actor.free()
	print("GENERATED_FOOT_HEADING_PASSED")
	quit()
