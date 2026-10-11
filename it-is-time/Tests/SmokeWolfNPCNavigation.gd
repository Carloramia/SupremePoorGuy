extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn")
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
	var region := NavigationRegion3D.new()
	var navmesh := NavigationMesh.new()
	navmesh.vertices = PackedVector3Array([Vector3(-50,0,-50),Vector3(50,0,-50),Vector3(50,0,50),Vector3(-50,0,50)])
	navmesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = navmesh
	level.add_child(region)
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.get_node("NPCStateMachine3D").enabled = false
	level.add_child(actor)
	actor.position.y = 0.03
	assert(actor.generate_creature())
	var torso := actor.get_node("GeneratedParts/Torso") as RigidBody3D
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	var initial_y := torso.position.y
	for tick: int in 240:
		await physics_frame
		if tick % 60 == 59: print("WOLF_STAND tick=", tick, " torso=", torso.position, " up=", torso.global_basis.y.dot(Vector3.UP), " feet=", movement.get_leg_parts().size())
	assert(torso.position.is_finite() and torso.global_basis.y.dot(Vector3.UP) > 0.8)
	assert(torso.position.y > initial_y * 0.7)
	var start := torso.global_position
	var ai := actor.get_node("NPCStateMachine3D")
	ai.enabled = true
	ai.move_to_position(start+Vector3(12,0,0))
	for tick: int in 180: await physics_frame
	ai.stop()
	print("WOLF_NPC_NAVIGATION delta=", torso.global_position-start)
	assert(torso.global_position.x - start.x > 0.2)
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D: assert(part.position.is_finite() and not part.is_broken)
	level.free()
	await process_frame
	print("PASS: Wolf remains standing with intact finite physical bodies.")
	quit()


