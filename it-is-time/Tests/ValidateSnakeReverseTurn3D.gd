extends SceneTree

const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Snake.tscn")

class Command extends Node:
	var direction := Vector3.ZERO
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing

func _initialize() -> void: call_deferred("run")

func raised_snapshot(movement: Node, facing: Vector3) -> Dictionary:
	var head: Dictionary = movement._parts[-1]
	var leader: RigidBody3D = movement._path_leader.body
	var error := 0.0
	var pose_degrees := 0.0
	for row: Dictionary in movement._parts:
		if row.belly: continue
		error = maxf(error,row.body.global_position.distance_to(row.path_target))
		var target: Basis = movement._path_pose_basis*Basis(row.rest.basis)
		pose_degrees = maxf(pose_degrees,rad_to_deg(target.get_rotation_quaternion().angle_to(row.body.global_basis.orthonormalized().get_rotation_quaternion())))
	return {"head_x":Vector3(head.body.global_position-leader.global_position).dot(facing),
		"head_height":head.body.global_position.y-leader.global_position.y,
		"target_head_x":Vector3(head.path_target-movement._path_leader.path_target).dot(facing),
		"tracking_error":error,"pose_error_degrees":pose_degrees}

func raised_summary(samples: Array[Dictionary]) -> Dictionary:
	var result := {"head_x":0.0,"head_height":0.0,"target_head_x":0.0,"tracking_error":0.0,"pose_error_degrees":0.0}
	for row: Dictionary in samples:
		for key: String in ["head_x","head_height","target_head_x"]: result[key] += float(row[key])/samples.size()
		for key: String in ["tracking_error","pose_error_degrees"]: result[key] = maxf(result[key],row[key])
	return result

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
	var actor := ACTOR.instantiate()
	actor.generate_on_ready = false
	level.add_child(actor)
	if not actor.generate_creature():
		push_error("Snake generation failed")
		quit(1)
		return
	var movement := actor.get_node("SnakeMovementController3D")
	var command := Command.new()
	level.add_child(command)
	movement.command_source = command
	command.direction = Vector3.RIGHT
	var forward_samples: Array[Dictionary] = []
	for tick: int in 480:
		await physics_frame
		if tick >= 360 and movement._path_ready: forward_samples.append(raised_snapshot(movement,command.facing))
	if not movement._path_ready:
		push_error("Forward path did not start")
		quit(1)
		return
	var start: float = movement._path_progress
	var previous := start
	var minimum_facing := 1.0
	var minimum_segment_facing := 1.0
	var minimum_segment_name := ""
	var minimum_segment_tick := -1
	var maximum_gap_error := 0.0
	var maximum_gap_pair := -1
	var maximum_gap_tick := -1
	var maximum_gap_allowance := 0.0
	var maximum_mechanical_violation := 0.0
	var final_gap_error := 0.0
	var reverse_samples: Array[Dictionary] = []
	var minimum_head_x := INF
	command.direction = Vector3.LEFT
	for tick: int in 1200:
		await physics_frame
		if not movement._path_ready: continue
		if movement._path_progress < previous-0.001:
			push_error("Reverse command retraced the path")
			quit(1)
			return
		previous = movement._path_progress
		minimum_head_x = minf(minimum_head_x,Vector3(movement._parts[-1].body.global_position-movement._path_leader.body.global_position).dot(command.facing))
		if tick >= 1020: reverse_samples.append(raised_snapshot(movement,command.facing))
		minimum_facing = minf(minimum_facing,movement._update_anchor().heading.dot(command.facing))
		for row: Dictionary in movement._parts:
			# Raised parts have authored pitch, so compare their shared facing after removing that rest rotation.
			var segment_axis: Vector3 = (row.body.global_basis*Basis(row.rest.basis).inverse()).x.slide(Vector3.UP).normalized()
			var alignment := segment_axis.dot(command.facing)
			if alignment < minimum_segment_facing:
				minimum_segment_facing = alignment
				minimum_segment_name = row.body.name
				minimum_segment_tick = tick
		for pair: Dictionary in movement._spacing_pairs:
			if pair.is_empty(): continue
			var a: Dictionary = movement._parts[pair.a]
			var b: Dictionary = movement._parts[pair.b]
			var target: Vector3 = Vector3(b.path_target)-Vector3(a.path_target)
			var actual: Vector3 = b.body.global_position-a.body.global_position
			var gap_error := (target-actual).length()
			if gap_error > maximum_gap_error:
				maximum_gap_error = gap_error
				maximum_gap_pair = pair.b
				maximum_gap_tick = tick
				# A sharp reversal changes relative targets by up to twice their arc gap.
				maximum_gap_allowance = float(pair.gap)*2.0+.1
			if tick % 6 == 0:
				var joint: Generic6DOFJoint3D = b.incoming_joint
				var fa: Transform3D = a.body.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_a"))
				var fb: Transform3D = b.body.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_b"))
				var offset := fa.affine_inverse()*fb.origin
				for axis: int in 3:
					var getter: String = "get_param_"+["x","y","z"][axis]
					var lower: float = joint.call(getter,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)
					var upper: float = joint.call(getter,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
					maximum_mechanical_violation = maxf(maximum_mechanical_violation,maxf(lower-offset[axis],offset[axis]-upper))
			if tick == 1199: final_gap_error = maxf(final_gap_error,gap_error)
	var tangent: Vector3 = movement._ground_path.sample(movement._path_progress).tangent
	var forward := raised_summary(forward_samples)
	var reverse := raised_summary(reverse_samples)
	print("SNAKE_RAISED_COMPARISON forward=",forward," reverse=",reverse)
	print("SNAKE_REVERSE_TURN progress=",movement._path_progress-start," tangent=",tangent," facing=",minimum_facing," segment_facing=",minimum_segment_facing," segment=",minimum_segment_name," segment_tick=",minimum_segment_tick," gap_error=",maximum_gap_error," pair=",maximum_gap_pair," tick=",maximum_gap_tick," final_gap_error=",final_gap_error," mechanical_violation=",maximum_mechanical_violation)
	if movement._path_progress-start < 50.0 or tangent.dot(Vector3.LEFT) < .9 or minimum_facing < .9 or minimum_segment_facing < .8 or maximum_gap_error > maximum_gap_allowance or final_gap_error > .2 or maximum_mechanical_violation > .08:
		push_error("Reverse route did not complete while the body stayed connected and facing forward")
		quit(1)
		return
	if minimum_head_x <= 0.0 or absf(float(forward.head_x)-float(reverse.head_x)) > float(forward.head_x)*.05 or absf(float(forward.head_height)-float(reverse.head_height)) > float(forward.head_height)*.05 or reverse.pose_error_degrees > 10.0:
		push_error("Raised-chain reversal changed its authored height or posture unexpectedly")
		quit(1)
		return
	if not actor.generate_creature():
		push_error("Snake regeneration failed")
		quit(1)
		return
	command.direction = Vector3.LEFT
	for tick: int in 300:
		await physics_frame
		if not movement._path_ready: continue
		var head_offset: Vector3 = movement._parts[-1].body.global_position-movement._path_leader.body.global_position
		if head_offset.dot(command.facing) <= 0.0:
			push_error("Starting backward travel moved the raised body behind its ground anchor")
			quit(1)
			return
	print("SNAKE_BACKWARD_START raised=",raised_snapshot(movement,command.facing))
	print("SNAKE_REVERSE_TURN_VALIDATION_PASSED")
	quit(0)
