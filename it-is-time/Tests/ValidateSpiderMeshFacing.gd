extends SceneTree

func _initialize() -> void:
	var calibration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Spider/Metadata/generator_calibration.json"))
	for record: Dictionary in calibration.models:
		var mesh := load(record.calibrated_mesh) as ArrayMesh
		var original := load(record.volume_mesh) as ArrayMesh
		assert(mesh.get_surface_count()==3)
		for surface: int in 3:
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var checked := 0
			for i: int in range(0,indices.size(),3):
				var cross := (vertices[indices[i+1]]-vertices[indices[i]]).cross(vertices[indices[i+2]]-vertices[indices[i]])
				if cross.length_squared()<1e-18: continue
				assert(cross.normalized().dot(normals[indices[i]]) < -0.99,record.key+" clockwise outward face/normal "+str(surface))
				checked+=1
			assert(checked>0)
			if surface<2:
				for normal: Vector3 in normals:
					assert(normal.dot(Vector3.BACK if surface==0 else Vector3.FORWARD)>0.9999)
			else:
				var old_indices: PackedInt32Array = original.surface_get_arrays(2)[Mesh.ARRAY_INDEX]
				assert(indices.size()==old_indices.size())
				for i: int in range(0,indices.size(),3):
					assert(indices[i]==old_indices[i] and indices[i+1]==old_indices[i+2] and indices[i+2]==old_indices[i+1],"XY reflection must reverse side winding")
	print("PASS: all ",calibration.models.size()," Spider meshes have outward clockwise front/back/side triangles and consistent normals.")
	quit()
