extends SceneTree
const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_HornedBeast.tscn")
class Command extends Node:
	var direction := Vector3.ZERO
	func get_movement_direction() -> Vector3: return direction
	func is_jump_requested() -> bool: return false
	func is_fast_requested() -> bool: return false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100,1,100)
	collision.shape = shape
	ground.add_child(collision)
	root.add_child(ground)
	ground.position.y = -0.5
	var actor := ACTOR.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor.generate_creature())
	var move := actor.get_node("GeneratedLegStepMovementController3D")
	var source := Command.new()
	actor.add_child(source)
	move.command_source = source
	for frame in range(120): await physics_frame
	var torso := actor.get_node("GeneratedParts/Torso") as RigidBody3D
	var start := torso.global_position
	source.direction = Vector3.RIGHT
	for frame in range(180): await physics_frame
	var dx := torso.global_position.x-start.x
	source.direction = Vector3.ZERO
	for frame in range(60): await physics_frame
	start = torso.global_position
	source.direction = Vector3.BACK
	for frame in range(180): await physics_frame
	var dz := torso.global_position.z-start.z
	print("BALANCE_AXES dx=",dx," dz=",dz," recovery=",actor.get_node("CreatureRecoveryStateMachine3D").get_recovery_diagnostics())
	assert(dx > 0.5 and dz > 0.5)
	assert(not move.recovery_control_active)
	actor.free()
	ground.free()
	await process_frame
	print("PASS: balanced HornedBeast moves in X and Z without recovery lock.")
	quit()
