extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level := load("res://Scenes/Levels/TestLevel.tscn").instantiate() as Node3D
	root.add_child(level)
	var actors: Array[Node3D] = []
	var starts: Dictionary = {}
	var npc7 := level.get_node("CharacterTestNPC7")
	var facing7 := npc7.get_node("PhysicalFacingController3D")
	var movement7 := facing7.get_node(facing7.movement_controller_path)
	var initial_turn_completed := false
	var initial_turn_timed_out := false
	var turning_feet: Dictionary = {}
	for actor: Node in level.get_children():
		if not actor.has_node("NPCStateMachine3D"): continue
		actors.append(actor)
		starts[actor.name] = 0
		var brain := actor.get_node("NPCStateMachine3D")
		brain.state_changed.connect(func(_old: int, next: int) -> void:
			if next == brain.State.ATTACK: starts[actor.name] += 1)
		for body: RigidBody3D in actor._get_physical_body_parts():
			body.max_hp = 10000.0
			body.current_hp = 10000.0
			body.armor = 500.0
	for frame: int in range(3600):
		await physics_frame
		if not initial_turn_completed:
			initial_turn_timed_out = initial_turn_timed_out or facing7._npc_retry_correction
			if facing7.is_turning():
				var leg: RigidBody3D = movement7.get_active_leg()
				if is_instance_valid(leg): turning_feet[leg.name] = true
			elif npc7.get_node("Torso").global_basis.x.dot(Vector3.LEFT) > 0.98:
				initial_turn_completed = true
		if frame % 300 == 0:
			print("CROWD frame=%d attacks=%s" % [frame, starts])
			for actor: Node3D in actors:
				print("CROWD_STATE actor=%s state=%s ranges=%s" % [actor.name,actor.get_node("NPCStateMachine3D").get_state_diagnostics(),actor.get_node("NPCStateMachine3D").get_attack_range_diagnostics()])
		if starts.get(&"CharacterTestNPC2", 0) > 0 and starts.get(&"CharacterTestNPC7", 0) > 0:
			assert(initial_turn_completed and not initial_turn_timed_out, "NPC7 must finish its initial left turn without timing out")
			assert(turning_feet.has(&"Leg_L") and turning_feet.has(&"Leg_R"), "NPC7 must be able to alternate both feet during its turn")
			print("CROWDED_NPC_COMBAT_3D_VALIDATION_PASSED frame=%d attacks=%s" % [frame, starts])
			quit()
			return
	assert(false, "The previously blocked NPC2/NPC7 pair must be able to attack in the crowded level")
