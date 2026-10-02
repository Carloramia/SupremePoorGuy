extends SceneTree

func _initialize() -> void:
	call_deferred("_diagnose")

func _diagnose() -> void:
	var level := load("res://Scenes/Levels/TestLevel.tscn").instantiate() as Node3D
	root.add_child(level)
	for _frame: int in range(10):
		await physics_frame
	var spawner := level.get_node("NavigationNPCSpawner3D")
	spawner.get_node("SpawnTimer").stop()
	var npc := spawner.try_spawn_npc() as Node3D
	assert(npc != null)
	var state_machine := npc.get_node("NPCStateMachine3D")
	var agent := state_machine.get_node("NavigationAgent3D") as NavigationAgent3D
	var controller := npc.get_node("NPCLegStepMovementController3D")
	var torso := npc.get_node("Torso") as RigidBody3D
	var start_position := torso.global_position
	for frame: int in range(480):
		await physics_frame
		if frame % 60 == 0:
			var grounded_count: int = 0
			for leg_name: StringName in [&"Leg_R", &"Leg_L"]:
				if controller.is_leg_grounded(npc.get_node(NodePath(leg_name)) as RigidBody3D):
					grounded_count += 1
			print(
				"NPC_DIAG t=", frame / 60.0,
				" state=", state_machine.State.keys()[state_machine.current_state],
				" input=", controller.get_input_movement_direction(),
				" step=", controller.get_step_state_name(),
				" grounded=", grounded_count,
				" nav_finished=", agent.is_navigation_finished(),
				" reachable=", agent.is_target_reachable(),
				" path_points=", agent.get_current_navigation_path().size(),
				" torso=", torso.global_position,
				" velocity=", torso.linear_velocity
			)
	var displacement := torso.global_position - start_position
	displacement.y = 0.0
	print("NPC_DIAG_RESULT horizontal_displacement=", displacement.length())
	assert(displacement.length() > 5.0)
	level.queue_free()
	quit()
