extends SceneTree

const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Snake.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn")
const ROUTE = preload("res://Scripts/Creatures/SnakeGroundPath.gd")
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

func check_route() -> void:
	var route := ROUTE.new()
	route.reset(Vector3(3,0,7),Vector3.RIGHT,40.0,10.0,0.4,0.1)
	check(absf(Vector3(route.sample(-2.0).position).z-7.0) > .3,"Initial history already contains the S curve instead of a long straight ramp")
	route.ensure(20.0,20.0,Vector3.RIGHT)
	var frozen: Dictionary = route.sample(15.0)
	var error := 0.0
	for i: int in 100:
		var s := i*0.2
		var point: Vector3 = route.sample(s).position
		error = maxf(error,absf(route.project(point,s,0.3)-s))
	check(error < 0.00001,"Arc-length projection recovers each shared route position")
	route.ensure(20.0,30.0,Vector3.BACK)
	check(Vector3(route.sample(15.0).position).is_equal_approx(frozen.position),"Turning replans only the unvisited preview")
	for s: float in [20.0,40.0,80.0,160.0,320.0]: route.ensure(s,20.0,Vector3.RIGHT)
	check(route.points.size() < 700,"World route history has a fixed memory budget")
	for s: float in [280.0,160.0,40.0,-80.0,-160.0]:
		route.ensure(s,20.0,Vector3.RIGHT)
		var reversed: Dictionary = route.sample(s)
		check(absf(route.project(reversed.position,s,.3)-s) < .0001,"Reverse travel can extend history beyond the initial route")
		for i: int in route.points.size()-1:
			check(Vector3(route.points[i+1].position-route.points[i].position).length() < route.step*1.15,"Restoring trimmed history preserves wave continuity at both ends")
	check(route.points.size() < 900,"Reverse travel also has bounded route memory")
	var data := SnakeMotionData.new()
	check(data.is_valid(),"New route defaults are valid")
	check(is_equal_approx(data.spacing_wave_frequency_ratio,2.0) and is_equal_approx(preload("res://Resources/Movement/SnakeMotion.tres").spacing_wave_frequency_ratio,2.0),"Both script and shared preset default to two spatial spacing cycles")
	data.path_joint_slide_widths = 0.5
	check(not data.is_valid(),"Route sliders cannot silently shrink the authored joint travel")
	data.path_joint_slide_widths = 4.0
	data.path_wavelength_ratio = NAN
	check(not data.is_valid(),"Non-finite route settings are rejected")
	for property: String in ["spacing_wave_amplitude_ratio","spacing_wave_frequency_ratio","spacing_wave_phase_degrees"]:
		data = SnakeMotionData.new()
		data.set(property,NAN)
		check(not data.is_valid(),"Non-finite spacing wave settings are rejected")
	data = SnakeMotionData.new()
	data.spacing_wave_amplitude_ratio = 1.0
	check(not data.is_valid(),"Spacing amplitude leaves a joint travel reserve")
	data.spacing_wave_amplitude_ratio = .8
	data.spacing_wave_frequency_ratio = 0.0
	check(not data.is_valid(),"Zero spacing frequency is rejected")
	route.reset(Vector3(3,0,7),Vector3.RIGHT,40.0,10.0,.4,.02)
	route.ensure(20.0,20.0,Vector3.RIGHT)
	for point: Dictionary in route.points:
		check(absf(float(point.position.x)-3.0-float(point.u)) < .00001,"The route has no X wave")
		check(absf(float(point.position.z)-7.0-.4*sin(TAU*float(point.u)/10.0)) < .00001,"The original world-space Z sine is unchanged")
	for degrees: float in [75.0,90.0,180.0]:
		route.reset(Vector3(3,0,7),Vector3.RIGHT,40.0,10.0,.4,.1)
		route.ensure(20.0,20.0,Vector3.RIGHT)
		var corner_index: int = route._index(23.137)+1
		var corner: Dictionary = route.points[corner_index].duplicate()
		var preserved: Array[Dictionary] = route.points.slice(0,corner_index+1).duplicate(true)
		var heading := Basis(Vector3.UP,deg_to_rad(degrees))*Vector3.RIGHT
		route.ensure(20.0,30.0,heading,23.137)
		for index: int in preserved.size():
			check(Vector3(route.points[index].position).is_equal_approx(preserved[index].position),"Sharp turns preserve every occupied route point")
		check(Vector3(route.sample(corner.s).position).is_equal_approx(corner.position),"Rotating the sine preserves the corner position")
		check(Vector3(route.sample(float(corner.s)-.001).forward).dot(Vector3.RIGHT) > .99999,"The incoming segment keeps its original direction")
		check(Vector3(route.sample(float(corner.s)+.001).forward).dot(heading) > .99999,"The outgoing segment adopts the complete new direction immediately")
		var next: Dictionary = route.points[corner_index+1]
		var expected := Vector3(corner.position)+heading*route.step+heading.cross(Vector3.UP)*route.amplitude*(sin(TAU*float(next.u)/route.wavelength)-sin(TAU*float(corner.u)/route.wavelength))
		check(Vector3(next.position).distance_to(expected) < .00001,"A new direction makes a corner without a curved transition or lateral jump")
	# A 180-degree corner can retrace the same world positions; progress must choose the outgoing branch.
	route.reset(Vector3.ZERO,Vector3.RIGHT,10.0,10.0,0.0,.1)
	route.ensure(2.0,5.0,Vector3.RIGHT)
	route.ensure(2.0,5.0,Vector3.LEFT,2.0)
	var turn_index: int = route._index(2.0)+1
	var turn_s: float = route.points[turn_index].s
	var outgoing: Dictionary = route.sample(turn_s+.05)
	check(absf(route.project(outgoing.position,turn_s,.2,true)-turn_s-.05) < .00001,"Forward projection can leave an overlapping reversal without sticking to the incoming branch")

