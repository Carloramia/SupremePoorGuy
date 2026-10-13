extends SceneTree

class StanceProbe extends "res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd":
	func _ready() -> void: set_physics_process(false)
	func _get_leg_rest_world_position(_leg: RigidBody3D) -> Vector3: return Vector3.ZERO

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for name: String in ["Generate_Wolf", "Generate_Wolf_NPC", "Generate_Bird", "Generate_Bird_NPC", "Generate_Beast", "Generate_Creature_NPC", "Generate_Ratkin", "Generate_StumpBeast", "Generate_Spider"]:
		var actor := load("res://Scenes/Creatures/Characters/" + name + ".tscn").instantiate() as Node
		actor.generate_on_ready = false
		var ai := actor.get_node_or_null("NPCStateMachine3D")
		if ai != null: ai.enabled = false
		root.add_child(actor)
		var movement: Node = actor.get_node("GeneratedLegStepMovementController3D")
		assert(movement.stable_turn_control_enabled == (name not in ["Generate_StumpBeast", "Generate_Spider", "Generate_Beast", "Generate_Creature_NPC"]))
		actor.queue_free()
		await process_frame
	var probe := StanceProbe.new()
	probe.slow_gait_data = preload("res://Scripts/Creatures/LegMovementData.gd").new()
	probe.fast_gait_data = probe.slow_gait_data
	probe.stable_turn_control_enabled = true
	root.add_child(probe)
	var control := probe._turn_traction_control(deg_to_rad(2.0), deg_to_rad(20.0), deg_to_rad(45.0))
	assert(control.acceleration < 0.0, "Turn control must brake before passing the goal")
	assert(absf(control.requested_rate) < deg_to_rad(10.0), "Small errors must not request full turn speed")
	var integral: float = probe._turn_rate_integral
	for index: int in 100: probe._turn_traction_control(PI, 0.0, deg_to_rad(45.0))
	assert(probe._turn_rate_integral == integral, "Queries must not advance the turn controller")
	probe.locomotion_height_support_enabled = true
	assert(probe._height_support_weight_share() == 1.0)
	probe._action_owners[probe] = {"feet": [], "bodies": []}
	assert(probe._height_support_weight_share() == probe.sub_torso_weight_share, "An action must retain its established support allocation")
	probe._action_owners.clear()
	var foot := RigidBody3D.new()
	root.add_child(foot)
	probe._chains[foot] = {"length": 2.0}
	probe.grounded_stance_travel_ratio = 0.12
	foot.position.x = -0.3
	var demand := probe._get_bounded_stance_demand(foot, Vector3.RIGHT, Vector3.ZERO, 2.0, 0.0, 0.15, {})
	assert(demand.requested, "A bent chain at its boundary must re-step even after actual speed stalls")
	foot.position.x = 0.1
	demand = probe._get_bounded_stance_demand(foot, Vector3.RIGHT, Vector3.ZERO, 2.0, 0.0, 0.15, {})
	assert(not demand.requested, "Target speed alone must not repeatedly lift a forward-planted foot")
	foot.position.x = -0.1
	probe._extension_rearm[foot] = {"origin": Vector3.ZERO, "direction": Vector3.RIGHT}
	demand = probe._get_bounded_stance_demand(foot, Vector3.RIGHT, Vector3.ZERO, 2.0, 0.0, 0.15, {})
	assert(not demand.requested, "A planted foot must regain stance progress before preview re-steps")
	foot.free()
	probe.free()
	print("CREATURE_MOTION_CORRECTIONS_PASSED")
	quit()
