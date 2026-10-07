extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	collision.shape = box
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var npc := load("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn").instantiate() as Node3D
	root.add_child(npc)
	var brain := npc.get_node("NPCStateMachine3D")
	brain.behavior = brain.behavior.duplicate(true)
	brain.behavior.require_line_of_sight = false
	brain.behavior.scan_interval = 0.05
	var facing := npc.get_node("PhysicalFacingController3D") as PhysicalFacingController3D
	var torso := npc.get_node("Torso") as PhysicalBodyPart3D
	var enemy := Node3D.new()
	enemy.set_script(load("res://Scripts/Creatures/PhysicalCharacterController.gd"))
	enemy.faction_id = 0
	enemy.require_head_and_torso_connectivity = false
	var target := load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn").instantiate() as PhysicalBodyPart3D
	target.freeze = true
	enemy.add_child(target)
	root.add_child(enemy)
	target.global_position = Vector3(-20, 4, 0)
	for frame: int in range(12): await physics_frame
	assert(brain._enemy == enemy)
	assert(facing.get_facing() == facing.FacingDirection.LEFT and facing.is_turning(), "Enemy acquisition must issue a left body turn without mouse input")
	assert(not brain._try_attack(3.0) and brain._attack_block_reason == &"body_turn_pending", "Body turn must precede Arm attack prediction")
	for frame: int in range(1000):
		await physics_frame
		if facing.is_npc_facing_ready(Vector3.LEFT) and torso.global_basis.x.dot(Vector3.LEFT) > 0.98: break
	var arm_r := npc.get_node("Arm_R") as PhysicalBodyPart3D
	var arm_l := npc.get_node("Arm_L") as PhysicalBodyPart3D
	print("NPC_BODY_LEFT heading=%s arm_r=%s arm_l=%s torso=%s" % [torso.global_basis.x, arm_r.global_position, arm_l.global_position, torso.global_position])
	assert(torso.global_basis.x.dot(Vector3.LEFT) > 0.98, "NPC must physically turn its whole body")
	assert(arm_r.global_position.x < torso.global_position.x and arm_r.global_position.x < arm_l.global_position.x, "Weapon Arm_R must be on the left side after turning")
	assert(arm_r.global_position.distance_to(target.global_position) < arm_l.global_position.distance_to(target.global_position))
	assert(facing.is_npc_facing_ready(Vector3.LEFT))
	target.global_position = Vector3(20, 4, 0)
	for frame: int in range(1000):
		await physics_frame
		if facing.get_facing() == facing.FacingDirection.RIGHT and facing.is_npc_facing_ready(Vector3.RIGHT) and torso.global_basis.x.dot(Vector3.RIGHT) > 0.98: break
	assert(torso.global_basis.x.dot(Vector3.RIGHT) > 0.98)
	assert(arm_r.global_position.x > torso.global_position.x and arm_r.global_position.x > arm_l.global_position.x)
	assert(facing.is_npc_facing_ready(Vector3.RIGHT))
	brain.enabled = false
	await physics_frame
	assert(not facing.is_turning(), "Disabled AI must release turn planning")
	print("NPC_BODY_FACING_3D_VALIDATION_PASSED")
	quit()
