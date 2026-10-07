extends SceneTree
const NPC = preload("res://Scenes/Creatures/Characters/Generate_StumpBeast_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400,1,400)
	collision.shape = box
	floor.add_child(collision)
	floor.position.y = -0.5
	root.add_child(floor)
	var npc := NPC.instantiate()
	npc.generate_on_ready = false
	root.add_child(npc)
	var ai := npc.get_node("NPCStateMachine3D")
	ai.enabled = false
	ai.set_physics_process(false)
	assert(npc.generate_creature())
	for i in range(120): await physics_frame
	var enemy := Node3D.new()
	enemy.set_script(CHARACTER)
	enemy.require_head_and_torso_connectivity = false
	root.add_child(enemy)
	var torso: PhysicalBodyPart3D = load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn").instantiate()
	torso.freeze = true
	enemy.add_child(torso)
	torso.global_position = npc.get_combat_anchor().global_position + Vector3(-100,0,0)
	ai._enemy = enemy
	ai.enabled = true
	ai.current_state = ai.State.WAITING
	var movement := npc.get_node("GeneratedLegStepMovementController3D")
	var aligned := false
	for i in range(1800):
		await physics_frame
		if i > 120 and absf(wrapf(PI - movement._get_physical_heading_yaw(),-PI,PI)) < deg_to_rad(15):
			aligned = true
			break
	print("STUMP_TURN_RESULT aligned=",aligned," yaw=",rad_to_deg(movement._get_physical_heading_yaw())," status=",movement._layout_turn_status)
	assert(aligned,"Leaf yaw constraints must allow a complete physical 180-degree turn")
	npc.free()
	enemy.free()
	floor.free()
	print("STUMP_PHYSICAL_TURN_VALIDATION_PASSED")
	quit()
