extends SceneTree

const WOLF = preload("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn")
var actors: Array[Node3D] = []

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400,1,400)
	collision.shape = box
	ground.add_child(collision)
	ground.position.y = -0.5
	stage.add_child(ground)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-200,0,-200),Vector3(-200,0,200),Vector3(200,0,200),Vector3(200,0,-200)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	stage.add_child(region)
	for index: int in 2:
		var actor := WOLF.instantiate() as Node3D
		actor.name = "AxisWolf"+str(index)
		actor.generate_on_ready = false
		actor.faction_id = index+1
		actor.position = Vector3(-25 if index == 0 else 25,0.03,-8 if index == 0 else 8)
		actor.rotation.y = 0.0 if index == 0 else PI
		actor.get_node("NPCStateMachine3D").enabled = false
		stage.add_child(actor)
		assert(actor.generate_creature())
		actors.append(actor)
	for tick: int in 180: await physics_frame
	for actor: Node3D in actors:
		var ai := actor.get_node("NPCStateMachine3D")
		ai.attack_execution_enabled = false
		ai.enabled = true
		ai.behavior = ai.behavior.duplicate(true)
		ai.behavior.require_line_of_sight = false
	var initial_gap := absf(actors[0].get_combat_anchor().global_position.z-actors[1].get_combat_anchor().global_position.z)
	var samples: Array[Dictionary] = []
	var peak_error := 0.0
	var final_gap := initial_gap
	for tick: int in 720:
		await physics_frame
		if tick % 30 != 29: continue
		var row := {"time":float(tick+1)/60.0,"actors":[]}
		for index: int in 2:
			var actor := actors[index]
			var ai := actor.get_node("NPCStateMachine3D")
			var movement := actor.get_node("GeneratedLegStepMovementController3D")
			var command: Vector3 = ai.get_generated_facing_direction(0.0)
			assert(is_zero_approx(command.z) and absf(command.x) == 1.0, "Lane alignment must retain a left/right heading")
			for part: RigidBody3D in actor._get_physical_body_parts():
				assert(part.global_position.is_finite() and not part.is_broken, "Approach must preserve an intact finite body")
			var error := rad_to_deg(absf(wrapf(atan2(-command.z,command.x)-movement._get_physical_heading_yaw(),-PI,PI)))
			peak_error = maxf(peak_error,error)
			row.actors.append({"position":actor.get_combat_anchor().global_position,"heading_error":error,
				"maximum_heading_error":rad_to_deg(movement._get_maximum_heading_error(atan2(-command.z,command.x))),
				"wolf_heading":movement.get_stance_support_diagnostics().wolf_heading,
				"goal":ai._requested_target_position,"turn":movement._layout_turn_status,"state":ai.State.keys()[ai.current_state]})
		final_gap = absf(actors[0].get_combat_anchor().global_position.z-actors[1].get_combat_anchor().global_position.z)
		row["z_gap"] = final_gap
		samples.append(row)
	var result := {"initial_z_gap":initial_gap,"final_z_gap":final_gap,"peak_heading_error":peak_error,"samples":samples}
	var file := FileAccess.open("res://Reports/NPCAxisPositioning_2026-10-19/wolf_approach.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("WOLF_AXIS_APPROACH_RESULT initial_z_gap=",initial_gap," final_z_gap=",final_gap," peak_heading_error=",peak_error)
	assert(final_gap < 1.5, "Opposing Wolves must converge toward the attack alignment band")
	assert(peak_error < 15.0, "Lateral approach must not cause a large physical heading drift")
	stage.free()
	await process_frame
	print("WOLF_AXIS_APPROACH_PASSED")
	quit()
