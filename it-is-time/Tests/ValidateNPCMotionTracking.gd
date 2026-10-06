extends SceneTree

const NPC = preload("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func spawn(actor_name: String) -> Node3D:
	var actor := NPC.instantiate() as Node3D
	actor.name = actor_name
	actor.initial_weapon_scene = null
	actor.get_node("NPCStateMachine3D").enabled = false
	for part: Node in actor.find_children("*", "RigidBody3D", true, false): part.freeze = true
	root.add_child(actor)
	return actor

func run() -> void:
	var first := spawn("CharacterTestNPC")
	var second := spawn("CharacterTestNPC2")
	await process_frame
	var console := root.get_node("RuntimeConsole")
	var movement: Node = first.get_node("NPCLegStepMovementController3D")
	var execution: Dictionary = movement.get_npc_motion_execution_diagnostics()
	check(execution.legs.size() == 2, "Execution diagnostics must include both Hip joints")
	for row: Dictionary in execution.legs:
		check(row.has("hip_limits_xz") and row.hip_anchor_offset.length() < 0.001, "Initial Hip anchor frames must coincide")
	var foot: Node3D = first.get_node("Leg_R")
	var original := foot.global_position
	foot.global_position += Vector3(0.3,0,0)
	execution = movement.get_npc_motion_execution_diagnostics()
	for row: Dictionary in execution.legs:
		if row.foot == &"Leg_R": check(is_equal_approx(row.hip_anchor_offset.x,0.3), "Hip diagnostics must measure actual anchor separation")
	foot.global_position = original
	var machine: Node = first.get_node("NPCStateMachine3D")
	var path_index: int = machine.navigation_agent.get_current_navigation_path_index()
	check(machine.get_navigation_motion_diagnostics().has("enemy_direction"), "Path diagnostics must include the enemy direction")
	check(machine.navigation_agent.get_current_navigation_path_index() == path_index, "Diagnostics must not advance the navigation agent")
	console.set_process(false)
	check(not console._npc_motion_tracking_enabled, "NPC tracking must be off initially")
	check(console.execute_command("help").contains("tracknpcmotion"), "Help must list NPC motion tracking")
	check(console.execute_command("tracknpcmotion on").contains("matched=2"), "Both actors must be tracked without player possession")
	var lines: Array[String] = console._collect_npc_motion_snapshot()
	var parts := 0
	var legs := 0
	var states := 0
	for line: String in lines:
		check(line.begins_with("[npc_motion] npc_path=/root/CharacterTestNPC"), "Each row must identify its NPC")
		check(" npc_id=" in line, "Each row must contain a stable instance identity")
		if " part=" in line:
			parts += 1
			check("angular_velocity=" in line and "velocity=" in line, "All body rows must report motion")
		if " leg=" in line:
			legs += 1
			check("grounded=" in line and "attached=" in line and "target=" in line, "Leg rows must include contact and gait")
		if " state={" in line: states += 1
	check(parts == 12 and legs == 4 and states == 2, "Both complete six-part NPCs must be sampled")
	console.execute_command("tracknpcmotion on CharacterTestNPC2")
	lines = console._collect_npc_motion_snapshot()
	for line: String in lines: check("npc_path=/root/CharacterTestNPC2 " in line, "Exact name filtering must isolate the second actor")
	console.execute_command("tracknpcmotion on " + str(first.get_instance_id()))
	for line: String in console._collect_npc_motion_snapshot():
		check("npc_path=/root/CharacterTestNPC " in line, "ID filtering must isolate the first actor")
	console.execute_command("tracknpcmotion on /root/CharacterTestNPC2")
	check(console._collect_npc_motion_snapshot().size() == lines.size(), "Path filtering must match the same actor")
	console._npc_motion_elapsed = 0.0
	var sequence: int = console._motion_snapshot_sequence
	console._process(0.099)
	check(console._motion_snapshot_sequence == sequence, "Sampling must wait for the interval")
	console._process(0.002)
	check(console._motion_snapshot_sequence > sequence, "Sampling must run at 0.1 seconds")
	console.execute_command("tracknpcmotion off")
	sequence = console._motion_snapshot_sequence
	console._process(1.0)
	check(console._motion_snapshot_sequence == sequence, "Off must stop motion snapshots")
	console.execute_command("tracknpcmotion on")
	var late := spawn("LateNPC")
	check(console._emit_npc_motion_snapshot() == 3, "Newly spawned NPCs must be included automatically")
	second.queue_free()
	check(console._emit_npc_motion_snapshot() == 2, "Pending deletion must exclude the NPC safely")
	console.execute_command("tracknpcmotion off")
	first.queue_free()
	late.queue_free()
	await process_frame
	print("NPC_MOTION_TRACKING_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
