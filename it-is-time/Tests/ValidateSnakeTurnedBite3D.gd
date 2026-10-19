extends "res://Tests/ValidateSnakeAttacks3D.gd"

class Command extends Node:
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return Vector3.ZERO
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000,1,2000)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var actor := NPC.instantiate()
	enable_attacks(actor)
	actor.generate_on_ready = false
	actor.get_node("SnakeGenerator").overall_scale = 1.0
	level.add_child(actor)
	check(actor.generate_creature(),"Generate turned-bite fixture")
	actor.get_node("NPCStateMachine3D").set_physics_process(false)
	var movement := actor.get_node("SnakeMovementController3D")
	var attack := actor.get_node("SnakeBiteAttackController3D")
	var command := Command.new()
	actor.add_child(command)
	movement.command_source = command
	for tick: int in 180: await physics_frame
	command.facing = Vector3.LEFT
	for tick: int in 360: await physics_frame
	print("SNAKE_IDLE_TURN_POSE upper=",movement._raised_heading," belly=",movement._update_anchor().heading," pivots=",movement._raised_turn_pivot()," connections=",movement._connection_diagnostics)
	check(movement._raised_heading.dot(Vector3.LEFT)>.99,"Raised reference faces left")
	check(movement._update_anchor().heading.dot(Vector3.RIGHT)>.95,"Stationary belly retains its original facing")
	var victim := CHARACTER.instantiate()
	victim.faction_id = 2
	var target: PhysicalBodyPart3D = PART.instantiate()
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso,PhysicalBodyPart3D.BodyPartTag.Head])
	target.max_hp = 1000000.0
	target.armor = 0.0
	target.left_distance = 1.0
	target.right_distance = 1.0
	target.top_distance = 1.0
	target.bottom_distance = 1.0
	target.collision_thickness = 2.0
	target.freeze = true
	victim.add_child(target)
	level.add_child(victim)
	target.global_position = attack.head.to_global(attack._mouth_offset())+Vector3.LEFT*3.0
	target.global_position.x = minf(target.global_position.x,movement.get_control_anchor().global_position.x-3.0)
	await physics_frame
	movement.command_source = null
	actor.get_node("NPCStateMachine3D")._generated_facing_side = -1.0
	var footprint: Dictionary = {}
	for row: Dictionary in movement._belly: footprint[row.body] = row.body.global_position
	var started: bool = attack.try_start_npc_attack(attack.ACTION,target,0.0)
	if not started: print("SNAKE_TURNED_BITE_PREDICTION ",attack.predict_npc_attack(attack.ACTION,target,0.0))
	check(started,"Start bite toward the independently turned side")
	var phases: Dictionary = {}
	var maximum_drift := 0.0
	var drift_by_phase: Dictionary = {}
	for tick: int in 1500:
		await physics_frame
		phases[attack._phase] = true
		if not attack.is_npc_attack_active(): break
		for row: Dictionary in movement._belly:
			var drift := Vector3(row.body.global_position-footprint[row.body]).slide(Vector3.UP).length()
			maximum_drift = maxf(maximum_drift,drift)
			drift_by_phase[attack._phase] = maxf(float(drift_by_phase.get(attack._phase,0.0)),drift)
	check(phases.has(&"lunging") and attack._last_reason==&"completed","Turned bite must pass preparation and finish")
	check(target.current_hp<target.max_hp,"Turned bite deals real damage")
	check(maximum_drift<0.3,"Bite cannot rotate or relocate the stationary belly")
	print("SNAKE_TURNED_BITE_RESULT started=",started," phases=",phases," reason=",attack._last_reason," drift=",maximum_drift," drift_by_phase=",drift_by_phase," damage=",target.max_hp-target.current_hp)
	level.free()
	await process_frame
	if not failed: print("SNAKE_TURNED_BITE_PASSED")
	quit(1 if failed else 0)
