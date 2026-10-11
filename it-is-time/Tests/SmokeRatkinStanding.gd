extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Ratkin.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100,1,100)
	collider.shape = shape
	floor_body.add_child(collider)
	level.add_child(floor_body)
	floor_body.position.y = -0.5
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	level.add_child(actor)
	actor.position.y = 0.03
	assert(actor.generate_creature())
	var torso := actor.get_node("GeneratedParts/Torso") as RigidBody3D
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	var initial_y := torso.position.y
	for tick: int in 240:
		await physics_frame
		if tick % 60 == 59: print("RATKIN_STAND tick=", tick, " torso=", torso.position, " up=", torso.global_basis.y.dot(Vector3.UP), " feet=", movement.get_leg_parts().size())
	assert(torso.position.is_finite() and torso.global_basis.y.dot(Vector3.UP) > 0.8)
	assert(torso.position.y > initial_y * 0.7)
	var start := torso.global_position
	Input.action_press("Right")
	for tick: int in 180: await physics_frame
	Input.action_release("Right")
	print("RATKIN_WALK delta=", torso.global_position-start)
	assert(torso.global_position.x - start.x > 0.2)
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D: assert(part.position.is_finite() and not part.is_broken)
	level.free()
	await process_frame
	print("PASS: Ratkin remains standing with intact finite physical bodies.")
	quit()
