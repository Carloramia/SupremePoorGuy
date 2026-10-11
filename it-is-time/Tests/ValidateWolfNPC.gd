extends SceneTree
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var npc := NPC.instantiate()
	npc.generate_on_ready = false
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
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-50,0,-50),Vector3(50,0,-50),Vector3(50,0,50),Vector3(-50,0,50)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	root.add_child(region)
	root.add_child(npc)
	assert(npc.generate_creature())
	var generator: Node3D = npc.get_node(npc.generator_path)
	assert(generator._get_defaults_path().ends_with("WolfGeneratorDefaults.tres"))
	assert(npc.get_node("GeneratedParts").has_node("SubTorso_ForeLeg_1"))
	var movement: Node = npc.get_node("GeneratedLegStepMovementController3D")
	var action: Node = npc.get_node("WolfAttackController3D")
	for frame: int in range(120): await physics_frame
	assert(action.has_npc_attack(&"wolf_bite"),"Wolf attack receiver must be available")
	assert(ai._available_attacks().size() == 2)
	assert(movement.get_leg_parts().size() == 4)
	var enemy := Node3D.new()
	enemy.set_script(CHARACTER)
	enemy.require_head_and_torso_connectivity = false
	root.add_child(enemy)
	var torso: PhysicalBodyPart3D = load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn").instantiate()
	torso.freeze = true
	torso.max_hp = 100000.0
	enemy.add_child(torso)
	# Place the target near a stomp impact, rather than assuming a fixed distance
	# from the torso is within the sphere at every generator scale and prediction time.
	var front_foot: RigidBody3D
	for foot: RigidBody3D in movement.get_leg_parts():
		if movement._has_body_tag(foot,movement.FORELEG_TAG):
			if front_foot == null or foot.global_position.x > front_foot.global_position.x: front_foot = foot
	torso.global_position = action.get_node("Bite").jaw.global_position+Vector3.RIGHT
	var target_collision := CollisionShape3D.new()
	var target_box := BoxShape3D.new()
	target_box.size = Vector3(5,5,2)
	target_collision.shape = target_box
	torso.add_child(target_collision)
	await physics_frame
	assert(ai._is_enemy(enemy))
	assert(ai._enemy_torso(enemy) == torso)
	var prediction: Dictionary = action.predict_npc_attack(&"wolf_bite",torso,0.0,24,0.1)
	print("WOLF_ATTACK_PREDICTION ",prediction)
	assert(prediction.hit, "Enemy beside the jaw must be hittable by bite prediction")
	# Verify the shared state machine can select and dispatch the attack itself.
	ai.enabled = true
	ai.resume_autonomous()
	var autonomous_attack := false
	for frame: int in range(240):
		await physics_frame
		if action.is_npc_attack_active() and ai.current_state == ai.State.ATTACK:
			autonomous_attack = true
			break
	if not autonomous_attack: print("WOLF_AI_DIAGNOSTICS ",ai.get_state_diagnostics()," action=",action.get_action_diagnostics())
	assert(autonomous_attack,"Wolf AI must autonomously acquire and attack a hostile target")
	ai.set_physics_process(false)
	for frame: int in range(600):
		await physics_frame
		if not action.is_npc_attack_active(): break
	assert(not action.is_npc_attack_active(),"Autonomous Wolf melee must complete")
	assert(movement._action_feet.is_empty(),"Finished NPC attacks must release movement claims")
	assert(not npc.get_node("CreatureActionController3D").enabled,"Old stomp remains disabled")
	npc.free()
	enemy.free()
	floor.free()
	region.free()
	print("WOLF_BEAST_NPC_VALIDATION_PASSED")
	quit()