func check_spacing_targets(m: Node) -> void:
	for pair: Dictionary in m._spacing_pairs:
		if pair.is_empty(): continue
		check(m._parts[pair.a].belly and m._parts[pair.b].belly,"Arc-length constraints apply only between authored ground segments")
		var gap: float = float(m._parts[pair.b].path_distance)-float(m._parts[pair.a].path_distance)
		var extra: float = float(m._parts[pair.b].spacing_target_s)
		check(absf(gap-float(pair.gap)-extra) < .0005,"Adjacent parts use the requested arc-length spacing")
		check(absf(extra) <= float(pair.gap)*.15+.0005,"Arc-length spacing stays inside fifteen percent")
	for row: Dictionary in m._parts:
		check(Vector3(row.path_raw_target-row.path_route_target).distance_to(row.spacing_offset_world) < .0005,"Spacing wave changes arc length without rewriting the base route")

func check_spacing_guards(m: Node) -> void:
	var reference: Transform3D = m.get_pose_reference()
	reference.basis = m._path_pose_basis
	var head_index: int = m._parts.size()-1
	var body: RigidBody3D = m._parts[head_index].body
	var original := body.global_basis
	var before: Array[Dictionary] = m._plan_spacing_wave(reference,5.0,.2,0.0,0.0)
	body.global_basis = Basis(Vector3.UP,.35)*original
	var changed: Array[Dictionary] = m._plan_spacing_wave(reference,5.0,.2,0.0,0.0)
	check(absf(float(before[head_index].distance)-float(changed[head_index].distance)) < .00001,"Arc-length spacing does not depend on the part's local X rotation")
	body.global_basis = original
	var diagnostic: Dictionary = m.get_snake_motion_diagnostics(true)
	check(diagnostic.spacing_axis_mode == "path_arc_length" and diagnostic.parts[1].has("spacing_actual_s"),"Full motion logs expose path spacing and tracking error")
	check(diagnostic.parts[1].has("pair_force"),"Full motion logs expose the pairwise spring force")
	check(diagnostic.raised_path_mode == "authored_xy" and diagnostic.parts[head_index].path_role == "raised_rest","Motion logs identify the authored upper body pose separately")
	check(diagnostic.parts[head_index].connection_rule == "rest_pose" and not diagnostic.parts[head_index].has("spacing_actual_s"),"Upper connections report pose constraints rather than ground arc spacing")
	check(diagnostic.parts[head_index].has("raised_layout_error_xy"),"Full motion logs expose upper XY layout errors")
	var original_path: RefCounted = m._ground_path
	var original_anchor: Dictionary = original_path.sample(m._path_progress)
	var original_samples: Array[Dictionary] = []
	for index: int in m._parts.size(): original_samples.append(m._spacing_sample(index,m._parts[index].path_distance,reference,5.0))
	for direction: Vector3 in [Vector3.LEFT,Vector3.BACK]:
		var changed_path := ROUTE.new()
		changed_path.reset(Vector3.ZERO,direction,original_path.keep_length,original_path.wavelength,original_path.amplitude,original_path.step)
		# Rotate the same parameterized route, preserving its wave phase after earlier corners.
		var rotation := Basis(Vector3.UP,atan2(Vector3(original_anchor.forward).cross(direction).y,Vector3(original_anchor.forward).dot(direction)))
		changed_path.points = original_path.points.duplicate(true)
		for point: Dictionary in changed_path.points:
			point.position = rotation*Vector3(point.position)
			point.center = rotation*Vector3(point.center)
			point.forward = rotation*Vector3(point.forward)
		m._ground_path = changed_path
		var anchor: Dictionary = changed_path.sample(m._path_progress)
		for index: int in m._parts.size():
			if m._parts[index].belly: continue
			var sample: Dictionary = m._spacing_sample(index,m._parts[index].path_distance,reference,5.0)
			var offset: Vector3 = Vector3(sample.position-anchor.position).slide(Vector3.UP)
			var expected: Vector3 = Vector3(original_samples[index].position-original_anchor.position).slide(Vector3.UP)
			check(offset.distance_to(expected) < .0001,"Upper body arrangement is unchanged by reverse or sideways ground travel")
			var local: Vector3 = reference.basis.inverse()*(sample.position-anchor.position)
			var pivot: Dictionary = m._raised_turn_pivot()
			var rest: Vector3 = m._parts[index].rest.origin-Vector3(pivot.rest)+reference.basis.inverse()*(Vector3(pivot.world)-m._path_leader.body.global_position)
			check(absf(local.x-rest.x) < .0001,"Upper body samples retain the original signed X offsets, including backward bends")
			var relative_velocity: Vector3 = sample.tangent*5.0+sample.frame_velocity-Vector3(anchor.tangent)*5.0
			var expected_velocity: Vector3 = original_samples[index].tangent*5.0+original_samples[index].frame_velocity-Vector3(original_anchor.tangent)*5.0
			check(relative_velocity.distance_to(expected_velocity) < .0001,"Upper body waving velocity remains the same relative to its moving ground anchor")
	m._ground_path = original_path

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	check_route()
	var level := Node3D.new()
	root.add_child(level)
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	collider.shape.size = Vector3(2000,1,2000)
	ground.add_child(collider)
	ground.position.y = -0.5
	level.add_child(ground)
	for scenario: Vector2 in [Vector2(1,0),Vector2(2,0),Vector2(4,0),Vector2(1,PI/2)]:
		var actor := NPC.instantiate() if scenario.y > 0.0 else ACTOR.instantiate()
		actor.generate_on_ready = false
		actor.rotation.y = scenario.y
		actor.get_node("SnakeGenerator").overall_scale = scenario.x
		level.add_child(actor)
		check(actor.generate_creature(),"Generate world-path fixture")
		if actor.has_node("NPCStateMachine3D"): actor.get_node("NPCStateMachine3D").set_physics_process(false)
		var m := actor.get_node("SnakeMovementController3D")
		m.motion_data = m.motion_data.duplicate()
		var command := Command.new()
		command.facing = actor.global_basis.x
		level.add_child(command)
		m.command_source = command
		var head: RigidBody3D = actor.get_node("GeneratedParts/Head")
		var height := head.global_position.y
		for tick: int in 180: await physics_frame
		check(not m._path_ready,"Idle does not invent a moving ground route")
		var idle_sway_envelope: float = m._sway_max_amplitude
		check(head.global_position.y > height*0.85,"Idle raised posture is preserved")
		command.direction = command.facing
		var distance := 0.0
		var max_error := 0.0
		var max_slip := 0.0
		var max_cross_track := 0.0
		var max_target_cross_track := 0.0
		var crossed := {}
		var spacing_low := INF
		var spacing_high := -INF
		var actual_spacing_low := INF
		var actual_spacing_high := -INF
		var initial: Vector3 = m.get_control_anchor().global_position
		var expected_speed := preload("res://Scripts/Creatures/AxisMovement3D.gd").target_velocity(command.direction,m.motion_data.target_speed,m.motion_data.target_z_speed).dot(command.direction.normalized())
		var duration := ceili((m._belly.size()*1.5*scenario.x+30.0)/maxf(expected_speed,0.1)*60.0)
		for tick: int in duration:
			await physics_frame
			if not m._path_ready: continue
			if tick > 180:
				if tick % 30 == 0: check_spacing_targets(m)
				spacing_low = minf(spacing_low,float(m._parts[1].spacing_target_s))
				spacing_high = maxf(spacing_high,float(m._parts[1].spacing_target_s))
				for row: Dictionary in m._belly:
					max_error = maxf(max_error,Vector3(row.path_target-row.body.global_position).slide(Vector3.UP).length())
					var projection_radius: float = Vector3(row.spacing_offset_world).length()+.2*scenario.x+m._ground_path.step*3.0
					var nearest: float = m._ground_path.project(row.body.global_position,row.path_distance,projection_radius)
					max_cross_track = maxf(max_cross_track,Vector3(m._ground_path.sample(nearest).position-row.body.global_position).slide(Vector3.UP).length())
					var target_nearest: float = m._ground_path.project(row.path_target,row.path_distance,projection_radius)
					max_target_cross_track = maxf(max_target_cross_track,Vector3(m._ground_path.sample(target_nearest).position-row.path_target).slide(Vector3.UP).length())
					var marker: float = m._ground_path.wavelength*1.25
					if nearest >= marker and not crossed.has(row.body):
						crossed[row.body] = true
						check(Vector3(m._ground_path.sample(marker).position-row.body.global_position).slide(Vector3.UP).length() < .3*scenario.x,"Successive ground parts pass the same route marker")
				for row: Dictionary in m._sway_chain:
					if not is_instance_valid(row.sway_joint): continue
					var slip: Vector3 = JOINTS.collect(row.sway_joint).relative_anchor_offset_joint_a
					if row.body == m._parts[1].body:
						var spacing_detail: Dictionary = m.get_snake_motion_diagnostics(true).parts[1]
						actual_spacing_low = minf(actual_spacing_low,float(spacing_detail.spacing_actual_s))
						actual_spacing_high = maxf(actual_spacing_high,float(spacing_detail.spacing_actual_s))
					max_slip = maxf(max_slip,maxf(float(row.slide_lower)-slip.z,slip.z-float(row.slide_upper)))
					var x_limit: float = row.sway_joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
					var y_limit: float = row.sway_joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
					max_slip = maxf(max_slip,maxf(absf(slip.x)-x_limit,absf(slip.y)-y_limit))
					check(is_zero_approx(row.sway_joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)) and row.sway_joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) > 0.0,"Path joints allow limited passive yaw")
			if tick == duration-121: initial = m.get_control_anchor().global_position
		check(m._path_ready and m._path_blend > .999,"Movement engages the shared world route")
		check(m._path_amplitude > .3*scenario.x,"Independent route amplitude creates a visible S shape at every scale")
		check(m._spacing_blend > .999 and m._spacing_ratio > 0.0 and m._spacing_ratio <= .8,"The physical spacing wave is active with a safe amplitude")
		check(m._spacing_acceleration_bound <= m.motion_data.maximum_acceleration*.8,"Spacing acceleration leaves a reserve for tracking")
		check(spacing_high-spacing_low > .005*scenario.x,"The arc-length target alternately extends and contracts")
		check(actual_spacing_high-actual_spacing_low > .002*scenario.x,"Physical parts actually change their route spacing")
		check(absf(float(m._parts[m._spacing_anchor].path_distance)-m._path_progress) < .00001,"The leading grounded torso remains the route anchor")
		check(is_equal_approx(m._sway_max_amplitude,idle_sway_envelope),"Wider route sliders do not inflate the idle sway envelope")
		var debug: Dictionary = m.get_ground_path_debug_snapshot()
		check(debug.points.size() == 128 and debug.excludes.size() == m._parts.size()+1,"Bounded debug snapshot includes the route and excludes every owned body")
		distance = Vector3(m.get_control_anchor().global_position-initial).dot(command.direction)/2.0
		print("SNAKE_WORLD_ROUTE scale=",scenario.x," yaw=",scenario.y," speed=",distance," max_error=",max_error," cross_track=",max_cross_track," permitted_cross_track=",max_target_cross_track," marker_crossings=",crossed.size()," max_slip=",max_slip," head_height=",head.global_position.y," rest_height=",height," diag=",m.get_snake_motion_diagnostics(false))
		check(distance > expected_speed*0.8 and distance < expected_speed*1.2,"World route must preserve the target for its world movement axis")
		check(max_error < .2*scenario.x,"Ground segments accurately follow the shared route")
		check(max_cross_track < max_target_cross_track+.05*scenario.x,"Physical segments follow the S curve plus the permitted local-axis overlay")
		if scenario.x == 1.0: check(crossed.size() == m._belly.size(),"Every ground part passes the leader's marked route position")
		check(max_slip < .04*scenario.x,"Route remains compatible with existing sliders")
		check(head.global_position.y > height*.8,"Route preserves the raised XY S shape")
		var leader_distance: float = m._path_progress
		var route: RefCounted = m._ground_path
		for row: Dictionary in m._belly:
			var sample: Dictionary = route.sample(m._path_progress-float(row.path_gap))
			check(Vector3(sample.position-row.path_route_target).slide(Vector3.UP).length() < .0001,"Every ground segment retains the same unshifted world route")
		var period_length: float = route.wavelength
		m.motion_data.target_speed = 3.0
		for tick: int in 180: await physics_frame
		check(is_equal_approx(route.wavelength,period_length),"Changing speed does not stretch the spatial S pattern")
		check(absf(m._path_speed) > 2.0 and absf(m._path_speed) < 4.0,"Path progression follows real travel speed")
		command.direction = Vector3.ZERO
		for tick: int in 360: await physics_frame
		var stopped: Dictionary = route.sample(m._path_progress-1.0)
		var stopped_progress: float = m._path_progress
		for tick: int in 120: await physics_frame
		check(absf(m._path_progress-stopped_progress) < .05*scenario.x,"Stopped body does not continue advancing its ground wave")
		check(Vector3(route.sample(stopped_progress-1.0).position).is_equal_approx(stopped.position),"Stopping leaves the visited curve fixed in world space")
		check(m.get_snake_motion_diagnostics(false).actual_speed < .2,"World-route braking settles")
		check(is_zero_approx(m._spacing_blend),"Stopping smoothly removes the spacing wave")
		check(m._parts.all(func(row: Dictionary) -> bool: return absf(float(row.get("spacing_target_s",0.0))) < .0001),"Stopped parts return to their authored route spacing")
		check(m._parts.all(func(row: Dictionary) -> bool: return row.trajectory_offset.is_zero_approx()),"Old delayed horizontal chase is inactive")
		if scenario.x == 1.0 and scenario.y == 0.0:
			var before_reverse: float = m._path_progress
			var passed_point: Vector3 = route.sample(before_reverse-4.0).position
			command.direction = -command.facing
			for tick: int in 240: await physics_frame
			check(m._path_progress > before_reverse+8.0,"Reverse input extends the route forward instead of retracing it")
			check(m._spacing_phase_rate > 0.0,"Spacing waves keep advancing during a route reversal")
			check(Vector3(route.sample(before_reverse-4.0).position).is_equal_approx(passed_point),"The visited route remains fixed during a reversal")
			check(m._update_anchor().heading.dot(command.facing) > .95,"Route reversal keeps the shared body facing")
			command.direction = Vector3.ZERO
			command.facing = Vector3.LEFT
			for tick: int in 300:
				await physics_frame
				if m._raised_heading.x < -.995 and not m._path_turning: break
			print("SNAKE_ROUTE_TURN heading=",m._update_anchor().heading," diag=",m.get_snake_motion_diagnostics(false))
			check(m._raised_heading.x < -.99,"Raised body turns independently while the ground path remains active")
			check(m._path_ready and not route.turn_markers.is_empty(),"Turning records facing markers without replacing the route")
			check(route.sample(before_reverse-4.0).position.is_equal_approx(passed_point),"Turning retains visited geometry")
			command.direction = Vector3.LEFT
			for tick: int in 180: await physics_frame
			check(m._path_ready and not m._path_turning,"Travel continues on the retained route after the upper turn")
			if m._path_ready: check_spacing_guards(m)
		actor.set_temporary_ragdoll(command,true)
		check(not m._path_ready and m._ground_path.points.is_empty(),"Ragdoll releases the shared route")
		check(m._spacing_pairs.is_empty() and is_zero_approx(m._spacing_blend),"Ragdoll releases all spacing targets")
		for row: Dictionary in m._sway_chain:
			check(row.slide_upper >= row.base_slide_upper,"Ragdoll keeps mechanical travel available until anchors return inside the authored limits")
		actor.set_temporary_ragdoll(command,false)
		if scenario.x == 1.0 and scenario.y == 0.0: m.motion_data.spacing_wave_enabled = false
		check(actor.generate_creature(),"Regeneration rebuilds the route topology")
		command.facing = actor.global_basis.x
		command.direction = command.facing
		for tick: int in 120: await physics_frame
		check(m._path_ready,"Route restarts after regeneration")
		if not m.motion_data.spacing_wave_enabled:
			check(is_zero_approx(m._spacing_blend) and m._parts.all(func(row: Dictionary) -> bool: return absf(float(row.get("spacing_target_s",0.0))) < .0001),"The independent spacing switch preserves the unmodulated route and authored arc spacing")
		m.motion_data.ground_path_enabled = false
		for tick: int in 60: await physics_frame
		check(not m._path_ready,"Path switch returns ownership to the legacy controller")
		for row: Dictionary in m._sway_chain:
			if is_instance_valid(row.sway_joint):
				check(row.sway_joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT) >= row.base_slide_upper,"Legacy mode retains safe mechanical travel while joints relax")
		actor.free()
		command.free()
		await process_frame
	level.free()
	if not failed: print("SNAKE_WORLD_ROUTE_VALIDATION_PASSED")
	quit(1 if failed else 0)
