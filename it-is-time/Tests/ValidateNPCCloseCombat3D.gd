extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var far_chase := "--far-chase" in OS.get_cmdline_user_args()
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(240,1,240)
	collision.shape = box
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-100,0,-100),Vector3(-100,0,100),Vector3(100,0,100),Vector3(100,0,-100)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	root.add_child(region)
	var scene := load("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn") as PackedScene
	var npcs: Array[Node3D] = []
	var starts := [0,0]
	var max_walking_error := [0.0, 0.0]
	for index: int in range(2):
		var npc := scene.instantiate() as Node3D
		npc.name = "CombatNPC%d" % index
		npc.faction_id = index
		npc.position = (Vector3(-9.714691,0,-32.221535) if index == 0 else Vector3(50.44299,0,45.416046)) if far_chase else (Vector3(-8,0,-4) if index == 0 else Vector3(8,0,4))
		root.add_child(npc)
		for part: Node in npc.find_children("*","PhysicalBodyPart3D",true,false):
			part.max_hp = 10000.0
			part.current_hp = 10000.0
			part.armor = 500.0
		var brain := npc.get_node("NPCStateMachine3D")
		brain.state_changed.connect(func(_old: int, next: int) -> void:
			if next == brain.State.ATTACK: starts[index] += 1)
		npc.get_node("PhysicalFacingController3D").diagnostic_logging = false
		npcs.append(npc)
	for frame: int in range(3600 if far_chase else 1800):
		await physics_frame
		for index: int in npcs.size():
			var facing := npcs[index].get_node("PhysicalFacingController3D")
			var brain := npcs[index].get_node("NPCStateMachine3D")
			# Measure chase stability before combat starts; weapon impacts and
			# attack follow-through intentionally retain their physical response.
			if starts[index] == 0 and not facing.is_turning() and brain.current_state != brain.State.ATTACK:
				max_walking_error[index] = maxf(max_walking_error[index], absf(rad_to_deg(facing.get_turn_angle_error())))
		if frame % 180 == 0:
			for npc: Node3D in npcs:
				var brain := npc.get_node("NPCStateMachine3D")
				var facing := npc.get_node("PhysicalFacingController3D")
				print("CLOSE_FACING npc=%s turning=%s error=%.2f speed=%.3f" % [npc.name, facing.is_turning(), rad_to_deg(facing.get_turn_angle_error()), npc.get_node("Torso").angular_velocity.y])
				print("CLOSE_COMBAT frame=%d npc=%s starts=%s state=%s ranges=%s" % [frame,npc.name,starts,brain.get_state_diagnostics(),brain.get_attack_range_diagnostics()])
		if starts[0] > 0 and starts[1] > 0: break
	assert(starts[0] > 0 and starts[1] > 0, "Both approaching physical NPCs must reach a viable stance and attack")
	print("NPC_WALKING_ERROR far_chase=%s errors=%s" % [far_chase,max_walking_error])
	assert(max_walking_error[0] < 28.0 and max_walking_error[1] < 28.0, "Walking must not recreate the large heading drift")
	print("NPC_CLOSE_COMBAT_3D_VALIDATION_PASSED starts=%s max_walking_error=%s" % [starts,max_walking_error])
	quit()
