extends SceneTree

const NPC = preload("res://Scenes/Creatures/Characters/Generate_StumpBeast_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")

func _initialize() -> void: call_deferred("run")

func enemy_at(position: Vector3) -> Node3D:
	var actor := Node3D.new()
	actor.set_script(CHARACTER)
	actor.require_head_and_torso_connectivity = false
	root.add_child(actor)
	var torso: PhysicalBodyPart3D = load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn").instantiate()
	torso.freeze = true
	actor.add_child(torso)
	torso.global_position = position
	return actor

func run() -> void:
	var npc := NPC.instantiate()
	npc.generate_on_ready = false
	root.add_child(npc)
	assert(npc.generate_creature())
	var movement := npc.get_node("GeneratedLegStepMovementController3D")
	var ai := npc.get_node("NPCStateMachine3D")
	ai.set_physics_process(false)
	movement.set_physics_process(false)
	for body in npc._get_physical_body_parts(): body.freeze = true
	# The leaf joint must keep yaw locked across cache rebuilds, without locking the bending hinge.
	movement.refresh_physics_query_cache()
	for foot in movement.get_leg_parts():
		var joint: Generic6DOFJoint3D = movement._chains[foot].joints[0]
		assert(joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT))
		assert(is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)))
		assert(is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
		assert(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) > 0.0)
	var origin: Vector3 = npc.get_combat_anchor().global_position
	var first := enemy_at(origin + Vector3(20,0,0))
	var closer := enemy_at(origin + Vector3(5,0,0))
	ai.behavior = ai.behavior.duplicate(true)
	ai.behavior.attacks.clear()
	ai._enemy = first
	ai._target_switch_remaining = 1.5
	ai._scan_elapsed = 0.0
	ai._update_combat(0.1)
	assert(ai._enemy == first, "Cooldown must retain a valid enemy")
	ai._scan_elapsed = 0.0
	ai._update_combat(1.5)
	assert(ai._enemy == closer, "A substantially closer enemy may replace the target after cooldown")
	closer.faction_id = npc.faction_id
	ai._scan_elapsed = 0.0
	ai._update_combat(0.01)
	assert(ai._enemy == first, "An invalid target must bypass cooldown")
	first.get_combat_anchor().global_position = origin + Vector3(-10,0,15)
	ai.current_state = ai.State.WAITING
	for i in range(4):
		await physics_frame
		ai.get_generated_facing_direction(0.1)
	assert(ai.get_generated_facing_direction(0.0) == Vector3.LEFT, "Z offset must not change X-only facing")
	ai.current_state = ai.State.ATTACK
	first.get_combat_anchor().global_position = origin + Vector3(10,0,-15)
	assert(ai.get_generated_facing_direction(1.0) == Vector3.LEFT, "Attack must retain its starting facing")
	ai.current_state = ai.State.WAITING
	ai._distance_attack = load("res://Resources/AI/GeneratedStompAI.tres").attacks[0]
	ai.behavior.preferred_distance = 15.0
	for i in range(10):
		ai._prediction_distance_sample = i
		assert(ai._preferred_attack_distance(ai._distance_attack) >= 11.25)
		assert(ai._preferred_attack_distance(ai._distance_attack) <= 18.75)
	npc.free()
	first.free()
	closer.free()
	print("STUMP_FACING_STABILITY_VALIDATION_PASSED")
	quit()
