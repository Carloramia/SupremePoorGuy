extends SceneTree
const BASE = "res://Assets/3DResources/Environment/FrontierBattle"
var parts: Array[StaticBody3D] = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE+"/Metadata/model_manifest.json"))
	assert(manifest.model_count == 22 and manifest.models.size() == 22)
	var asset_ids := []
	var triangle_count := 0
	for index: int in manifest.models.size():
		var record: Dictionary = manifest.models[index]
		assert(FileAccess.get_sha256(record.source) == record.source_sha256, "Original changed")
		assert(FileAccess.get_sha256(record.image) == FileAccess.get_sha256(record.texture))
		var picture := Image.load_from_file(ProjectSettings.globalize_path(record.image))
		assert(picture.get_size() == Vector2i(record.texture_size[0],record.texture_size[1]))
		for id: String in record.asset_ids: asset_ids.append(id)
		var mesh := load(record.volume_mesh) as ArrayMesh
		assert(mesh != null and mesh.get_surface_count() == 3)
		var face_material := mesh.surface_get_material(0) as StandardMaterial3D
		assert(face_material.albedo_texture.resource_path == record.texture)
		assert(face_material.cull_mode == BaseMaterial3D.CULL_BACK)
		assert(absf(mesh.get_aabb().size.z-1.0) < 0.0001)
		assert(is_equal_approx(mesh.get_aabb().size.x,record.texture_size[0]*manifest.pixel_unit))
		assert(is_equal_approx(mesh.get_aabb().size.y,record.texture_size[1]*manifest.pixel_unit))
		var glb := load(record.glb) as PackedScene
		assert(glb != null)
		var imported := glb.instantiate()
		assert(imported.find_children("*","MeshInstance3D",true,false).size() == 1)
		imported.free()
		var part := load(record.physical_scene).instantiate() as StaticBody3D
		part.position.x = index*20
		root.add_child(part)
		parts.append(part)
		var collision := part.get_node("CollisionShape3D") as CollisionShape3D
		var faces: PackedVector3Array = collision.shape.get_faces()
		triangle_count += faces.size()/3
		assert(faces.size() > 0 and faces.size()%3 == 0)
		for point: Vector3 in faces:
			assert(point.is_finite())
			assert(is_equal_approx(absf(point.z),record.thickness/2.0))
		assert(is_equal_approx(part.get_node("Model/Visual").scale.z,record.thickness))
		var saved_unit_faces: PackedVector3Array = part.unit_collision.get_faces()
		part.thickness = record.thickness*2.0
		await process_frame
		var changed: PackedVector3Array = collision.shape.get_faces()
		for i: int in faces.size():
			assert(changed[i].x == faces[i].x and changed[i].y == faces[i].y)
			assert(is_equal_approx(changed[i].z,faces[i].z*2.0))
		assert(part.unit_collision.get_faces() == saved_unit_faces)
		part.thickness = record.thickness
		part.collision_enabled = false
		await process_frame
		assert(collision.disabled)
		assert(collision.shape == null)
		part.collision_enabled = true
		part.image_scale = Vector2(1.25,0.75)
		part.opacity = 0.65
		await process_frame
		var resized: PackedVector3Array = collision.shape.get_faces()
		for i: int in faces.size():
			assert(resized[i].is_equal_approx(faces[i]*Vector3(1.25,0.75,1.0)))
		assert(is_equal_approx(part.get_node("Model/Visual").transparency,0.35))
		part.image_scale = Vector2.ONE
		part.opacity = 1.0
		await process_frame
		await physics_frame
		# Cast at a real opaque collision triangle, from either side of the volume.
		var centre := (faces[0]+faces[1]+faces[2])/3.0
		centre.z = 0
		var normal := collision.global_basis.z.normalized()
		var world := collision.to_global(centre)
		for direction: float in [-1.0,1.0]:
			var ray := PhysicsRayQueryParameters3D.create(world+normal*direction,world-normal*direction)
			var hit := part.get_world_3d().direct_space_state.intersect_ray(ray)
			assert(not hit.is_empty() and hit.collider == part, record.name+" collision missing")
		var outside := collision.to_global(Vector3(mesh.get_aabb().end.x+0.2,mesh.get_aabb().end.y+0.2,0))
		assert(part.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(outside+normal,outside-normal)).is_empty())
		print("ENVIRONMENT_VALIDATED ",record.name," triangles=",faces.size()/3)
	assert(asset_ids.size() == 23 and "rock" in asset_ids and "demo_rock_large" in asset_ids)
	# Duplicate instances must not share a mutable collision shape.
	var first: Dictionary = manifest.models[0]
	var other := load(first.physical_scene).instantiate() as StaticBody3D
	root.add_child(other)
	parts[0].thickness = first.thickness*3.0
	await process_frame
	assert(is_equal_approx(other.get_node("Model/Visual").scale.z,first.thickness))
	assert(other.get_node("CollisionShape3D").shape != parts[0].get_node("CollisionShape3D").shape)
	other.free()
	# Exercise a real body contact, not just ray queries against the static shape.
	var floor_collision := parts[2].get_node("CollisionShape3D") as CollisionShape3D
	var floor_faces: PackedVector3Array = floor_collision.shape.get_faces()
	var floor_point := (floor_faces[0]+floor_faces[1]+floor_faces[2])/3.0
	floor_point.z = 0
	var ground_point := floor_collision.to_global(floor_point)
	var probe := RigidBody3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.02
	var sphere_collision := CollisionShape3D.new()
	sphere_collision.shape = sphere
	probe.add_child(sphere_collision)
	probe.position = ground_point+Vector3.UP*0.3
	root.add_child(probe)
	for tick: int in 90: await physics_frame
	assert(probe.position.y > ground_point.y and probe.position.y < ground_point.y+0.1, "Ground contact must support a falling rigid body")
	assert(absf(probe.linear_velocity.y) < 0.3)
	probe.free()
	for part: StaticBody3D in parts: part.free()
	var preview := load(BASE+"/Previews/FrontierBattlePartsPreview.tscn").instantiate() as Node3D
	root.add_child(preview)
	assert(preview.get_node("Camera3D") != null)
	var camera := preview.get_node("Camera3D") as Camera3D
	camera.look_at(Vector3.ZERO)
	print("PREVIEW_CAMERA ",camera.global_transform," origin_in_view=",camera.is_position_in_frustum(Vector3.ZERO))
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(1600,1000)
		for frame: int in 6: await process_frame
		RenderingServer.force_draw()
		var picture := root.get_texture().get_image()
		assert(picture != null and not picture.is_empty())
		var background := picture.get_pixel(0,0)
		var visible_samples := 0
		for y: int in range(0,picture.get_height(),8):
			for x: int in range(0,picture.get_width(),8):
				var colour := picture.get_pixel(x,y)
				if absf(colour.r-background.r)+absf(colour.g-background.g)+absf(colour.b-background.b)>0.15: visible_samples += 1
		assert(visible_samples > 100, "Preview must show actual rendered assets")
		assert(picture.save_png("D:/GameJamWorkspace/Reports/DeliveryIntegration_2026-10-16/environment_parts_preview.png") == OK)
	preview.free()
	print("BATTLE_ENVIRONMENT_ASSETS_PASSED models=",manifest.model_count," asset_ids=",asset_ids.size()," collision_triangles=",triangle_count)
	quit()
