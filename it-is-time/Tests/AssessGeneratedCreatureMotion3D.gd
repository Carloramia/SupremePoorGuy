extends SceneTree
## Isolated flat-ground capability assessment. Does not change saved creature settings.

class Commands extends Node:
	var direction := Vector3.ZERO
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing
	func is_jump_requested() -> bool: return false
	func is_fast_movement_requested() -> bool: return false

var options: Dictionary = {}
var actor: Node3D
var movement: Node
var commands: Commands
var torsos: Array[RigidBody3D] = []
var parts: Array[RigidBody3D] = []
var rows: Array[Dictionary] = []
var result: Dictionary = {}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			options[argument.trim_prefix("--").get_slice("=",0)] = argument.substr(argument.find("=")+1)
	call_deferred("run")

func frames(count: int) -> void:
	for index: int in range(count): await physics_frame

func center() -> Vector3:
	var value := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in torsos:
		value += body.global_position * body.mass
		mass += body.mass
	return value / maxf(mass,0.001)

func sample(time: float) -> Dictionary:
	var velocity := Vector3.ZERO
	var mass := 0.0
	var tilt := 0.0
	for body: RigidBody3D in torsos:
		velocity += body.linear_velocity * body.mass
		mass += body.mass
		tilt = maxf(tilt,rad_to_deg(acos(clampf(body.global_basis.y.normalized().dot(Vector3.UP),-1.0,1.0))))
	velocity /= maxf(mass,0.001)
	var grounded := 0
	for foot: RigidBody3D in movement.get_leg_parts():
		if movement.is_leg_grounded(foot): grounded += 1
	var broken := 0
	var finite := true
	for body: RigidBody3D in parts:
		if body.is_broken: broken += 1
		finite = finite and body.global_position.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite()
	var position := center()
	return {"time":time,"x":position.x,"y":position.y,"z":position.z,"vx":velocity.x,"vy":velocity.y,"vz":velocity.z,
		"heading":rad_to_deg(movement._get_physical_heading_yaw()),"heading_error":rad_to_deg(movement._get_maximum_heading_error(PI if commands.facing.x < 0.0 else 0.0)),
		"tilt":tilt,"grounded":grounded,"steps":movement._active_steps.size(),"recovery":movement.recovery_control_active,
		"turn_status":str(movement._layout_turn_status),"planned_speed":movement.get_expected_horizontal_speed(),"broken":broken,"finite":finite}

func finish(code: int = 0) -> void:
	result["samples"] = rows
	var output: String = options.get("out","")
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		assert(file != null,"Assessment output must be writable")
		file.store_string(JSON.stringify(result,"\t"))
	print("CREATURE_ASSESSMENT_COMPLETE ",JSON.stringify(result.get("summary",result)))
	if is_instance_valid(actor): actor.queue_free()
	await process_frame
	quit(code)

