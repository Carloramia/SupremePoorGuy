extends SceneTree

const BASE := "res://Assets/3DResources/Creatures/Human/"

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
	assert(manifest.models.size() == 88)
	assert(manifest.model_count == manifest.models.size())
	var human3_count := 0
	var new_counts := {4:0, 5:0}
	for record: Dictionary in manifest.models:
		if str(record.key).begins_with("human3_"): human3_count += 1
		var set_index := int(record.set)
		if new_counts.has(set_index): new_counts[set_index] += 1
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
		assert(part.get_node("JointIn").position.is_equal_approx(Vector3.ZERO))
		var end := Vector3(record.joint_out_local[0], record.joint_out_local[1], record.joint_out_local[2])
		assert(part.get_node("JointOut").position.is_equal_approx(end))
		var shape := part.get_node("CollisionShape3D").shape as ConvexPolygonShape3D
		assert(shape != null and shape.points.size() >= 8)
		var initial := shape_bounds(shape)
		assert(is_equal_approx(initial.size.z, 0.08))
		var alpha_size := Vector2(record.visible_world_size[0], record.visible_world_size[1])
		assert(absf(initial.size.x-alpha_size.x) < alpha_size.x/20.0)
		assert(absf(initial.size.y-alpha_size.y) < alpha_size.y/20.0)
		assert(part.get_node("CollisionShape3D").position.is_equal_approx(Vector3.ZERO))
		var unit: float = record.units_per_texture_pixel
		var expected_low := Vector2((record.alpha_bounds[0]-record.pivot_pixel[0])*unit, (record.pivot_pixel[1]-record.alpha_bounds[3])*unit)
		assert(absf(initial.position.x-expected_low.x) < alpha_size.x/20.0)
		assert(absf(initial.position.y-expected_low.y) < alpha_size.y/20.0)
		var second := scene.instantiate() as PhysicalBodyPart3D
		second.freeze = true
		root.add_child(second)
		await process_frame
		await process_frame
		assert(second.get_node("CollisionShape3D").shape != shape)
		part.paper_volume_thickness = 0.16
		var changed := shape_bounds(shape)
		assert(is_equal_approx(changed.size.z, 0.16))
		assert(is_equal_approx(initial.size.x, changed.size.x) and is_equal_approx(initial.size.y, changed.size.y))
		assert(is_equal_approx(shape_bounds(second.get_node("CollisionShape3D").shape).size.z, 0.08))
		var model_scene := load(BASE + str(record.scene)) as PackedScene
		var model := model_scene.instantiate()
		assert(model.get_node("PaperVolume").mesh.get_surface_count() == 3)
		model.free()
		part.queue_free()
		second.queue_free()
		await process_frame
		await process_frame
		print("HUMAN_PART_PASS ", record.name)
	assert(human3_count == 17)
	assert(new_counts == {4:17, 5:18})
	for filename: String in ["HumanPartsPreview.tscn", "Human1PartsPreview.tscn", "Human2PartsPreview.tscn", "Human3PartsPreview.tscn", "Human4PartsPreview.tscn", "Human5PartsPreview.tscn", "HumanAllPartsPreview.tscn"]:
		var gallery := (load(BASE + "Previews/" + filename) as PackedScene).instantiate()
		root.add_child(gallery)
		await process_frame
		assert(gallery.get_node("Camera3D").current)
		gallery.queue_free()
		await process_frame
	print("PASS: 88 Human PhysicalParts, three-surface volume meshes, winding, source textures, tags, markers, independent thickness and five-set galleries.")
	quit()
