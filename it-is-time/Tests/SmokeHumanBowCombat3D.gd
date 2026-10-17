extends SceneTree
const NPC = preload("res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Bow_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const TORSO = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var count := 1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--count="): count = clampi(argument.trim_prefix("--count=").to_int(),1,8)
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,100)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-100,0,-50),Vector3(100,0,-50),Vector3(100,0,50),Vector3(-100,0,50)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	level.add_child(region)
	var actors: Array[Node3D] = []
	for index: int in count:
		var actor := NPC.instantiate() as Node3D
		actor.name = "BowNPC_"+str(index)
		actor.position.z = (float(index)-float(count-1)*0.5)*8.0
		actor.get_node("NPCStateMachine3D").enabled = false
		actor.get_node("InventoryController3D").attachment_debug_logging = false
		actors.append(actor)
		level.add_child(actor)
	for tick: int in 240: await physics_frame
	var targets: Array[PhysicalBodyPart3D] = []
	for actor: Node3D in actors:
		var torso: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Torso")
		var enemy := Node3D.new()
		enemy.set_script(CHARACTER)
		enemy.faction_id = actor.faction_id+1
		enemy.require_head_and_torso_connectivity = false
		var target := TORSO.instantiate() as PhysicalBodyPart3D
		target.name = "Torso"
		target.freeze = true
		target.max_hp = 10000.0
		target.current_hp = 10000.0
		target.armor = 0.0
		targets.append(target)
		enemy.add_child(target)
		level.add_child(enemy)
		enemy.global_position = torso.global_position+Vector3(35,0,0)
		actor.get_node("NPCStateMachine3D").enabled = true
	for tick: int in 1200:
		await physics_frame
	var measurements: Array[Dictionary] = []
	for actor: Node3D in actors:
		measurements.append(actor.get_node("BowAttackController3D").get_attack_diagnostics())
		actor.get_node("NPCStateMachine3D").enabled = false
		actor.get_node("BowAttackController3D").enabled = false
	# Let shots fired before the cutoff reach their targets before counting misses.
	for tick: int in 180: await physics_frame
	var success := true
	for index: int in actors.size():
		var actor := actors[index]
		var bow: Node = actor.get_node("BowAttackController3D")
		var torso: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Torso")
		var passed: bool = bow.shots_fired>=2 and bow.damaging_hits>=1 and torso.global_basis.y.dot(Vector3.UP)>0.7
		success = success and passed
		measurements[index].impacts = bow.hits
		measurements[index].damaging_hits = bow.damaging_hits
		measurements[index].hp_damage = targets[index].max_hp-targets[index].current_hp
		measurements[index].upright = torso.global_basis.y.dot(Vector3.UP)
		measurements[index].simulated_seconds = 20.0
		measurements[index].flight_drain_seconds = 3.0
		print("BOW_AUTONOMOUS_RESULT ",JSON.stringify(measurements[index])," passed=",passed)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file := FileAccess.open(argument.trim_prefix("--report="),FileAccess.WRITE)
			if file!=null: file.store_string(JSON.stringify(measurements,"\t"))
	level.free()
	for arrow: Node in get_nodes_in_group(&"bow_projectiles"): arrow.free()
	await process_frame
	quit(0 if success else 1)
