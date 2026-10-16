extends SceneTree

const BASE := "res://Assets/3DResources/Creatures/Snake/"

func _initialize() -> void:
	call_deferred("run")

func shape_bounds(shape: ConvexPolygonShape3D) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for point: Vector3 in shape.points:
		assert(point.is_finite())
		low = low.min(point)
		high = high.max(point)
	return AABB(low, high - low)

func check_winding(mesh: ArrayMesh) -> void:
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert(not vertices.is_empty() and not indices.is_empty())
		for index: int in range(0, indices.size(), 3):
			var a := indices[index]
			var b := indices[index+1]
			var c := indices[index+2]
			var cross := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
			# Godot front faces use clockwise winding, opposing the outward normal.
			assert(cross.dot(normals[a]) < 0.0, "Reversed face on surface %s" % surface)

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "Metadata/model_manifest.json"))
	assert(manifest.models.size() == 32)
	assert(manifest.model_count == manifest.models.size())
	var snake3_count := 0
	for record: Dictionary in manifest.models:
		if str(record.key).begins_with("snake3_"): snake3_count += 1
		var scene := load(record.physical_scene) as PackedScene
		assert(scene != null)
		var part := scene.instantiate() as PhysicalBodyPart3D
		assert(part != null)
		part.freeze = true
		root.add_child(part)
		await process_frame
		await process_frame
		assert(part.geometry_mode == PhysicalBodyPart3D.GeometryMode.CUSTOM_MODEL)
		assert(part.paper_volume_enabled and not part.sprite_visible and part.mesh_visible)
		assert(part.get_meta("anatomical_role") == record.role)
		assert(part.tags.size() == record.tags.size())
		for tag: int in record.tags:
			assert(tag in part.tags)
		var volume := part.get_node("Model/PaperVolume") as MeshInstance3D
		assert(volume.visible and volume.mesh.get_surface_count() == 3)
		check_winding(volume.mesh)
		var front := volume.mesh.surface_get_material(0) as StandardMaterial3D
		var back := volume.mesh.surface_get_material(1) as StandardMaterial3D
		assert(front.albedo_texture.resource_path == record.source)
		assert(front.albedo_texture == back.albedo_texture)
		assert(front.cull_mode == BaseMaterial3D.CULL_BACK and back.cull_mode == BaseMaterial3D.CULL_BACK)
		assert(volume.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] == volume.mesh.surface_get_arrays(1)[Mesh.ARRAY_TEX_UV])
		for visual: MeshInstance3D in part.get_node("Model").find_children("*", "MeshInstance3D", true, false):
			if visual != volume:
				assert(not visual.visible)
		assert(part.has_node("JointIn") and part.has_node("JointOut"))
		var calibrated_hinges := {"snake3_upper_jaw": Vector3(-0.0203747228, -0.0297291712, 0), "snake3_lower_jaw": Vector3(-0.0159957017, 0.0118393300, 0)}
		assert(part.get_node("JointIn").position.is_equal_approx(calibrated_hinges.get(record.key, Vector3.ZERO)))
		var end := Vector3(record.joint_out_local[0], record.joint_out_local[1], record.joint_out_local[2])
		assert(part.get_node("JointOut").position.is_equal_approx(end))
		var shape := part.get_node("CollisionShape3D").shape as ConvexPolygonShape3D
		assert(shape != null and shape.points.size() >= 8)
		var initial := shape_bounds(shape)
		assert(is_equal_approx(initial.size.z, 0.08 * 2.0))
		var alpha_size := Vector2(record.visible_world_size[0], record.visible_world_size[1])
		assert(absf(initial.size.x-alpha_size.x) < alpha_size.x/20.0)
		assert(absf(initial.size.y-alpha_size.y) < alpha_size.y/20.0)
		var second := scene.instantiate() as PhysicalBodyPart3D
		second.freeze = true
		root.add_child(second)
		await process_frame
		await process_frame
		assert(second.get_node("CollisionShape3D").shape != shape)
		part.paper_volume_thickness = 0.16
		var changed := shape_bounds(shape)
		assert(is_equal_approx(changed.size.z, 0.16 * 2.0))
		assert(is_equal_approx(initial.size.x, changed.size.x) and is_equal_approx(initial.size.y, changed.size.y))
		assert(is_equal_approx(shape_bounds(second.get_node("CollisionShape3D").shape).size.z, 0.08 * 2.0))
		var model_scene := load(BASE + str(record.scene)) as PackedScene
		var model := model_scene.instantiate()
		assert(model.get_node("PaperVolume").mesh.get_surface_count() == 3)
		model.free()
		part.queue_free()
		second.queue_free()
		await process_frame
		await process_frame
		print("SNAKE_PART_PASS ", record.name)
	assert(snake3_count == 12)
	for filename: String in ["SnakePartsPreview.tscn", "Snake1PartsPreview.tscn", "Snake2PartsPreview.tscn", "Snake3PartsPreview.tscn", "SnakeAllPartsPreview.tscn"]:
		var gallery := (load(BASE + "Previews/" + filename) as PackedScene).instantiate()
		root.add_child(gallery)
		await process_frame
		assert(gallery.get_node("Camera3D").current)
		gallery.queue_free()
		await process_frame
	print("PASS: 32 Snake PhysicalParts, three-surface volume meshes, winding, source textures, tags, markers, independent thickness and galleries.")
	quit()
