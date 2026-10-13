extends SceneTree

const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Snake.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn")
const JOINTS = preload("res://Scripts/Debug/JointMotionDiagnostics3D.gd")
var failed := false

class Command extends Node:
	var direction := Vector3.ZERO
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value and not failed:
		failed = true
		push_error(message)

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	collider.shape.size = Vector3(2000,1,2000)
	ground.add_child(collider)
	ground.position.y = -0.5
	level.add_child(ground)
	for scenario: Vector2 in [Vector2(1,0),Vector2(4,0),Vector2(1,PI/2)]:
		var actor := NPC.instantiate() if scenario.y > 0 else ACTOR.instantiate()
		actor.generate_on_ready = false
		actor.rotation.y = scenario.y
		actor.get_node("SnakeGenerator").overall_scale = scenario.x
		level.add_child(actor)
		check(actor.generate_creature(),"Generate centered-wave fixture")
		if actor.has_node("NPCStateMachine3D"): actor.get_node("NPCStateMachine3D").set_physics_process(false)
		var m := actor.get_node("SnakeMovementController3D")
		m.motion_data = m.motion_data.duplicate()
		check(m.motion_data.ground_path_enabled,"Shared world path is the default travelling mode")
		# Keep covering the optional legacy wave separately from the world-route regression.
		m.motion_data.ground_path_enabled = false
		check(m.motion_data.sway_enabled and not m.motion_data.head_orbit_enabled,"Default uses Z wave instead of XY orbit")
		var command := Command.new()
		command.facing = actor.global_basis.x
		level.add_child(command)
		m.command_source = command
		for body: Node in actor.get_node("GeneratedParts").get_children():
			if body is RigidBody3D: check(is_zero_approx(body.position.z),"All generated bodies including Jaw start at Z=0")
		check(m._sway_links == m._torsos.size()-m._belly.size()+1,"Cycle includes Head-Torso and the first ground connection")
		check(is_equal_approx(m._sway_period,m._sway_links*0.2),"Frequency derives from raised count and propagation delay")
		check(is_equal_approx(m._sway_max_ground_offset,m._sway_links*0.1*scenario.x),"Fixed Head reach sums scaled slider limits")
		check(not m._parts.any(func(row: Dictionary) -> bool: return row.body.name == &"Jaw"),"Jaw remains passive")
		check_wave_targets(m)
		var head: RigidBody3D = actor.get_node("GeneratedParts/Head")
		var head_height := head.global_position.y
		var low := INF
		var high := -INF
		var idle_belly_error := 0.0
		for tick: int in 480:
			await physics_frame
			if tick < 180: continue
			var inverse: Transform3D = m.get_pose_reference().affine_inverse()
			var z: float = (inverse*head.global_position-Vector3(m._parts[-1].rest.origin)).z
			low = minf(low,z)
			high = maxf(high,z)
			for row: Dictionary in m._belly:
				check(is_zero_approx(row.sway_offset),"Idle grounded targets do not wave")
				idle_belly_error = maxf(idle_belly_error,absf((inverse*row.body.global_position-Vector3(row.rest.origin)).z))
		print("SNAKE_CENTERED_IDLE scale=",scenario.x," yaw=",scenario.y," range=",Vector2(low,high)," amplitude=",m._sway_amplitude," belly_error=",idle_belly_error," diag=",m.get_snake_motion_diagnostics(false))
		check(low < -m._sway_amplitude*0.4 and high > m._sway_amplitude*0.4,"Head physically waves to both sides")
		check(idle_belly_error < 0.1*scenario.x,"Idle grounded Torso stays near its center plane")
		check(head.global_position.y > head_height*0.85,"Wave preserves the raised S pose")
		for direction: Vector3 in [Vector3.RIGHT,Vector3.BACK]:
			command.direction = direction
			for tick: int in 120: await physics_frame
			var start: Vector3 = m.get_control_anchor().global_position
			var ground_wave := 0.0
			var joint_error := 0.0
			for tick: int in 240:
				await physics_frame
				for row: Dictionary in m._belly: ground_wave = maxf(ground_wave,absf(row.sway_offset))
				for row: Dictionary in m._sway_chain:
					if not is_instance_valid(row.sway_joint): continue
					var slip: float = JOINTS.collect(row.sway_joint).relative_anchor_offset_joint_a.z
					joint_error = maxf(joint_error,maxf(float(row.slide_lower)-slip,slip-float(row.slide_upper)))
			var speed: float = ((m.get_control_anchor().global_position-start)/4.0).dot(direction)
			print("SNAKE_CENTERED_TRAVEL scale=",scenario.x," yaw=",scenario.y," direction=",direction," speed=",speed," ground_wave=",ground_wave," joint_error=",joint_error)
			check(speed > m.motion_data.target_speed*0.8,"Z wave permits target-speed X/Z travel")
			check(ground_wave > m._sway_amplitude*0.8 and m._sway_travel_blend > 0.999,"Ground Torso joins the moving wave")
			check(joint_error < 0.03*scenario.x,"Physical sliders stay inside centered limits with solver tolerance")
			check(m._parts.all(func(row: Dictionary) -> bool: return is_zero_approx(row.trajectory_offset.z)),"Trajectory follower does not duplicate Z wave")
		command.direction = Vector3.ZERO
		for tick: int in 360: await physics_frame
		print("SNAKE_CENTERED_STOP scale=",scenario.x," diag=",m.get_snake_motion_diagnostics(false))
		check(is_zero_approx(m._sway_travel_blend),"Stopping restores the idle envelope")
		check(m._belly.all(func(row: Dictionary) -> bool: return is_zero_approx(row.sway_offset)),"Grounded wave stops after braking")
		if scenario.x == 1.0 and scenario.y == 0.0:
			command.facing = Vector3.LEFT
			for tick: int in 1500:
				await physics_frame
				if m._update_anchor().heading.x < -.995: break
			check(m._update_anchor().heading.x < -.995,"Turning works while wave remains active")
		actor.set_temporary_ragdoll(command,true)
		check(m._sway_phase == 0.0 and m._sway_amplitude == 0.0,"Ragdoll cancels wave control")
		actor.set_temporary_ragdoll(command,false)
		check(actor.generate_creature(),"Regeneration rebuilds wave limits")
		for tick: int in 60: await physics_frame
		check(m._sway_time > 0.0,"Wave resumes after regeneration")
		var previous_period: float = m._sway_period
		actor.get_node("SnakeGenerator").raised_body_ratio = 0.2
		check(actor.generate_creature(),"Changing raised count regenerates the chain")
		check(m._sway_period < previous_period,"Fewer raised segments automatically shorten the complete-cycle period")
		m.motion_data.sway_enabled = false
		for tick: int in 120: await physics_frame
		check(is_zero_approx(m._sway_amplitude),"Wave switch releases its targets")
		actor.free()
		command.free()
		await process_frame
	level.free()
	if not failed: print("SNAKE_CENTERED_WAVE_VALIDATION_PASSED")
	quit(1 if failed else 0)

