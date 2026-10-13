extends SceneTree

const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Snake.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const JOINTS = preload("res://Scripts/Debug/JointMotionDiagnostics3D.gd")
var failed := false

class Command extends Node:
	var direction := Vector3.ZERO
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2000,1,2000)
	floor_body.add_child(shape)
	floor_body.position.y = -.5
	level.add_child(floor_body)
	for scenario: Vector2 in [Vector2(1,0),Vector2(4,0),Vector2(1,PI/2)]:
		var actor := NPC.instantiate() if scenario.y > 0 else ACTOR.instantiate()
		actor.generate_on_ready = false
		actor.rotation.y = scenario.y
		actor.get_node("SnakeGenerator").overall_scale = scenario.x
		level.add_child(actor)
		check(actor.generate_creature(), "Generate trajectory fixture")
		if actor.has_node("NPCStateMachine3D"):
			actor.get_node("NPCStateMachine3D").attack_execution_enabled = false
			check(actor.get_node("NPCStateMachine3D").enabled, "NPC remains available when attack execution is disabled")
			check(actor.get_node("NPCStateMachine3D")._available_attacks().is_empty(), "Disabled bite does not reserve an attack distance")
			actor.get_node("NPCStateMachine3D").set_physics_process(false)
		var m := actor.get_node("SnakeMovementController3D")
		m.motion_data = m.motion_data.duplicate()
		# This regression exercises the optional XY orbit independently of the default Z wave.
		m.motion_data.head_orbit_enabled = true
		m.motion_data.sway_enabled = false
		var command := Command.new()
		command.facing = actor.global_basis.x
		level.add_child(command)
		m.command_source = command
		check(m.locomotion_enabled and m.motion_data.head_orbit_enabled and m.motion_data.trajectory_following_enabled and not m.motion_data.sway_enabled, "New motion defaults")
		check(m._parts.size() == m._torsos.size()+1, "Jaw has no active trajectory or movement servo")
		check(m._parts[-1].leader.is_empty() and m._parts[-1].body.name == &"Head", "Topology leader is Head")
		for index: int in m._parts.size()-1:
			check(m._parts[index].leader.body == m._parts[index+1].body, "Follow actual connection order toward Head")
		for joint: Generic6DOFJoint3D in actor.get_node("GeneratedParts/Joints").get_children():
			if joint.get_meta("generated_connection_kind") == "SnakeJaw":
				check(is_zero_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)), "Jaw keeps locked translation")
				continue
			var length := minf(GEOMETRY.bounds(joint.get_node(joint.node_a)).size.x,GEOMETRY.bounds(joint.get_node(joint.node_b)).size.x)
			for axis: String in ["x","y"]:
				var slack := length * (0.15 if axis == "x" else 0.05)
				check(is_equal_approx(joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),slack), "Generated X/Y travel independently uses 15/5 percent of the shorter actual length")
		var sample := {"history":[{"time":0.0,"offset":Vector3(0,1,2)},{"time":0.1,"offset":Vector3(2,3,4)}]}
		check(m._sample_trajectory(sample,0.05).is_equal_approx(Vector3(1,2,3)), "Delayed samples interpolate displacement without collapsing spacing")
		var head_row: Dictionary = m._parts[-1]
		var head_height: float = head_row.body.global_position.y
		var low := Vector3(INF,INF,INF)
		var high := Vector3(-INF,-INF,-INF)
		var joint_error := 0.0
		for tick: int in 720:
			await physics_frame
			if tick < 240: continue
			var offset: Vector3 = m.get_pose_reference().affine_inverse()*head_row.body.global_position-head_row.rest.origin
			low = low.min(offset)
			high = high.max(offset)
			for row: Dictionary in m._parts:
				check(row.history.size() < 10, "Trajectory history stays bounded")
				if row.grounded: check(is_zero_approx(row.trajectory_offset.y) and is_zero_approx(row.trajectory_offset.z), "Grounded following is local X only")
				if not is_instance_valid(row.incoming_joint): continue
				var d: Dictionary = JOINTS.collect(row.incoming_joint)
				var relative: Vector3 = d.relative_anchor_offset_joint_a
				var x_slack: float = row.incoming_joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
				var y_slack: float = row.incoming_joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
				joint_error = maxf(joint_error,maxf(absf(relative.x)-x_slack,absf(relative.y)-y_slack))
		print("SNAKE_TRAJECTORY scale=",scenario.x," yaw=",scenario.y," head_range=",high-low," radius=",m._orbit_radius," joint_error=",joint_error," height=",head_row.body.global_position.y," rest_height=",head_height)
		check(is_equal_approx(m._orbit_radius,head_row.size.z*2), "Orbit radius uses actual PartWidth once")
		check(high.x-low.x > m._orbit_radius and high.y-low.y > m._orbit_radius*.5, "Head physically traverses a local XY orbit")
		check(joint_error < .1*scenario.x, "XY sliders remain within solver tolerance")
		check(head_row.body.global_position.y > head_height*.85, "Following preserves raised S structure")
		check(m._update_anchor().heading.dot(actor.global_basis.x) > .98, "Circular motion does not turn the creature")
		# Travel and stopping must work while the new trajectory remains active.
		for direction: Vector3 in [Vector3.RIGHT,Vector3.BACK]:
			command.direction = direction
			for tick: int in 120: await physics_frame
			var start: Vector3 = m.get_control_anchor().global_position
			for tick: int in 240: await physics_frame
			var mean_velocity: Vector3 = (m.get_control_anchor().global_position-start)/4.0
			print("SNAKE_TRAJECTORY_TRAVEL scale=",scenario.x," direction=",direction," mean_velocity=",mean_velocity)
			check(mean_velocity.dot(direction) > m.motion_data.target_speed*.8, "Orbit and following allow normal world X/Z movement")
		command.direction = Vector3.ZERO
		for tick: int in 120: await physics_frame
		var stopped: Vector3 = m.get_control_anchor().global_position
		for tick: int in 240: await physics_frame
		check(m.get_control_anchor().global_position.distance_to(stopped) < .5*scenario.x, "Stopping has no persistent drift over a full orbit")
		if scenario.y == 0:
			command.facing = Vector3.LEFT
			for tick: int in 1500:
				await physics_frame
				if m._update_anchor().heading.x < -.995: break
			check(m._update_anchor().heading.x < -.995, "Grounded turn works with the new trajectory active")
		# Verify the drive uses any current Torso contact, even a formerly raised front Torso.
		m.set_physics_process(false)
		for row: Dictionary in m._torsos: row.body._support_surface_contact = {}
		var front: Dictionary = m._torsos[-1]
		front.body._support_surface_contact = {"frame":Engine.get_physics_frames(),"normal":Vector3.UP,"collider_id":floor_body.get_instance_id()}
		command.direction = Vector3.RIGHT
		m._tick(1.0/60)
		check(m._contact_count == 1 and front.grounded and not front.belly, "Realtime support is independent of original belly classification")
		check(m._parts.all(func(row: Dictionary) -> bool: return not Vector3(row.movement_force).is_zero_approx()), "A single supporting Torso permits every Torso and Head to drive")
		front.body._support_surface_contact = {}
		m._tick(1.0/60)
		check(m._contact_count == 0 and m._drive_force.is_zero_approx(), "Complete loss of support stops all propulsion immediately")
		m.cancel_motion()
		check(m._parts.all(func(row: Dictionary) -> bool: return row.history.is_empty() and Vector3(row.trajectory_offset).is_zero_approx()), "Cancellation clears trajectory state")
		m.set_physics_process(true)
		check(actor.generate_creature(), "Regeneration refreshes followers and joint ranges")
		for tick: int in 60: await physics_frame
		check(m._orbit_time > 0 and not m._parts[-1].history.is_empty(), "Trajectory resumes after regeneration")
		var diag: Dictionary = m.get_snake_motion_diagnostics()
		check(diag.parts[-1].has("actual_motion_offset") and diag.parts[-1].has("movement_force"), "Diagnostics include trajectories and per-part drive")
		actor.set_temporary_ragdoll(command,true)
		check(m._orbit_time == 0 and m._drive_force.is_zero_approx(), "Ragdoll releases orbit and propulsion")
		actor.set_temporary_ragdoll(command,false)
		actor.free()
		command.free()
		await process_frame
	# A foreign dynamic body must not grant terrain support; ordinary parts keep their default behavior.
	var platform := RigidBody3D.new()
	platform.freeze = true
	platform.position = Vector3(500,1.5,0)
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(20,1,20)
	platform.add_child(collision)
	level.add_child(platform)
	var part: PhysicalBodyPart3D = load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn").instantiate()
	part.position = Vector3(500,5,0)
	part.surface_contact_tracking = true
	part.surface_contact_terrain_only = true
	level.add_child(part)
	for tick: int in 180: await physics_frame
	check(platform in part.get_colliding_bodies() and part.get_support_surface_contact().is_empty(), "Dynamic creatures/items cannot grant Snake terrain support")
	part.surface_contact_terrain_only = false
	part.sleeping = false
	for tick: int in 10: await physics_frame
	check(not part.get_support_surface_contact().is_empty(), "Other creatures retain support-contact defaults")
	level.free()
	if not failed: print("SNAKE_TRAJECTORY_VALIDATION_PASSED")
	quit(1 if failed else 0)
