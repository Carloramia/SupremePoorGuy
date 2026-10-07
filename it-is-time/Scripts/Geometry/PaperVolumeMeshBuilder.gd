@tool
extends RefCounted

## Bake a unit-depth volume once. Runtime changes scale only Z and update the side material.
## Pixel boundary runs include concavities and interior holes, unlike a convex collision hull.
static func build(source: Mesh, material: StandardMaterial3D) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() != 4 or uvs.size() != 4 or material == null or material.albedo_texture == null: return null
	var image := material.albedo_texture.get_image()
	if image == null: return null
	if image.is_compressed() and image.decompress() != OK: return null
	var uv_basis := Transform2D(uvs[1]-uvs[0],uvs[2]-uvs[0],uvs[0])
	if is_zero_approx(uv_basis.determinant()): return null
	var mapping := Transform2D(Vector2(vertices[1].x-vertices[0].x,vertices[1].y-vertices[0].y),Vector2(vertices[2].x-vertices[0].x,vertices[2].y-vertices[0].y),Vector2(vertices[0].x,vertices[0].y)) * uv_basis.affine_inverse()
	var result := ArrayMesh.new()
	for front: bool in [true,false]:
		var face_vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		for vertex: Vector3 in vertices:
			face_vertices.append(Vector3(vertex.x,vertex.y,0.5 if front else -0.5))
			normals.append(Vector3.BACK if front else Vector3.FORWARD)
		var face_indices := indices.duplicate()
		if not front:
			for index: int in range(0,face_indices.size(),3):
				var swap := face_indices[index+1]
				face_indices[index+1] = face_indices[index+2]
				face_indices[index+2] = swap
		var face_arrays: Array = []
		face_arrays.resize(Mesh.ARRAY_MAX)
		face_arrays[Mesh.ARRAY_VERTEX] = face_vertices
		face_arrays[Mesh.ARRAY_NORMAL] = normals
		face_arrays[Mesh.ARRAY_TEX_UV] = uvs
		face_arrays[Mesh.ARRAY_INDEX] = face_indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,face_arrays)
		var face_material := material.duplicate() as StandardMaterial3D
		face_material.cull_mode = BaseMaterial3D.CULL_BACK
		result.surface_set_material(result.get_surface_count()-1,face_material)
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image,material.alpha_scissor_threshold)
	var size := Vector2i(image.get_width(),image.get_height())
	var sides := {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"indices":PackedInt32Array()}
	# Merge straight pixel edges into runs to keep the baked mesh small.
	for row: int in size.y:
		for top: bool in [true,false]:
			var start := -1
			for x: int in range(size.x+1):
				var neighbor_y := row-1 if top else row+1
				var edge := x < size.x and bitmap.get_bit(x,row) and (neighbor_y < 0 or neighbor_y >= size.y or not bitmap.get_bit(x,neighbor_y))
				if edge and start < 0: start = x
				if not edge and start >= 0:
					var y := row if top else row+1
					_add_side(sides,mapping,Vector2(start,y)/Vector2(size),Vector2(x,y)/Vector2(size),Vector2(0,-1 if top else 1))
					start = -1
	for col: int in size.x:
		for left: bool in [true,false]:
			var start := -1
			for y: int in range(size.y+1):
				var neighbor_x := col-1 if left else col+1
				var edge := y < size.y and bitmap.get_bit(col,y) and (neighbor_x < 0 or neighbor_x >= size.x or not bitmap.get_bit(neighbor_x,y))
				if edge and start < 0: start = y
				if not edge and start >= 0:
					var x := col if left else col+1
					_add_side(sides,mapping,Vector2(x,start)/Vector2(size),Vector2(x,y)/Vector2(size),Vector2(-1 if left else 1,0))
					start = -1
	if sides.vertices.is_empty(): return null
	var side_arrays: Array = []
	side_arrays.resize(Mesh.ARRAY_MAX)
	side_arrays[Mesh.ARRAY_VERTEX] = sides.vertices
	side_arrays[Mesh.ARRAY_NORMAL] = sides.normals
	side_arrays[Mesh.ARRAY_INDEX] = sides.indices
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,side_arrays)
	var side_material := StandardMaterial3D.new()
	side_material.albedo_color = Color(0.65,0.65,0.65)
	side_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.surface_set_material(2,side_material)
	return result

static func _add_side(sides: Dictionary,mapping: Transform2D,a: Vector2,b: Vector2,outward: Vector2) -> void:
	var p := mapping * a
	var q := mapping * b
	var n := mapping.basis_xform(outward).normalized()
	var normal := Vector3(n.x,n.y,0)
	var offset: int = sides.vertices.size()
	sides.vertices.append_array(PackedVector3Array([Vector3(p.x,p.y,0.5),Vector3(q.x,q.y,0.5),Vector3(q.x,q.y,-0.5),Vector3(p.x,p.y,-0.5)]))
	for index: int in 4: sides.normals.append(normal)
	var edge := Vector3(q.x-p.x,q.y-p.y,0)
	var order := [0,2,1,0,3,2] if edge.cross(Vector3(0,0,-1)).dot(normal) > 0 else [0,1,2,0,2,3]
	for index: int in order: sides.indices.append(offset+index)
