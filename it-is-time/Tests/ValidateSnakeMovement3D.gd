extends SceneTree

const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Snake.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn")
const PLAYER = preload("res://Scenes/Player/Controller.tscn")

class Command extends Node:
	var direction := Vector3.ZERO
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 1, 2000)
	collider.shape = box
	ground.add_child(collider)
	ground.position.y = -0.5
	level.add_child(ground)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-900,0,-900),Vector3(900,0,-900),Vector3(900,0,900),Vector3(-900,0,900)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	level.add_child(region)
	for size: float in [1.0, 4.0]:
		var actor := ACTOR.instantiate()
		actor.generate_on_ready = false
		actor.get_node("SnakeGenerator").overall_scale = size
		actor.position.y = 0.01
		level.add_child(actor)
		assert(actor.generate_creature())
		var movement := actor.get_node("SnakeMovementController3D")
		movement.locomotion_enabled = true
		movement.motion_data = movement.motion_data.duplicate()
		movement.motion_data.sway_enabled = false
		movement.motion_data.head_orbit_enabled = false
		movement.motion_data.trajectory_following_enabled = false
		var command := Command.new()
		level.add_child(command)
		movement.command_source = command
		var head := actor.get_node("GeneratedParts/Head") as PhysicalBodyPart3D
		var head_y := head.global_position.y
		for tick: int in 180: await physics_frame
		print("SNAKE_STAND scale=",size," head_y=",head.global_position.y," initial=",head_y," diag=",summary(movement))
		assert(head.global_position.y > head_y * 0.8, "Raised S pose collapsed.")
		assert(movement.get_snake_motion_diagnostics().ground_contacts > 0)
		var start: Vector3 = movement.get_control_anchor().global_position
		command.direction = Vector3.RIGHT
		for tick: int in 240: await physics_frame
		print("SNAKE_FORWARD scale=",size," delta=",movement.get_control_anchor().global_position-start," diag=",summary(movement))
		assert(movement.get_snake_motion_diagnostics().actual_velocity.x > movement.motion_data.target_speed * 0.8, "Forward speed too low.")
		assert(head.global_position.y > head_y * 0.7)
		command.direction = Vector3.BACK
		for tick: int in 180: await physics_frame
		print("SNAKE_SIDE scale=",size," diag=",summary(movement))
		assert(movement.get_snake_motion_diagnostics().actual_velocity.z > movement.motion_data.target_speed * 0.8, "Side speed too low.")
		command.direction = Vector3.ZERO
		for tick: int in 120: await physics_frame
		assert(movement.get_snake_motion_diagnostics().actual_speed < 0.5, "Stopping failed.")
		command.facing = Vector3.LEFT
		var turn_ticks := 0
		for tick: int in 1800:
			await physics_frame
			turn_ticks = tick+1
			if movement._update_anchor().heading.x < -0.995 and movement.get_snake_motion_diagnostics().actual_speed < 0.2: break
		print("SNAKE_TURN scale=",size," duration=",turn_ticks/60.0," heading=",movement._update_anchor().heading," diag=",summary(movement))
		assert(movement._update_anchor().heading.x < -0.995, "Grounded turn failed.")
		assert(head.global_position.y > head_y * 0.8, "Raised pose collapsed during turning.")
		for part: Node in actor.get_node("GeneratedParts").get_children():
			if part is PhysicalBodyPart3D:
				assert(part.global_position.is_finite() and part.linear_velocity.length() < 50.0 and not part.is_broken)
		movement.set_character_control_enabled(false)
		assert(movement.get_snake_motion_diagnostics().drive_force.is_zero_approx())
		movement.set_character_control_enabled(true)
		actor.set_temporary_ragdoll(command, true)
		assert(not movement.can_process())
		assert(movement.get_snake_motion_diagnostics().drive_force.is_zero_approx())
		actor.set_temporary_ragdoll(command, false)
		assert(movement.can_process())
		actor.free()
		command.free()
		await process_frame
	# A character rotated in its parent scene must not receive that yaw twice.
	var rotated := ACTOR.instantiate()
	rotated.generate_on_ready = false
	rotated.get_node("SnakeGenerator").overall_scale = 0.5
	rotated.rotation.y = PI * 0.5
	level.add_child(rotated)
	assert(rotated.generate_creature())
	var rotated_motion := rotated.get_node("SnakeMovementController3D")
	rotated_motion.motion_data = rotated_motion.motion_data.duplicate()
	rotated_motion.motion_data.sway_enabled = false
	rotated_motion.motion_data.head_orbit_enabled = false
	rotated_motion.motion_data.trajectory_following_enabled = false
	var rotated_head := rotated.get_node("GeneratedParts/Head") as RigidBody3D
	var rotated_height := rotated_head.global_position.y
	for tick: int in 180: await physics_frame
	assert(rotated_head.global_position.y > rotated_height * 0.8)
	assert(rotated_motion._update_anchor().heading.z < -0.99)
	rotated.free()
	await process_frame
	var npc := NPC.instantiate()
	npc.generate_on_ready = false
	npc.get_node("SnakeGenerator").overall_scale = 1.0
	level.add_child(npc)
	assert(npc.generate_creature())
	for tick: int in 120: await physics_frame
	var movement := npc.get_node("SnakeMovementController3D")
	var ai := npc.get_node("NPCStateMachine3D")
	movement.locomotion_enabled = true
	movement.motion_data = movement.motion_data.duplicate()
	movement.motion_data.sway_enabled = false
	movement.motion_data.head_orbit_enabled = false
	movement.motion_data.trajectory_following_enabled = false
	ai.enabled = true
	var start: Vector3 = movement.get_control_anchor().global_position
	ai.move_to_position(start + Vector3(25,0,0))
	for tick: int in 180: await physics_frame
	assert(movement.get_control_anchor().global_position.x > start.x + 5.0, "NPC navigation did not drive the Snake.")
	var enemy := ACTOR.instantiate()
	enemy.generate_on_ready = false
	enemy.get_node("SnakeGenerator").overall_scale = 1.0
	enemy.get_node("SnakeMovementController3D").enabled = false
	enemy.position.x = movement.get_control_anchor().global_position.x + 100.0
	level.add_child(enemy)
	assert(enemy.generate_creature())
	for part: Node in enemy.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true
	start = movement.get_control_anchor().global_position
	ai.resume_autonomous()
	for tick: int in 180: await physics_frame
	assert(ai._enemy == enemy and ai.current_state == ai.State.MOVE_TO_TARGET)
	assert(movement.get_control_anchor().global_position.x > start.x + 5.0, "Autonomous enemy pursuit failed.")
	enemy.free()
	var player := PLAYER.instantiate()
	player.diagnostic_logging = false
	level.add_child(player)
	await process_frame
	assert(player.attach_character(npc))
	assert(movement.command_source == player and not ai.is_physics_processing())
	assert(player.get_control_anchor() == movement.get_control_anchor())
	player.detach_character()
	assert(movement.command_source == null and ai.is_physics_processing())
	player.free()
	var console := root.get_node("RuntimeConsole")
	console.execute_command("motiondetail full")
	var full_lines: Array[String] = console._collect_motion_snapshot(npc)
	assert("snake_motion=" in "\n".join(full_lines) and "surface_normal" in "\n".join(full_lines))
	console.execute_command("motiondetail summary")
	assert("snake_motion=" in "\n".join(console._collect_motion_snapshot(npc)))
	movement.set_control_performance_tracking_enabled(true)
	for tick: int in 5: await physics_frame
	assert(movement.consume_control_performance_stats().timings.has(&"snake_motion"))
	ai.stop()
	# An unsupported chain gets neither drive nor permanent gravity compensation.
	collider.set_deferred("disabled", true)
	for tick: int in 40: await physics_frame
	assert(movement.get_snake_motion_diagnostics().ground_contacts == 0)
	assert(movement.get_snake_motion_diagnostics().drive_force.is_zero_approx())
	assert(movement.get_snake_motion_diagnostics().support_blend == 0.0)
	var normal_valid: bool = await check_slope_contact(level)
	assert(normal_valid, "Solver surface normals must be in world coordinates.")
	# Breaking a part removes it from control and restores its ordinary collision material.
	var tail := npc.get_node("GeneratedParts/Torso_001") as PhysicalBodyPart3D
	tail.break_part()
	assert(not tail.surface_contact_tracking and tail not in movement.get_torso_parts())
	npc.get_node("GeneratedParts/Head").break_part()
	await process_frame
	await process_frame
	assert(not movement._character_enabled and not movement.is_physics_processing(), "Head death must disable Snake control.")
	level.free()
	await process_frame
	print("PASS: Snake scale 0.5/1/4 stand, target speed, lateral motion, braking, grounded turn, disable/ragdoll/break, NPC navigation/enemy pursuit, player attach/detach, motion/performance diagnostics and unsupported fall.")
	quit()

func summary(movement: Node) -> Dictionary:
	var result: Dictionary = movement.get_snake_motion_diagnostics(false)
	result.erase("parts")
	return result

func check_slope_contact(level: Node3D) -> bool:
	var slope := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	collider.shape = box
	slope.add_child(collider)
	slope.position = Vector3(300,0,0)
	slope.rotation.z = 0.2
	level.add_child(slope)
	var part := (load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn") as PackedScene).instantiate() as PhysicalBodyPart3D
	part.position = Vector3(300,3,0)
	part.rotation.z = -0.3
	part.surface_contact_tracking = true
	part.surface_contact_terrain_only = true
	level.add_child(part)
	for tick: int in 180: await physics_frame
	var contact := part.get_support_surface_contact()
	print("SNAKE_SLOPE_CONTACT contact=",contact," expected=",slope.global_basis.y," body=",part.global_transform," colliders=",part.get_colliding_bodies())
	var valid: bool = not contact.is_empty() and Vector3(contact.normal).dot(slope.global_basis.y) > 0.99
	part.surface_contact_tracking = false
	valid = valid and part.get_support_surface_contact().is_empty()
	part.free()
	slope.free()
	return valid
