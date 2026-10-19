extends SceneTree

class Commands extends Node:
	var direction := Vector3.ZERO
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing
	func is_jump_requested() -> bool: return false
	func is_fast_movement_requested() -> bool: return false

var failed := false
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; print("HORNED_TURN_FAILED ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000,1,2000)
	collision.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(collision)
	level.add_child(floor_body)
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_HornedBeast.tscn").instantiate()
	actor.generate_on_ready = false
	level.add_child(actor)
	check(actor.generate_creature(),"generate")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	check(movement.stable_turn_control_enabled,"HornedBeast must reserve turn steps")
	var command := Commands.new()
	actor.add_child(command)
	movement.command_source = command
	for tick: int in 180: await physics_frame
	for side: float in [-1.0,1.0]:
		command.facing = Vector3.RIGHT*side
		command.direction = Vector3(side,0,0.2).normalized()
		var best := 180.0
		var starts := 0
		var last_sequence: int = movement.get_step_sequence()
		for tick: int in 900:
			await physics_frame
			var error: float = rad_to_deg(movement._get_maximum_heading_error(PI if side<0.0 else 0.0))
			best = minf(best,error)
			var sequence: int = movement.get_step_sequence()
			if sequence!=last_sequence: starts += 1; last_sequence = sequence
			if tick%180==179: print("HORNED_TURN_PROGRESS side=",side," seconds=",(tick+1)/60.0," error=",error," status=",movement._layout_turn_status," rejections=",movement._turn_landing_rejections," steps=",starts)
			if error<12.0: break
		check(best<15.0,"Turn must converge, side=%s best=%s"%[side,best])
		check(starts>0,"Turning must actively replace stance feet")
		for body: RigidBody3D in actor._get_physical_body_parts(): check(body.global_position.is_finite() and not body.is_broken,"Finite intact body")
	level.free()
	await process_frame
	print("HORNED_TURN_CONTROL_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
