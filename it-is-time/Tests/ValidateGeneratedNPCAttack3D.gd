extends SceneTree
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Creature_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
class PlayerProbe extends Node:
	var character: Node3D
	func get_controlled_character() -> Node3D: return character
	func gameplay_input_allowed() -> bool: return true
	func get_movement_direction() -> Vector3: return Vector3.ZERO
	func is_jump_requested() -> bool: return false
var failed := false
func check(value: bool,message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("RuntimeConsole")._damage_tracking_enabled = true
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300,1,300)
	collision.shape = box
	floor.add_child(collision)
	floor.position.y = -0.5
	root.add_child(floor)
	var npc = NPC.instantiate()
	npc.generate_on_ready = false
	var ai = npc.get_node("NPCStateMachine3D")
	ai.enabled = false
	ai.behavior = ai.behavior.duplicate(true)
	ai.behavior.require_line_of_sight = false
	ai.behavior.maximum_vertical_difference = 100.0
	root.add_child(npc)
	var generator = npc.get_node("CreatureGenerator")
	generator.neck_number = 0
	generator._random.seed = 43
	check(npc.generate_creature(),"NPC generation failed")
	var movement = npc.get_node("GeneratedLegStepMovementController3D")
	var module = npc.get_node("CreatureActionController3D")
	module.actions[0] = module.actions[0].get_script().new()
	for frame: int in range(240): await physics_frame
	check(npc.get_node("CharacterDamageController3D").team_id == 1,"Regeneration must preserve the faction")
	var enemy := Node3D.new()
	enemy.set_script(CHARACTER)
	root.add_child(enemy)
	enemy.position = npc.get_combat_anchor().global_position + Vector3(8,0,0)
	var torso = load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn").instantiate()
	torso.freeze = true
	enemy.add_child(torso)
	torso.global_position = Vector3(enemy.global_position.x,1.5,enemy.global_position.z)
	var player := PlayerProbe.new()
	player.character = enemy
	root.add_child(player)
	player.add_to_group(&"player_controller_3d")
	ai.enabled = true
	check(module.predict_npc_attack(&"foreleg_stomp",torso,0.6).hit,"Nearby grounded target must be inside the predicted expanding shockwave")
	var original_position: Vector3 = torso.global_position
	torso.global_position.y = 100.0
	check(not module.predict_npc_attack(&"foreleg_stomp",torso,0.6).hit,"A high target must be outside the spherical shockwave despite horizontal range")
	torso.global_position = original_position
	var started := false
	var completed := false
	var measured_impact := false
	for frame: int in range(400):
		await physics_frame
		if module.is_npc_attack_active(): started = true
		for row: Dictionary in module._feet:
			if float(row.get("stomp_impulse",0.0)) > 0.0: measured_impact = true
		if started and module.get_action_diagnostics().reason == &"completed":
			completed = true
			break
	check(started,"Generated NPC must start a real stomp with another character controlled by the player")
	check(completed,"NPC stomp must physically complete")
	var expected_waves := 0
	for foot: RigidBody3D in movement.get_leg_parts():
		if 4 in foot.tags: expected_waves += 1
	check(expected_waves > 0 and module._shockwaves_spawned == expected_waves,"Each front foot must create exactly one shockwave during a real NPC stomp")
	check(measured_impact,"Real stomp must measure a positive solver contact impulse")
	ai.enabled = false
	await physics_frame
	await physics_frame
	check(movement.get_input_movement_direction().is_zero_approx(),"Disabled AI must not fall back to player keyboard input")
	# Possession must suppress AI while returning the normal player command path.
	player.character = npc
	ai.enabled = true
	await physics_frame
	await physics_frame
	check(ai.current_state == ai.State.IDLE,"Possession must suspend autonomous attacks")
	print("GENERATED_NPC_ATTACK_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
