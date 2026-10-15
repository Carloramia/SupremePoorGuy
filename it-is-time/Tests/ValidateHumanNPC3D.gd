extends SceneTree

const NPC = preload("res://Scenes/Creatures/Characters/Generate_Human_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const TORSO = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func make_target(faction: int, position: Vector3) -> Node3D:
	var actor := Node3D.new()
	actor.set_script(CHARACTER)
	actor.faction_id = faction
	actor.require_head_and_torso_connectivity = false
	var body := TORSO.instantiate() as PhysicalBodyPart3D
	body.name = "Torso"
	body.freeze = true
	actor.add_child(body)
	root.add_child(actor)
	actor.global_position = position
	return actor

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-50,0,-50), Vector3(50,0,-50), Vector3(50,0,50), Vector3(-50,0,50)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	level.add_child(region)
	var actor := NPC.instantiate() as Node3D
	var ai := actor.get_node("NPCStateMachine3D")
	ai.enabled = false
	level.add_child(actor)
	for tick: int in 12: await physics_frame
	check(actor.get_script().get_base_script() == load("res://Scripts/Creatures/GeneratedHumanCharacter3D.gd"), "NPC must inherit the Human character")
	check(actor.get_node("HumanGenerator").use_manual_layout, "NPC must retain the current authored Human layout")
	check(actor.get_node("GeneratedParts/Joints").get_child_count() == 13, "Human anatomy must retain all 13 joints")
	var inventory := actor.get_node("InventoryController3D")
	var weapon := inventory.get_equipped_item() as SampleWeapon3D
	check(weapon != null, "Automatic generation must equip the assigned initial weapon")
	if weapon == null:
		quit(1)
		return
	check(weapon.rigid_attachment_holder == actor.get_node("GeneratedParts/Arm_R"), "Initial weapon must bind to the hand, not the driven upper arm")
	check(weapon.wielder_character == actor and weapon.wielder_team_id == 1, "Weapon damage ownership must inherit the NPC faction")
	check(not inventory.get_node("InventoryBarUI").visible, "NPC must hide the player inventory HUD")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	check(movement.get_player_command_source() == ai and not movement.is_fast_speed_active(), "Human movement must use slow NPC commands")
	ai.current_state = ai.State.MOVE_TO_TARGET
	ai.use_fast_movement = true
	check(movement.is_fast_speed_active(), "Optional AI fast movement must use the NPC command API")
	ai.use_fast_movement = false
	ai.current_state = ai.State.IDLE
	for tick: int in 228: await physics_frame
	var torso := actor.get_node("GeneratedParts/Torso") as PhysicalBodyPart3D
	var start := torso.global_position
	var steps: int = movement.get_step_sequence()
	ai.enabled = true
	ai.move_to_position(start + Vector3(12, 0, 0))
	for tick: int in 240: await physics_frame
	print("HUMAN_NPC_NAVIGATION displacement=", torso.global_position-start, " steps=", movement.get_step_sequence()-steps)
	check(torso.global_position.x > start.x+1.0 and movement.get_step_sequence() > steps, "Navigation commands must produce real leg steps and Torso movement")
	check(torso.global_basis.y.dot(Vector3.UP) > 0.8, "Armed Human must remain upright while walking")
	ai.stop()
	var swing := actor.get_node("LimbSwingController3D")
	var member: Dictionary = swing._states[0].members[0]
	check(swing._npc_member_shapes(member).size() > swing.HIT_PREDICTION.shapes(member.body).size(), "NPC prediction must include the forearm, hand and merged weapon shapes")
	var enemy := make_target(2, torso.global_position + Vector3(6,0,0))
	var ally := make_target(1, torso.global_position + Vector3(0,0,4))
	ai._enemy = enemy
	ai._target = enemy.get_node("Torso")
	enemy.global_position.x = torso.global_position.x-6.0
	check(not ai._try_attack(6.0) and ai._attack_block_reason == &"body_turn_pending", "Left-side attacks must wait for the leg-driven body turn")
	if "--left-target" not in OS.get_cmdline_user_args(): enemy.global_position.x = torso.global_position.x+6.0
	ai.resume_autonomous()
	var charged := false
	var released := false
	for tick: int in 900:
		await physics_frame
		charged = charged or swing.get_group_state(0) == swing.SwingState.CHARGING
		released = released or weapon.swing_sequence > 0
		if tick % 180 == 179: print("HUMAN_NPC_COMBAT ", ai.get_state_diagnostics(), " ranges=", ai.get_attack_range_diagnostics())
		if released: break
	check(ai._enemy == enemy, "Autonomous targeting must ignore a closer friendly actor")
	check(charged and released, "Autonomous Human AI must predict, charge and swing its weapon")
	check(ai._body_facing_ready(), "The generated body must face the chosen side before attacking")
	print("HUMAN_NPC_ATTACK charge=", charged, " swing_sequence=", weapon.swing_sequence, " state=", ai.get_state_diagnostics().state)
	ai.enabled = false
	ai.stop()
	ally.free()
	enemy.free()
	# Regeneration must rebind the same stored item instead of spawning duplicates.
	var old_hand: Node = weapon.rigid_attachment_holder
	check(actor.generate_creature(), "Human NPC must support regeneration")
	for tick: int in 4: await physics_frame
	check(inventory.get_equipped_item() == weapon and weapon.rigid_attachment_holder != old_hand, "Regeneration must preserve and rebind initial equipment")
	var items := 0
	for item: Variant in inventory.get_items():
		if is_instance_valid(item): items += 1
	check(items == 1, "Regeneration must not duplicate the initial weapon")
	var controller: Node3D = load("res://Scenes/Player/Controller.tscn").instantiate()
	controller.initial_character = actor
	controller.diagnostic_logging = false
	level.add_child(controller)
	for tick: int in 3: await physics_frame
	check(controller.get_controlled_character() == actor and movement.get_player_command_source() == controller and not ai.is_physics_processing(), "Player takeover must replace commands and suspend AI")
	controller.detach_character()
	check(movement.get_player_command_source() == ai and ai.is_physics_processing(), "Detaching Controller must restore NPC command ownership")
	var hand := actor.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	hand.break_part()
	await physics_frame
	check(inventory.get_equipped_item() == null and weapon.can_be_picked_up, "Broken hand must drop the initial weapon through the shared inventory system")
	var bare := NPC.instantiate() as Node3D
	bare.generate_on_ready = false
	bare.initial_weapon_scene = null
	bare.get_node("NPCStateMachine3D").enabled = false
	bare.position.x = 30.0
	level.add_child(bare)
	for tick: int in 4: await physics_frame
	check(bare.get_node("InventoryController3D").get_equipped_item() == null and bare.get_node("GeneratedParts/Joints").get_child_count() == 13, "Saved assembly must support an unarmed NPC without regeneration")
	level.free()
	await process_frame
	print("HUMAN_NPC_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
