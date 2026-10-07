extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var npc := load("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn").instantiate() as Node3D
	for body: Node in npc.find_children("*", "RigidBody3D", true, false): body.freeze = true
	root.add_child(npc)
	for component: Node in npc.get_children(): component.set_physics_process(false)
	var brain := npc.get_node("NPCStateMachine3D")
	var facing := npc.get_node("PhysicalFacingController3D") as PhysicalFacingController3D
	var torso := npc.get_node("Torso") as PhysicalBodyPart3D
	var enemy := Node3D.new()
	enemy.set_script(load("res://Scripts/Creatures/PhysicalCharacterController.gd"))
	enemy.require_head_and_torso_connectivity = false
	enemy.faction_id = 0
	var target := load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn").instantiate() as PhysicalBodyPart3D
	target.freeze = true
	enemy.add_child(target)
	root.add_child(enemy)
	await physics_frame
	brain._enemy = enemy
	brain._target = target
	target.global_position = torso.global_position + Vector3(-3.5, 0, 30)
	var preferred: float = brain._preferred_attack_distance(brain._available_attacks()[0])
	target.global_position.x = torso.global_position.x - preferred
	assert(brain.get_npc_body_facing_direction() == Vector3.LEFT, "Large Z offsets must not hide the target's X side")
	facing._try_request_turn_from_cursor(0.2)
	assert(facing.get_facing() == facing.FacingDirection.LEFT and facing.is_turning())
	assert(brain._plan_attack_distance(30.2, brain._available_attacks()))
	assert(is_equal_approx(brain._requested_target_position.x, torso.global_position.x), "Within the X distance band, reposition only along Z")
	assert(is_equal_approx(brain._requested_target_position.z, target.global_position.z))
	assert(not brain._try_attack(3.5) and brain._attack_block_reason == &"z_alignment_pending")
	assert(brain.get_attack_range_diagnostics().z_error == 30.0)
	# Once the lane is aligned, retain the normal attack-distance stop band.
	target.global_position.z = torso.global_position.z + 0.2
	assert(not brain._plan_attack_distance(3.5, brain._available_attacks()))
	assert(not brain._try_attack(3.5) and brain._attack_block_reason == &"body_turn_pending")
	target.global_position = torso.global_position + Vector3(3.5, 0, -30)
	facing._try_request_turn_from_cursor(0.2)
	assert(brain.get_npc_body_facing_direction() == Vector3.RIGHT)
	assert(facing.get_facing() == facing.FacingDirection.RIGHT)
	# At the same X coordinate, keep the existing facing instead of oscillating.
	target.global_position.x = torso.global_position.x + 0.05
	assert(brain.get_npc_body_facing_direction().is_zero_approx())
	target.global_position = torso.global_position + Vector3(12, 0, 10)
	assert(brain._plan_attack_distance(15.6, brain._available_attacks()))
	assert(is_equal_approx(brain._requested_target_position.x, target.global_position.x - preferred))
	assert(is_equal_approx(brain._requested_target_position.z, target.global_position.z))
	assert(npc.get_node("NPCLegStepMovementController3D").input_enabled)
	print("NPC_AXIS_POSITIONING_3D_VALIDATION_PASSED")
	quit()
