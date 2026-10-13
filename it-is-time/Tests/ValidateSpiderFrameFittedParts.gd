extends SceneTree

func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Spider/Metadata/frame_fitted_manifest.json"))
	assert(manifest.models.size()==16)
	for record: Dictionary in manifest.models:
		var fitted := load(record.mesh) as ArrayMesh
		for surface: int in 3:
			var arrays := fitted.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i: int in range(0,indices.size(),3):
				var cross := (positions[indices[i+1]]-positions[indices[i]]).cross(positions[indices[i+2]]-positions[indices[i]])
				assert(cross.normalized().dot(normals[indices[i]]) < -0.99,record.key+" outward faces")
			if surface<2:
				var material := fitted.surface_get_material(surface) as StandardMaterial3D
				assert(material.albedo_texture.resource_path==record.texture)
				assert(not material.texture_repeat)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var top_left := Vector2(record.top_left_world[0],record.top_left_world[1])
				var size := Vector2(record.texture_size[0],record.texture_size[1])
				for i: int in vertices.size():
					var reconstructed := uv[i]*size/float(record.pixels_per_unit)
					reconstructed=Vector2(top_left.x+reconstructed.x,top_left.y-reconstructed.y)
					assert(reconstructed.distance_to(Vector2(vertices[i].x,vertices[i].y))<0.00001,record.key+" linear texel scale")
		var old_part: Node3D = load(record.original_scene).instantiate()
		var new_part: Node3D = load(record.scene).instantiate()
		var old_shape: CollisionShape3D = old_part.get_node("CollisionShape3D")
		var new_shape: CollisionShape3D = new_part.get_node("CollisionShape3D")
		assert(old_shape.transform==new_shape.transform)
		assert(var_to_bytes(old_shape.shape.points)==var_to_bytes(new_shape.shape.points))
		for marker: String in ["JointIn","JointOut"]:
			assert(old_part.get_node(marker).transform==new_part.get_node(marker).transform)
		assert(new_part.get_meta("source_png")==record.texture)
		old_part.free()
		new_part.free()
	print("PASS: 16 frame-space textures referenced, uniform linear UV scale, outward faces, unchanged collision/joint markers.")
	quit()
