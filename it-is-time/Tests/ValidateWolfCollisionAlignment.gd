extends SceneTree
const GEO = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const SNAP = preload("res://Scripts/Creatures/Generators/ManualPartSnapshot.gd")
func _initialize() -> void: call_deferred("run")
func check(actor: Node) -> Dictionary:
	var visuals := {}
	var count := 0
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if not body is PhysicalBodyPart3D: continue
		visuals[str(body.name)] = body.transform
		var mesh := body.get_node("Model/PaperVolume") as MeshInstance3D
		var pose := SNAP.relative_transform(mesh,body)
		visuals[str(body.name)+"/Model/PaperVolume"] = pose
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(2)[Mesh.ARRAY_VERTEX]
		var box := AABB(pose*vertices[0],Vector3.ZERO)
		for vertex: Vector3 in vertices: box = box.expand(pose*vertex)
		var bounds := GEO.bounds(body)
		assert(bounds.position.distance_to(box.position)<0.0001,str(body.name)+" collider offset")
		assert(bounds.size.distance_to(box.size)<0.0001,str(body.name)+" collider size")
		count += 1
	assert(count==22)
	return visuals
func run() -> void:
	for path: String in ["res://Scenes/Creatures/Characters/Generate_Wolf.tscn","res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn"]:
		var actor = load(path).instantiate()
		actor.generate_on_ready=false
		root.add_child(actor)
		var before := check(actor)
		assert(actor.generate_creature())
		var after := check(actor)
		for key: String in before: assert(before[key].is_equal_approx(after[key]),key+" visual pose changed")
		actor.free()
		print("WOLF_COLLISION_ALIGNMENT_PASS ",path)
	await process_frame
	print("PASS: all 22 Wolf/NPC collider bounds match visual contours; generation preserves visual poses.")
	quit()
