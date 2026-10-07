extends SceneTree
const BUILDER = preload("res://Scripts/Geometry/PaperVolumeMeshBuilder.gd")

func _initialize() -> void: call_deferred("run")

func depth(shape: ConvexPolygonShape3D) -> float:
	var low := INF
	var high := -INF
	for point: Vector3 in shape.points:
		low = minf(low,point.z)
		high = maxf(high,point.z)
	return high-low

func run() -> void:
	# A square with a hole must have four outer walls and four inner walls.
	var image := Image.create(8,8,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in range(1,7):
		for x: int in range(1,7):
			if x not in [3,4] or y not in [3,4]: image.set_pixel(x,y,Color.WHITE)
	var quad := QuadMesh.new()
	quad.size = Vector2(8,8)
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var volume := BUILDER.build(quad,material)
	assert(volume != null and volume.get_surface_count() == 3)
	assert(volume.surface_get_array_len(2) == 32,"The hole must have its own side walls")
	var front := volume.surface_get_arrays(0)
	var back := volume.surface_get_arrays(1)
	assert(front[Mesh.ARRAY_TEX_UV] == back[Mesh.ARRAY_TEX_UV],"Matching UVs must naturally mirror the rear view")
	assert(volume.surface_get_material(0).albedo_texture == volume.surface_get_material(1).albedo_texture)
	for surface: int in volume.get_surface_count():
		var arrays := volume.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index: int in range(0,indices.size(),3):
			var a := indices[index]
			var b := indices[index+1]
			var c := indices[index+2]
			assert((vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).dot(normals[a]) < 0,"Godot faces must use clockwise winding")
	var count := 0
	var dir := "res://Scenes/Creatures/Bodyparts/PaperParts/ToSplit_1"
	for group: String in ["Base","LeftLeg","RightLeg"]:
		for file: String in DirAccess.get_files_at(dir.path_join(group)):
			if not file.ends_with(".tscn"): continue
			var scene := load(dir.path_join(group).path_join(file)) as PackedScene
			var part := scene.instantiate() as PhysicalBodyPart3D
			part.freeze = true
			root.add_child(part)
			var model := part.get_node("Model") as Node3D
			var mesh := model.get_node("PaperVolume") as MeshInstance3D
			var collision := part.get_node("CollisionShape3D") as CollisionShape3D
			var shape := collision.shape as ConvexPolygonShape3D
			assert(part.paper_volume_enabled and mesh.visible and is_equal_approx(depth(shape),0.08))
			assert(mesh.mesh.get_surface_count() == 3 and mesh.mesh.surface_get_array_len(2) > 0)
			var front_material := mesh.mesh.surface_get_material(0) as StandardMaterial3D
			var back_material := mesh.mesh.surface_get_material(1) as StandardMaterial3D
			assert(front_material.albedo_texture != null and front_material.albedo_texture == back_material.albedo_texture)
			assert(mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] == mesh.mesh.surface_get_arrays(1)[Mesh.ARRAY_TEX_UV])
			for surface: int in [0,1]:
				var face_arrays := mesh.mesh.surface_get_arrays(surface)
				var face_points: PackedVector3Array = face_arrays[Mesh.ARRAY_VERTEX]
				var face_indices: PackedInt32Array = face_arrays[Mesh.ARRAY_INDEX]
				var face_normal := Vector3.BACK if surface == 0 else Vector3.FORWARD
				assert((face_points[face_indices[1]]-face_points[face_indices[0]]).cross(face_points[face_indices[2]]-face_points[face_indices[0]]).dot(face_normal) < 0)
			var source_meshes := model.find_children("*","MeshInstance3D",true,false)
			for node: MeshInstance3D in source_meshes:
				if node != mesh: assert(not node.visible,"The original plane must not overlap the volume")
			var before_model := model.transform
			var before_joint: Transform3D = part.get_node("JointOut").transform
			var points := shape.points
			part.paper_volume_thickness = 0.25
			part.paper_side_color = Color.RED
			assert(is_equal_approx(mesh.scale.z,0.25) and is_equal_approx(depth(shape),0.25))
			assert(mesh.get_surface_override_material(2).albedo_color == Color.RED)
			assert(model.transform == before_model and part.get_node("JointOut").transform == before_joint)
			for index: int in points.size():
				assert(Vector2(points[index].x,points[index].y).is_equal_approx(Vector2(shape.points[index].x,shape.points[index].y)))
			part.paper_volume_enabled = false
			assert(not mesh.visible and is_equal_approx(depth(shape),0.02))
			for node: MeshInstance3D in source_meshes:
				if node != mesh: assert(node.visible)
			part.paper_volume_enabled = true
			part.mesh_visible = false
			assert(not model.visible)
			part.mesh_visible = true
			assert(model.visible)
			var second := scene.instantiate() as PhysicalBodyPart3D
			second.freeze = true
			# Simulate an editor save whose collision points already contain volume depth.
			var stored_shape := second.get_node("CollisionShape3D").shape as ConvexPolygonShape3D
			var stored_points := stored_shape.points
			for index: int in stored_points.size(): stored_points[index].z *= 4.0
			stored_shape.points = stored_points
			root.add_child(second)
			assert(is_equal_approx(depth(second.get_node("CollisionShape3D").shape),0.08))
			assert(second.get_node("Model/PaperVolume").get_surface_override_material(2).albedo_color != Color.RED)
			second.paper_volume_enabled = false
			assert(is_equal_approx(depth(stored_shape),0.02),"Reloading an expanded shape must not lose the flat collision depth")
			second.free()
			part.free()
			count += 1
	assert(count == 27)
	print("PAPER_VOLUMES_VALIDATION_PASSED count=",count)
	quit()
