extends SceneTree

const REPORT := "D:/GameJamWorkspace/Reports/RatBiteAndSpeed_2026-10-17/"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var label := args[args.find("--label")+1] if "--label" in args else "speed"
	var world: Node3D = load("res://Scenes/Levels/RatsTestLevel.tscn").instantiate()
	for key: String in ["GenerateRat1NPC","GenerateRat2NPC"]:
		var original := world.get_node(key)
		world.remove_child(original)
		original.free()
	var actors: Array[Node3D] = []
	for variant: int in [1,2]:
		var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Rat_%d_NPC.tscn" % variant).instantiate()
		actor.position = Vector3(-20,0.15,-6 if variant==1 else 6)
		actor.faction_id = 1
		var ai: Node = actor.get_node("NPCStateMachine3D")
		ai.behavior = ai.behavior.duplicate(true)
		ai.behavior.auto_find_enemies = false
		ai.attack_execution_enabled = false
		var movement: Node = actor.get_node("GeneratedLegStepMovementController3D")
		movement.slow_gait_data = movement.slow_gait_data.duplicate()
		if "--speed" in args: movement.slow_gait_data.target_speed = float(args[args.find("--speed")+1])
		movement.fast_gait_data = movement.slow_gait_data
		world.add_child(actor)
		actors.append(actor)
	root.add_child(world)
	current_scene = world
	for tick: int in 180: await physics_frame
	var rows: Array[Dictionary] = []
	for actor: Node3D in actors:
		var torso: RigidBody3D = actor.get_node("GeneratedParts/Torso")
		actor.get_node("NPCStateMachine3D").move_to_position(Vector3(25,0,torso.global_position.z))
		rows.append({"actor":actor.name,"target_speed":actor.get_node("GeneratedLegStepMovementController3D").slow_gait_data.target_speed,"samples":[],"max_tilt":0.0})
	for tick: int in 900:
		await physics_frame
		if tick%6!=0: continue
		for index: int in actors.size():
			var actor := actors[index]
			var torso: RigidBody3D = actor.get_node("GeneratedParts/Torso")
			var movement: Node = actor.get_node("GeneratedLegStepMovementController3D")
			var feet: Array[Dictionary] = []
			for foot: RigidBody3D in movement.get_leg_parts():
				var step: Dictionary = movement.get_leg_step_diagnostics(foot)
				feet.append({"name":foot.name,"stepping":movement.is_leg_stepping(foot),"grounded":movement.is_leg_grounded(foot),"step":step})
			var tilt := rad_to_deg(torso.global_basis.y.angle_to(Vector3.UP))
			rows[index].max_tilt = maxf(rows[index].max_tilt,tilt)
			rows[index].samples.append({"time":tick/60.0,"x":torso.global_position.x,"y":torso.global_position.y,"z":torso.global_position.z,"vx":torso.linear_velocity.x,"tilt":tilt,"feet":feet})
	for row: Dictionary in rows:
		var samples: Array = row.samples.filter(func(s): return s.time>=3.0)
		var speed := 0.0
		for sample: Dictionary in samples: speed += float(sample.vx)/samples.size()
		row["mean_speed"] = speed
		row["displacement_speed"] = (samples[-1].x-samples[0].x)/(samples[-1].time-samples[0].time)
		row["ratio"] = speed/float(row.target_speed)
		row["passed"] = row.ratio>=0.9 and row.ratio<=1.1 and row.max_tilt<35.0
		print("RATS_SPEED actor=",row.actor," target=",row.target_speed," mean=",speed," displacement=",row.displacement_speed," ratio=",row.ratio," max_tilt=",row.max_tilt," passed=",row.passed)
	DirAccess.make_dir_recursive_absolute(REPORT)
	var output := FileAccess.open(REPORT+label+".json",FileAccess.WRITE)
	output.store_string(JSON.stringify(rows,"\t"))
	output.close()
	world.free()
	await process_frame
	quit()
