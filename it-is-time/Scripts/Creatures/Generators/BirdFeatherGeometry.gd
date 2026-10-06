@tool
extends RefCounted
## A tapered feather prism in local XY, rooted at the origin and pointing along +Y.
static func create_mesh(size: Vector3) -> ArrayMesh:
	var outline := PackedVector2Array([
		Vector2(0,0), Vector2(-0.35,0.18), Vector2(-0.5,0.5), Vector2(-0.25,0.85),
		Vector2(0,1), Vector2(0.25,0.85), Vector2(0.5,0.5), Vector2(0.35,0.18)])
	var vertices := PackedVector3Array()
	for depth: float in [-size.z*0.5, size.z*0.5]:
		for point: Vector2 in outline: vertices.append(Vector3(point.x*size.x,point.y*size.y,depth))
	var indices := PackedInt32Array()
	for index: int in range(1,7):
		indices.append_array(PackedInt32Array([0,index,index+1,8,8+index+1,8+index]))
	for index: int in range(8):
		var next := (index+1)%8
		indices.append_array(PackedInt32Array([index,8+index,8+next,index,8+next,next]))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in indices: surface.add_vertex(vertices[index])
	surface.generate_normals()
	return surface.commit()

static func add_feathers(parent: Node3D, layouts: Array, scene_owner: Node = null, preview_material: Material = null) -> void:
	if layouts.is_empty(): return
	var container := Node3D.new()
	container.name = "Feathers"
	container.set_meta(&"generated_feathers", true)
	parent.add_child(container)
	if scene_owner != null: container.owner = scene_owner
	var material: Material = preview_material
	if material == null:
		var solid := StandardMaterial3D.new()
		solid.albedo_color = layouts[0].get("color", Color(0.9,0.92,0.96))
		solid.roughness = 0.9
		material = solid
	# All feathers on one block have the same dimensions, so they share mesh and material.
	var mesh := create_mesh(layouts[0].size)
	for index: int in range(layouts.size()):
		var instance := MeshInstance3D.new()
		instance.name = "Feather_%03d" % (index+1)
		instance.mesh = mesh
		instance.material_override = material
		instance.transform = layouts[index].transform
		container.add_child(instance)
		if scene_owner != null: instance.owner = scene_owner
