extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_HornedBeast_SegmentedTail.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collider.shape = shape
	floor_body.add_child(collider)
	root.add_child(floor_body)
	floor_body.position.y = -0.5
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	actor.position.y = 0.15
	assert(actor.generate_creature())
	for tick in range(300):
		await physics_frame
		for node: Node in actor.get_node("GeneratedParts").get_children():
			if node is RigidBody3D:
				assert(node.global_position.is_finite())
				assert(not node.is_broken)
	var tip := actor.get_node("GeneratedParts/TailTip") as RigidBody3D
	tip.apply_torque_impulse(Vector3(0, 0, 0.1))
	for tick in range(120): await physics_frame
	for index in range(1, 4):
		var names := ["TailRoot", "TailTransition", "TailMiddle", "TailTip"]
		var a := actor.get_node("GeneratedParts/" + names[index-1]) as Node3D
		var b := actor.get_node("GeneratedParts/" + names[index]) as Node3D
		assert(a.get_node("JointOut").global_position.distance_to(b.get_node("JointIn").global_position) < 0.05)
	actor.free()
	floor_body.free()
	await process_frame
	print("PASS: four tail segments remain finite, intact and connected after settling and torque impulse.")
	quit()
