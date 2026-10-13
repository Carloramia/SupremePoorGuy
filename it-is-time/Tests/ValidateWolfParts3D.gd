extends SceneTree
func _initialize() -> void: call_deferred("run")
func bounds(shape: ConvexPolygonShape3D) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for point: Vector3 in shape.points:
		low = low.min(point)
		high = high.max(point)
	return AABB(low, high-low)
func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Wolf/Metadata/model_manifest.json"))
	assert(manifest.models.size() >= 18)
	for record: Dictionary in manifest.models:
		var scene := load(record.physical_scene) as PackedScene
		assert(scene != null)
		var part := scene.instantiate() as PhysicalBodyPart3D
		assert(part != null)
		part.freeze = true
		root.add_child(part)
		await process_frame
		await process_frame
		var volume := part.get_node("Model/PaperVolume") as MeshInstance3D
		var shape := part.get_node("CollisionShape3D").shape as ConvexPolygonShape3D
		assert(shape != null and not shape.points.is_empty())
		assert(part.geometry_mode == PhysicalBodyPart3D.GeometryMode.CUSTOM_MODEL)
		assert(part.paper_volume_enabled and volume.visible)
		assert(volume.mesh.get_surface_count() == 3 and volume.mesh.surface_get_array_len(2) > 0)
		var front := volume.mesh.surface_get_material(0) as StandardMaterial3D
		var back := volume.mesh.surface_get_material(1) as StandardMaterial3D
		assert(front.albedo_texture != null and front.albedo_texture == back.albedo_texture)
		assert(volume.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] == volume.mesh.surface_get_arrays(1)[Mesh.ARRAY_TEX_UV])
		for visual: MeshInstance3D in part.get_node("Model").find_children("*", "MeshInstance3D", true, false):
			if visual != volume: assert(not visual.visible)
		assert(part.has_node("JointIn") and part.has_node("JointOut"))
		var expected := Vector3(record.joint_out_local[0],record.joint_out_local[1],record.joint_out_local[2])
		if part.get_meta("wolf_forward_axis", "") == "+X": expected *= Vector3(-1,1,-1)
		assert((part.get_node("JointOut") as Marker3D).position.is_equal_approx(expected))
		assert(part.tags.size() == record.tags.size())
		for tag: int in record.tags: assert(tag in part.tags)
		var initial := bounds(shape)
		assert(is_equal_approx(initial.size.z, 0.08))
		var second := scene.instantiate() as PhysicalBodyPart3D
		second.freeze = true
		root.add_child(second)
		await process_frame
		await process_frame
		assert(second.get_node("CollisionShape3D").shape != shape)
		part.paper_volume_thickness = 0.16
		var changed := bounds(shape)
		assert(is_equal_approx(changed.size.z, 0.16))
		assert(is_equal_approx(changed.size.x, initial.size.x) and is_equal_approx(changed.size.y, initial.size.y))
		assert(is_equal_approx(bounds(second.get_node("CollisionShape3D").shape).size.z, 0.08))
		part.queue_free()
		second.queue_free()
		await process_frame
		await process_frame
		print("WOLF_PART_PASS ", record.category, "/", record.name)
	var preview := load("res://Assets/3DResources/Creatures/Wolf/Previews/WolfPartsPreview.tscn") as PackedScene
	assert(preview != null)
	var gallery := preview.instantiate()
	assert(gallery != null)
	assert(gallery.has_node("LowerJaw"))
	root.add_child(gallery)
	await process_frame
	await process_frame
	gallery.queue_free()
	await process_frame
	await process_frame
	if manifest.models.any(func(record: Dictionary) -> bool: return str(record.key).begins_with("wolf2_")):
		var extra := load("res://Assets/3DResources/Creatures/Wolf/Previews/Wolf2PartsPreview.tscn") as PackedScene
		assert(extra != null)
		var extra_gallery := extra.instantiate()
		assert(extra_gallery.has_node("wolf2_torso") and extra_gallery.has_node("wolf2_head_main"))
		extra_gallery.free()
	print("PASS: ",manifest.models.size()," inherited PhysicalParts, front/back/side meshes, tags, markers, independent collision thickness and galleries.")
	quit()

