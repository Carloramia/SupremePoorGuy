extends RefCounted
## Copies only authored visuals. Source actors never enter the tree, so AI,
## generators, joints and rigid-body physics cannot move the assembly sockets.

static func pose_to(node: Node3D, ancestor: Node) -> Transform3D:
	var pose := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			pose = current.transform * pose
		current = current.get_parent()
	return pose

static func capture(scene: PackedScene) -> Dictionary:
	var actor := scene.instantiate()
	var groups: Dictionary = {}
	var bounds := AABB()
	var first := true
	var all_nodes: Array[Node] = [actor]
	all_nodes.append_array(actor.find_children("*", "", true, false))
	for node: Node in all_nodes:
		if node is PhysicalBodyPart3D:
			var collider := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if collider != null and collider.shape != null:
				collider.shape = collider.shape.duplicate()
			node.prepare_generated_geometry()
	for node: Node in all_nodes:
		if not (node is MeshInstance3D or node is Sprite3D):
			continue
		if node is MeshInstance3D and node.mesh == null:
			continue
		if node is Sprite3D and node.texture == null:
			continue
		var current: Node = node
		var body: PhysicalBodyPart3D
		var shown := true
		while current != null:
			if current is Node3D:
				shown = shown and current.visible
			if body == null and current is PhysicalBodyPart3D:
				body = current
			if current == actor:
				break
			current = current.get_parent()
		if not shown or body == null:
			continue
		var key := str(actor.get_path_to(body))
		if not groups.has(key):
			var wrapper := Node3D.new()
			wrapper.name = str(body.name)
			groups[key] = {"node": wrapper, "pose": pose_to(body, actor), "path": key}
		var copy := node.duplicate(0) as GeometryInstance3D
		for child: Node in copy.get_children():
			copy.remove_child(child)
			child.free()
		copy.set_script(null)
		copy.top_level = false
		copy.layers = 1
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.transform = pose_to(node, body)
		groups[key].node.add_child(copy)
		var visual_bounds: AABB = pose_to(node, actor) * copy.get_aabb()
		bounds = visual_bounds if first else bounds.merge(visual_bounds)
		first = false
	actor.free()
	return {"parts": groups.values(), "bounds": bounds}

static func release(snapshot: Dictionary) -> void:
	for part: Dictionary in snapshot.get("parts", []):
		part.node.free()
