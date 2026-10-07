extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var level := load("res://Scenes/Levels/TestLevel.tscn").instantiate() as Node3D
	root.add_child(level)
	var actors: Array[Node3D] = [level.get_node("CharacterTestNPC"), level.get_node("CharacterTestNPC2")]
	var starts := [0, 0]
	for index: int in actors.size():
		var brain := actors[index].get_node("NPCStateMachine3D")
		brain.state_changed.connect(func(_previous: int, next: int) -> void:
			if next == brain.State.ATTACK: starts[index] += 1)
		for part: RigidBody3D in actors[index]._get_physical_body_parts():
			part.max_hp = 10000.0
			part.current_hp = 10000.0
			part.armor = 500.0
	for frame: int in range(2400):
		await physics_frame
		if frame % 180 == 0:
			for actor: Node3D in actors:
				var brain := actor.get_node("NPCStateMachine3D")
				print("LEVEL_COMBAT frame=%d starts=%s actor=%s state=%s ranges=%s" % [frame,starts,actor.name,brain.get_state_diagnostics(),brain.get_attack_range_diagnostics()])
		if starts[0] > 0 and starts[1] > 0:
			print("TEST_LEVEL_NPC_COMBAT_3D_VALIDATION_PASSED starts=%s frame=%d" % [starts,frame])
			quit()
			return
	assert(false, "Both NPCs in the actual TestLevel must initiate attacks")
