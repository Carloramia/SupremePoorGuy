extends SceneTree
const NPC = preload("res://Scenes/Creatures/Characters/Generate_StumpBeast_NPC.tscn")
const ORIGINAL_NPC = preload("res://Scenes/Creatures/Characters/Generate_Creature_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	assert(NPC.get_state().get_base_scene_state().get_path().ends_with("Generate_StumpBeast.tscn"))
	var original := ORIGINAL_NPC.instantiate()
	var npc := NPC.instantiate()
	assert(not npc.planar_constraints_enabled)
	assert(npc.faction_id == original.faction_id)
	assert(npc.get_node("NPCStateMachine3D").behavior == original.get_node("NPCStateMachine3D").behavior)
	var stomp = npc.get_node("CreatureActionController3D").actions[0]
	var original_stomp = original.get_node("CreatureActionController3D").actions[0]
	assert(stomp != original_stomp and stomp.action_id == original_stomp.action_id)
	assert(stomp.stomp_time < original_stomp.stomp_time)
	assert(stomp.downward_acceleration > original_stomp.downward_acceleration)
	original.free()
	npc.generate_on_ready = false
	if OS.get_cmdline_user_args().has("--scale6"):
		npc.get_node(npc.generator_path).overall_scale = 6.0
	if OS.get_cmdline_user_args().has("--baseline-stomp"):
		var baseline = original_stomp.duplicate(true)
		npc.get_node("CreatureActionController3D").actions[0] = baseline
	var ai: Node3D = npc.get_node("NPCStateMachine3D")
	ai.enabled = false
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100,1,100)
	collision.shape = box
	floor.add_child(collision)
	floor.position.y = -0.5
	root.add_child(floor)
	root.add_child(npc)
	assert(npc.generate_creature())
	var generator: Node3D = npc.get_node(npc.generator_path)
	assert(generator.use_manual_layout)
	assert(npc.get_node("GeneratedParts/SubTorso").get_meta("generated_scene_path").ends_with("01_body_light_plate.tscn"))
	var movement: Node = npc.get_node("GeneratedLegStepMovementController3D")
	var action: Node = npc.get_node("CreatureActionController3D")
	for frame: int in range(120): await physics_frame
	assert(action.has_npc_attack(&"foreleg_stomp"),"Front-foot attack must be available on the Stump body")
	assert(ai._available_attacks().size() == 1)
	assert(movement.get_leg_parts().size() == 4)
	var enemy := Node3D.new()
	enemy.set_script(CHARACTER)
	enemy.require_head_and_torso_connectivity = false
	root.add_child(enemy)
	var torso: PhysicalBodyPart3D = load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn").instantiate()
	torso.freeze = true
	enemy.add_child(torso)
	# Place the target near a stomp impact, rather than assuming a fixed distance
	# from the torso is within the sphere at every generator scale and prediction time.
	var front_foot: RigidBody3D
	for foot: RigidBody3D in movement.get_leg_parts():
		if movement._has_body_tag(foot,movement.FORELEG_TAG):
			if front_foot == null or foot.global_position.x > front_foot.global_position.x: front_foot = foot
	torso.global_position = front_foot.global_position+Vector3(3,1,0)
	await physics_frame
	assert(ai._is_enemy(enemy))
	assert(ai._enemy_torso(enemy) == torso)
	var prediction: Dictionary = action.predict_npc_attack(&"foreleg_stomp",torso,0.6)
	print("STUMP_ATTACK_PREDICTION ",prediction)
	assert(prediction.hit, "Grounded enemy must be hittable by the stomp shockwave")
	print("STUMP_NPC_ATTACK_START ", action.try_start_npc_attack(&"foreleg_stomp",torso,0.6), " diagnostics=",action.get_action_diagnostics())
	assert(action.is_npc_attack_active(),"NPC attack receiver must accept a valid stomp")
	action.cancel_npc_attack()
	# Verify the shared state machine can select and dispatch the attack itself.
	ai.enabled = true
	var autonomous_attack := false
	for frame: int in range(240):
		await physics_frame
		if action.is_npc_attack_active() and ai.current_state == ai.State.ATTACK:
			autonomous_attack = true
			break
	if not autonomous_attack: print("STUMP_AI_DIAGNOSTICS ",ai.get_state_diagnostics()," action=",action.get_action_diagnostics())
	assert(autonomous_attack,"Stump AI must autonomously acquire and attack a hostile target")
	ai.set_physics_process(false)
	var peak_down_speed := 0.0
	for frame: int in range(600):
		await physics_frame
		if action.phase == action.Phase.STOMPING:
			for foot: RigidBody3D in movement.get_leg_parts():
				if movement._has_body_tag(foot,movement.FORELEG_TAG): peak_down_speed = maxf(peak_down_speed,-foot.linear_velocity.y)
		if not action.is_npc_attack_active(): break
	print("STUMP_PEAK_DOWN_SPEED ",peak_down_speed)
	print("STUMP_STOMP_RESULT ",action.get_action_diagnostics())
	assert(action._shockwaves_spawned == 2,"Both front feet must create a stomp shockwave")
	npc.free()
	enemy.free()
	floor.free()
	print("STUMP_BEAST_NPC_VALIDATION_PASSED")
	quit()