func run() -> void:
	var label: String = options.get("scene","Generate_Spider")
	var phase: String = options.get("phase","x")
	var settle_seconds := float(options.get("settle","3.0"))
	assert(settle_seconds >= 3.0)
	var scene_path := "res://Scenes/Creatures/Characters/"+label+".tscn"
	result = {"scene":label,"phase":phase,"scene_path":scene_path,"physics_hz":Engine.physics_ticks_per_second,"seed":43,"settle_seconds":settle_seconds,"measurement":"mass-weighted Torso velocity; 10 Hz samples"}
	assert(Engine.physics_ticks_per_second == 60,"Use the project 60 Hz physics configuration")
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000,1,1000)
	collision.shape = box
	floor.add_child(collision)
	floor.position.y = -0.5
	root.add_child(floor)
	var packed := load(scene_path) as PackedScene
	assert(packed != null,"Assessment scene must exist")
	actor = packed.instantiate()
	actor.generate_on_ready = false
	if phase.begins_with("air"): actor.position.y = 30.0
	var ai := actor.get_node_or_null("NPCStateMachine3D")
	if ai != null:
		ai.enabled = false
		ai.set_physics_process(false)
	root.add_child(actor)
	var generator: Node = actor.get_node(actor.generator_path)
	if options.has("scale"): generator.overall_scale = float(options.scale)
	generator._random.seed = 43
	var generated: bool = actor.generate_creature()
	result["generated"] = generated
	if not generated:
		result["summary"] = {"error":"generation_failed"}
		await finish(1)
		return
	movement = actor.get_node("GeneratedLegStepMovementController3D")
	commands = Commands.new()
	root.add_child(commands)
	movement.command_source = commands
	torsos.assign(movement.get_torso_parts())
	parts.assign(actor._get_physical_body_parts())
	assert(not torsos.is_empty() and not movement.get_leg_parts().is_empty(),"Assessment requires torso and feet")
	var data: Resource = movement.slow_gait_data
	var total_mass := 0.0
	for body: RigidBody3D in parts: total_mass += body.mass
	result["config"] = {"movement_script":movement.get_script().resource_path,"gait":data.resource_path,"automatic":data.automatic_motion,
		"target_speed":data.target_speed,"turning_speed":data.turning_speed_degrees,"maximum_step_frequency":data.maximum_step_frequency,
		"overall_scale":generator.overall_scale,"part_count":parts.size(),"foot_count":movement.get_leg_parts().size(),"mass":total_mass,
		"planar":actor.planar_constraints_enabled,"ai_isolated":ai != null}
	result.config["stable_turn_control"] = movement.stable_turn_control_enabled
	result.config["bounded_stance_ratio"] = movement.grounded_stance_travel_ratio
	await frames(roundi(settle_seconds*60.0))
	result["settled"] = sample(0.0)
	var flight := actor.get_node_or_null("BirdFlightController3D")
	if flight != null:
		result.config["flight_speed"] = flight.horizontal_speed
		result.config["airborne_after_settle"] = flight.is_airborne()
	var turn := phase.ends_with("turn")
	commands.direction = Vector3.ZERO if phase == "idle" else Vector3.LEFT if phase in ["left","airleft","movingturn"] else Vector3.FORWARD if phase in ["up","airup"] else Vector3.BACK if phase.ends_with("z") else Vector3.ZERO if turn else Vector3.RIGHT
	commands.facing = Vector3.LEFT if turn else Vector3.RIGHT
	var z_motion := phase.ends_with("z") or phase in ["up","airup"]
	var count := 900 if turn else 360
	if options.has("duration"): count = roundi(float(options.duration) * 60.0)
	var aligned_frames := 0
	var completion_time := -1.0
	var initial := center()
	var start_us := Time.get_ticks_usec()
	for frame: int in range(count):
		await physics_frame
		if frame % 6 != 5: continue
		var row := sample(float(frame+1)/60.0)
		rows.append(row)
		if turn:
			aligned_frames = aligned_frames+6 if row.heading_error <= 10.0 else 0
			if aligned_frames >= 18 and completion_time < 0.0: completion_time = row.time
		if not row.finite: break
	result["simulation_wall_seconds"] = float(Time.get_ticks_usec()-start_us)/1000000.0
	var steady_speed := 0.0
	var cross_speed := 0.0
	var steady_count := 0
	var recovery_count := 0
	var peak_tilt := 0.0
	var maximum_broken := 0
	var maximum_heading_error := 0.0
	var active_samples := 0
	for row: Dictionary in rows:
		peak_tilt = maxf(peak_tilt,row.tilt)
		maximum_broken = maxi(maximum_broken,row.broken)
		if row.recovery: recovery_count += 1
		if row.steps > 0: active_samples += 1
		if row.time >= 3.0:
			steady_speed += row.vz if z_motion else row.vx
			cross_speed += absf(row.vx if z_motion else row.vz)
			maximum_heading_error = maxf(maximum_heading_error,row.heading_error)
			steady_count += 1
	var final := center()
	result["summary"] = {"steady_speed":steady_speed/maxi(steady_count,1),"cross_speed":cross_speed/maxi(steady_count,1),
		"displacement_x":final.x-initial.x,"displacement_z":final.z-initial.z,"height_change":final.y-initial.y,
		"peak_torso_tilt":peak_tilt,"recovery_fraction":float(recovery_count)/maxi(rows.size(),1),"maximum_broken":maximum_broken,
		"step_active_fraction":float(active_samples)/maxi(rows.size(),1),"turn_completion_seconds":completion_time,
		"turn_final_error":rows.back().heading_error if not rows.is_empty() else 180.0,"maximum_steady_heading_error":maximum_heading_error,
		"final_turn_status":str(movement._layout_turn_status),"final_airborne":flight.is_airborne() if flight != null else false}
	result["automatic_diagnostics"] = movement.get_automatic_motion_diagnostics()
	result["turn_diagnostics"] = movement._turn_drive_diagnostics.duplicate(true)
	result["contact_drive_diagnostics"] = movement.get_contact_drive_diagnostics()
	result["support_diagnostics"] = movement.get_stance_support_diagnostics()
	result["foot_diagnostics"] = []
	for foot: RigidBody3D in movement.get_leg_parts():
		result.foot_diagnostics.append({"foot":str(foot.name),"support":movement.get_support_foot_diagnostics(foot),"motion":movement.get_leg_step_diagnostics(foot)})
	await finish()
