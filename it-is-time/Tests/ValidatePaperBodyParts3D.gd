extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var directory := "res://Scenes/Creatures/Bodyparts/PaperParts/ToSplit_1"
	var count := 0
	var movement: Node = load("res://Scripts/Creatures/NPCLegStepMovementController3D.gd").new()
	for group: String in ["Base","LeftLeg","RightLeg"]:
		for filename: String in DirAccess.get_files_at(directory.path_join(group)):
			if not filename.ends_with(".tscn"): continue
			var path := directory.path_join(group).path_join(filename)
			var scene := load(path) as PackedScene
			var part := scene.instantiate() as PhysicalBodyPart3D
			assert(part != null and not part.freeze,"New parts must inherit gameplay behavior and allow physics")
			assert(part.geometry_mode == part.GeometryMode.CUSTOM_MODEL)
			part.paper_volume_enabled = false
			part.freeze = true
			root.add_child(part)
			var source := load(part.get_meta("paper_source_scene")).instantiate() as RigidBody3D
			var collision := part.get_node("CollisionShape3D") as CollisionShape3D
			var source_collision := source.get_node("CollisionShape3D") as CollisionShape3D
			assert(collision.shape is ConvexPolygonShape3D)
			var authored_points: PackedVector3Array = source_collision.shape.points
			assert(collision.shape.points == authored_points)
			assert(collision.transform.is_equal_approx(source_collision.transform))
			assert(part.get_node("Model").transform.is_equal_approx(source.get_node("Model").transform))
			assert(part.get_node("JointIn").transform.is_equal_approx(source.get_node("JointIn").transform))
			assert(part.get_node("JointOut").transform.is_equal_approx(source.get_node("JointOut").transform))
			assert(not part.get_node("MeshInstance3D").visible and not part.get_node("Sprite3D").visible)
			assert(part.get_node("Model").visible and part.current_hp == part.max_hp)
			part.mesh_visible = false
			assert(not part.get_node("Model").visible)
			part.mesh_visible = true
			assert(part.get_node("Model").visible)
			part.left_distance = 20.0
			part.collision_thickness = 2.0
			part._sync_geometry()
			assert(collision.shape.points == authored_points,"Box-fit parameters must not replace custom geometry")
			assert(collision.transform.is_equal_approx(source_collision.transform))
			if filename == "04_foot.tscn":
				assert(part.has_body_tag(part.BodyPartTag.Leg))
				var sole: Vector3 = movement._get_foot_world_position(part)
				var lowest := INF
				for point: Vector3 in authored_points: lowest = minf(lowest,(collision.global_transform * point).y)
				assert(is_equal_approx(sole.y,lowest),"Foot contact must use the polygon bottom, not its pivot")
			var other := scene.instantiate() as PhysicalBodyPart3D
			var other_points: PackedVector3Array = other.get_node("CollisionShape3D").shape.points
			var changed: PackedVector3Array = collision.shape.points
			changed[0] += Vector3.UP
			collision.shape.points = changed
			assert(other.get_node("CollisionShape3D").shape.points == other_points,"Collision shapes must be independent between instances")
			other.free()
			source.free()
			part.free()
			count += 1
	movement.free()
	assert(count == 27)
	print("PAPER_BODY_PARTS_VALIDATION_PASSED count=",count)
	quit()