func check_wave_targets(m: Node) -> void:
	m.set_physics_process(false)
	m._support_blend = 1.0
	# Sample idle, every transition envelope, and running across more than two cycles.
	for tick: int in 600:
		m._direction = Vector3.RIGHT if tick >= 180 and tick < 420 else Vector3.ZERO
		m._actual_velocity = Vector3.ZERO
		var previous_phase: float = m._sway_phase
		m._update_sway(1.0/60.0)
		check(absf(wrapf(m._sway_phase-previous_phase,-PI,PI)-TAU/(60.0*m._sway_period)) < .00001,"Switching preserves phase advance")
		for index: int in m._sway_chain.size()-1:
			var row: Dictionary = m._sway_chain[index]
			var next: Dictionary = m._sway_chain[index+1]
			check(absf(row.sway_offset-next.sway_offset) <= -float(row.slide_lower)+.00001,"Wave fits adjacent limits throughout transitions")
			check(absf(next.sway_offset) <= m._sway_amplitude+.00001,"Torso stays within the calculated sine amplitude")
		if tick > 30 and tick < 180:
			check(m._belly.all(func(row: Dictionary) -> bool: return is_zero_approx(row.sway_offset)),"Idle envelope reaches zero at ground")
		if tick > 210 and tick < 420:
			check(is_equal_approx(m._sway_chain[0].sway_offset,m._sway_chain[m._sway_links].sway_offset),"Raised chain spans exactly one sine cycle")
	m.cancel_motion()
	m.set_physics_process(true)
