@tool
extends RefCounted

const VERSION := 1
const LENGTH_PROPERTIES := [&"left_distance", &"right_distance", &"top_distance", &"bottom_distance", &"collision_thickness"]
const PROPERTIES := [&"geometry_mode", &"custom_model_path", &"paper_volume_enabled", &"paper_volume_thickness", &"sprite_visible", &"mesh_visible", &"paper_side_color", &"visual_states", &"initial_visual_state", &"visual_state_mesh_path"]

static func relative_transform(node: Node3D, body: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != body:
		if parent is Node3D: result = parent.transform * result
		parent = parent.get_parent()
	return result

static func scaled_shape(source: Shape3D, factor: float) -> Shape3D:
	if source == null: return null
	var shape := source.duplicate(true) as Shape3D
	shape.resource_local_to_scene = true
	if shape is BoxShape3D: shape.size *= factor
	elif shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = shape.points
		for i: int in range(points.size()): points[i] *= factor
		shape.points = points
	elif shape is SphereShape3D: shape.radius *= factor
	elif shape is CapsuleShape3D or shape is CylinderShape3D:
		shape.radius *= factor
		shape.height *= factor
	else: return null
	return shape

static func capture(body: Node3D, multiplier: float, source_scene: String) -> Dictionary:
	var snapshot := {"version":VERSION, "source_scene":source_scene, "nodes":[], "properties":{}}
	for key: StringName in PROPERTIES: snapshot.properties[key] = body.get(key)
	for key: StringName in LENGTH_PROPERTIES: snapshot.properties[key] = float(body.get(key))/multiplier
	for child: Node in body.find_children("*", "Node3D", true, false):
		if child.has_meta(&"generated_connection_port"): continue
		var ancestor := child
		var module_payload := false
		while ancestor != body:
			if ancestor.has_meta(&"generated_module_root"): module_payload = true; break
			ancestor = ancestor.get_parent()
		if module_payload: continue
		var pose := relative_transform(child, body)
		if not pose.is_finite() or pose.basis.determinant() == 0.0:
			push_warning("[manual_layout] Invalid internal transform at %s/%s; previous layout retained." % [body.name,body.get_path_to(child)])
			return {}
		pose.origin /= multiplier
		var entry := {"path":body.get_path_to(child), "class":child.get_class(), "transform":pose}
		if child is CollisionShape3D:
			entry["shape"] = scaled_shape(child.shape, 1.0/multiplier)
			if child.shape != null and entry.shape == null:
				push_warning("[manual_layout] Unsupported collision shape at " + str(entry.path) + "; previous layout retained.")
				return {}
			entry["disabled"] = child.disabled
		else:
			pose.basis = pose.basis.scaled(Vector3.ONE/multiplier)
			entry.transform = pose
		# Reference standalone assets; serializing imported meshes can embed their full textures.
		if child is MeshInstance3D and child.mesh != null:
			var mesh_path: String = child.mesh.resource_path
			if mesh_path.begins_with("res://") and not mesh_path.contains("::"): entry["mesh_path"] = mesh_path
			# Small procedural meshes (e.g. feathers) have no source asset to restore from.
			elif mesh_path.is_empty():
				entry["mesh"] = child.mesh
				entry["material_override"] = child.material_override
		if child is VisualInstance3D: entry["visible"] = child.visible
		snapshot.nodes.append(entry)
	return snapshot

static func apply_to(body: Node3D, snapshot: Dictionary, multiplier: float, source_scene: String) -> bool:
	if int(snapshot.get("version",0)) != VERSION or str(snapshot.get("source_scene","")) != source_scene:
		push_warning("[manual_layout] Part source/version changed for %s; internal snapshot skipped." % body.name)
		return false
	# Validate before touching the new Part; changing the source scene keeps normal generation usable.
	for entry: Dictionary in snapshot.nodes:
		var node := body.get_node_or_null(entry.path)
		if node == null or node.get_class() != entry.class:
			push_warning("[manual_layout] Missing/changed node %s/%s; internal snapshot skipped." % [body.name,entry.path])
			return false
		if entry.has("mesh_path") and not ResourceLoader.exists(entry.mesh_path):
			push_warning("[manual_layout] Missing mesh for %s; internal snapshot skipped." % body.name)
			return false
	for key: StringName in snapshot.properties:
		var value: Variant = snapshot.properties[key]
		body.set(key, float(value)*multiplier if key in LENGTH_PROPERTIES else value)
	for entry: Dictionary in snapshot.nodes:
		var node := body.get_node(entry.path)
		if node is MeshInstance3D and entry.has("mesh_path"): node.mesh = load(entry.mesh_path)
		elif node is MeshInstance3D and entry.has("mesh"):
			node.mesh = entry.mesh
			node.material_override = entry.get("material_override")
		if entry.has("visible"): node.visible = entry.visible
	body.prepare_generated_geometry()
	var targets := {}
	for entry: Dictionary in snapshot.nodes:
		var node := body.get_node(entry.path) as Node3D
		var pose: Transform3D = entry.transform
		pose.origin *= multiplier
		if node is CollisionShape3D:
			node.shape = scaled_shape(entry.shape,multiplier)
			node.disabled = entry.disabled
		else: pose.basis = pose.basis.scaled(Vector3.ONE*multiplier)
		targets[node] = pose
	# Root-relative transforms avoid multiplying Overall Scale at every nested node.
	_restore_transforms(body, targets)
	# Prime geometry caches before entering the tree, then restore authored offsets.
	body.prepare_generated_geometry()
	_restore_transforms(body, targets)
	return true

static func _restore_transforms(body: Node3D, targets: Dictionary) -> void:
	for node: Node3D in targets:
		var parent := node.get_parent()
		while not parent is Node3D: parent = parent.get_parent()
		var parent_pose := Transform3D.IDENTITY if parent == body else relative_transform(parent,body)
		node.transform = parent_pose.affine_inverse()*Transform3D(targets[node])
