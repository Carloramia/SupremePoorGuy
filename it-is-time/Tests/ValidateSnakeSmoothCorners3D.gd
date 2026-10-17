extends SceneTree

const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Snake.tscn")
const ROUTE = preload("res://Scripts/Creatures/SnakeGroundPath.gd")
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
	for property: String in ["path_execution_response_time","path_maximum_jerk","path_corner_rounding_widths"]:
		var data := SnakeMotionData.new()
		data.set(property,NAN)
		check(not data.is_valid(),"Invalid execution settings must be rejected")
	var route := ROUTE.new()
	route.reset(Vector3.ZERO,Vector3.RIGHT,40.0,10.0,0.0,.1)
	route.ensure(5.0,10.0,Vector3.LEFT)
	var s: float = route.corners[0].s
	check(route.corner_speed_limit(s-.4,5,18,180,.4) < 5.0,"Braking anticipates the corner")
	check(route.corner_speed_limit(s,5,18,180,.4) > 0.0,"A reversal can leave the corner instead of stalling forever")
	check(is_equal_approx(route.corner_speed_limit(s+5.0,5,18,180,.4),5.0),"Speed recovers outside the corner")
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2000,1,2000)
	floor_body.add_child(shape)
	floor_body.position.y = -.5
	level.add_child(floor_body)
	for scale_value: float in [1.0,2.0]:
		var actor := ACTOR.instantiate()
		actor.generate_on_ready = false
		actor.get_node("SnakeGenerator").overall_scale = scale_value
		level.add_child(actor)
		check(actor.generate_creature(),"Create sharp-corner fixture")
		var m := actor.get_node("SnakeMovementController3D")
		var command := Command.new()
		level.add_child(command)
		m.command_source = command
		for tick: int in 180: await physics_frame
		command.direction = Vector3.RIGHT
		for tick: int in 360: await physics_frame
		var previous := {}
		var max_jerk := 0.0
		var max_drive_jerk := 0.0
		var max_offset := 0.0
		var max_cross_track := 0.0
		var worst := {}
		for degrees: float in [75.0,165.0,345.0]:
			var start: float = m._path_progress
			var progress := 0.0
			var last_progress := start
			var recovery_ticks := 0
			command.direction = Basis(Vector3.UP,deg_to_rad(degrees))*Vector3.RIGHT
			for tick: int in 420:
				await physics_frame
				if not m._path_ready:
					check(m.is_connection_recovering() or m._path_turning,"Only a structural rejoin or whole-body turn may suspend the route")
					if recovery_ticks==0: print("SNAKE_CORNER_REJOIN ",m.get_snake_motion_diagnostics(false))
					recovery_ticks += 1
					previous.clear()
					last_progress = 0.0
					continue
				progress += maxf(m._path_progress-last_progress,0.0)
				last_progress = m._path_progress
				for row: Dictionary in m._parts:
					var a: Vector3 = row.path_acceleration
					var drive: Vector3 = row.path_drive_acceleration
					check(drive.length() <= maxf(m.motion_data.maximum_acceleration,m.motion_data.maximum_pose_acceleration)+.001,"Combined horizontal force stays inside one budget")
					if previous.has(row.body):
						var before: Dictionary = previous[row.body]
						max_drive_jerk = maxf(max_drive_jerk,drive.distance_to(before.drive)*60.0)
						if row.belly:
							max_jerk = maxf(max_jerk,a.distance_to(before.a)*60.0)
							check(a.length() <= m.motion_data.maximum_acceleration+.001,"Ground reference acceleration is bounded")
					previous[row.body] = {"a":a,"drive":drive}
					if row.belly:
						var offset := Vector3(row.path_target-row.path_raw_target).slide(Vector3.UP).length()
						var nearest: float = m._ground_path.project(row.path_target,row.path_distance,offset+m._ground_path.step*3.0)
						max_cross_track = maxf(max_cross_track,Vector3(row.path_target-m._ground_path.sample(nearest).position).slide(Vector3.UP).length())
						if offset > max_offset:
							max_offset = offset
							worst = {"part":row.body.name,"degrees":degrees,"tick":tick,"raw":row.path_raw_target,"executed":row.path_target,"v":row.path_velocity,"raw_v":row.path_raw_velocity,"limit":row.path_corner_speed,"actual":row.body.global_position,"progress":m._path_progress}
					else:
						var expected: Vector3 = row.rest.origin-m._path_leader.rest.origin
						var target: Vector3 = m._path_pose_basis.inverse()*(Vector3(row.path_target)-Vector3(m._path_leader.path_target))
						check(Vector2(expected.x-target.x,expected.y-target.y).length() < .0002,"Corner filtering preserves the full raised XY layout")
			check(progress > 10.0,"Sharp-corner execution keeps making progress")
			check(recovery_ticks<120,"Structural rejoining cannot indefinitely suspend corner movement")
			print("SNAKE_CORNER_PROGRESS angle=",degrees," distance=",progress," rejoin_ticks=",recovery_ticks," connections=",m.get_attack_connection_diagnostics())
		print("SNAKE_SMOOTH_CORNERS scale=",scale_value," reference_jerk=",max_jerk," drive_jerk=",max_drive_jerk," execution_offset=",max_offset," cross_track=",max_cross_track," speed=",m._actual_velocity.length())
		print("SNAKE_SMOOTH_WORST ",worst)
		check(max_jerk <= m.motion_data.path_maximum_jerk+.02,"Reference acceleration cannot jump at corners")
		check(max_drive_jerk <= m.motion_data.path_maximum_jerk+.02,"Combined actuator acceleration cannot jump at corners")
		var inertial_distance: float = pow(m.motion_data.target_speed,2.0)/m.motion_data.maximum_acceleration+m.motion_data.target_speed*m.motion_data.path_execution_response_time
		check(max_offset < inertial_distance+.5*scale_value,"Temporary route phase lag remains bounded by the braking/response distance")
		var braking_distance: float = pow(m.motion_data.target_speed,2.0)/(2.0*m.motion_data.maximum_acceleration)+m.motion_data.target_speed*m.motion_data.maximum_acceleration/m.motion_data.path_maximum_jerk
		check(max_cross_track < m._path_leader.size.z*m.motion_data.path_corner_rounding_widths+braking_distance,"A suddenly inserted corner stays within the physical braking envelope")
		for tick: int in 600: await physics_frame
		check(m._actual_velocity.length() > 4.0 and m._actual_velocity.length() < 6.0,"Requested speed returns after the complete chain passes the corners")
		command.direction = Vector3.ZERO
		for tick: int in 480: await physics_frame
		check(m._actual_velocity.length() < .2,"Execution settles after input is released")
		m._contact_count = 0
		m._support_blend = 0.0
		for row: Dictionary in m._parts: row.path_drive_acceleration = Vector3.RIGHT*10.0
		m._apply_path_horizontal_forces(1.0/60.0)
		check(m._parts.all(func(row: Dictionary) -> bool: return row.path_applied_force.is_zero_approx()),"Slew limiting cannot keep applying drive after ground support is lost")
		actor.free()
		command.free()
		await process_frame
	level.free()
	if not failed: print("SNAKE_SMOOTH_CORNERS_VALIDATION_PASSED")
	quit(1 if failed else 0)
