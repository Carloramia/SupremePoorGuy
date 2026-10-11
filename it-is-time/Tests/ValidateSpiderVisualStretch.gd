extends SceneTree

var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func physics_snapshot(container: Node) -> Array:
	var result: Array = []
	for node: Node in container.find_children("*", "Node3D", true, false):
		result.append([node.get_path(), node.transform])
		if node is RigidBody3D:
			result.append([node.mass, node.gravity_scale, node.linear_velocity, node.angular_velocity, node.collision_layer, node.collision_mask])
		elif node is CollisionShape3D:
			result.append([node.shape, node.shape.size if node.shape is BoxShape3D else null, node.disabled])
		elif node is Generic6DOFJoint3D:
			result.append([node.node_a, node.node_b, node.get_meta(&"generated_joint_frame_a"), node.get_meta(&"generated_joint_frame_b")])
			for axis: String in ["x", "y", "z"]:
				for param: int in Generic6DOFJoint3D.PARAM_MAX: result.append(node.call("get_param_" + axis, param))
				for flag: int in Generic6DOFJoint3D.FLAG_MAX: result.append(node.call("get_flag_" + axis, flag))
	return result

func validate(actor: Node) -> void:
	var parts: Node = actor.get_node("GeneratedParts")
	for body: Node in parts.get_children():
		if body is RigidBody3D: body.freeze = true
	var before := physics_snapshot(parts)
	actor._update_spider_limb_visuals()
	check(actor._spider_stretch_rows.size() == 8, "All eight upper-limb visuals must be bound")
	for row: RefCounted in actor._spider_stretch_rows:
		check(row.active, "Intact limb must have an active visual bridge")
		check(row.visual.mesh == row.source_mesh, "Original MeshInstance mesh must stay unchanged")
		check(row.visual.material_override == null, "Render deformation must not be saved as a node material")
		check(row.visual.custom_aabb == AABB(), "Culling overrides must not be stored on scene nodes")
		check(row.materials[0].shader.get_shader_uniform_list().size() == 11, "Godot must compile all stretch shader parameters")
		check(row.render_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > 4, "Textured faces need cap-boundary vertices")
		var source_uv: PackedVector2Array = row.source_mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var split_uv: PackedVector2Array = row.render_mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		for uv: Vector2 in source_uv:
			var found := false
			for split: Vector2 in split_uv:
				if split.is_equal_approx(uv): found = true
			check(found, "Face texture corners must retain their original UVs")
		# Exercise extension and 3D rotation without advancing the physics solver.
		var tip_original: Transform3D = row.tip_body.transform
		row.tip_body.position += Vector3(0.7, -0.5, 0.2)
		row.update()
		var expected_start: Vector3 = row.root_body.global_transform * row._root_frame.origin + row.upper.global_basis.z.normalized() * row._root_depth
		var expected_end: Vector3 = row.tip_body.global_transform * row._tip_frame.origin + row.upper.global_basis.z.normalized() * row._tip_depth
		check(row.map_part_point(row.source_root).distance_to(expected_start) < 0.0001, "Root hole must follow Torso anchor")
		check(row.map_part_point(row.source_tip).distance_to(expected_end) < 0.0001, "Tip hole must follow Leg anchor")
		var across: Vector3 = row.source_axis.cross(Vector3.BACK).normalized() * 0.04
		for center: Vector3 in [row.source_root, row.source_tip]:
			var offset: Vector3 = across + row.source_axis * row.protected_length * 0.4
			check(is_equal_approx(row.map_part_point(center + offset).distance_to(row.map_part_point(center)), offset.length()), "Both caps must retain their size during extension")
		check(row.materials[0].get_shader_parameter(&"target_frame") == row.target_frame, "Shader must receive the tested visual frame")
		row.tip_body.transform = tip_original
		row.update()
		check(row.geometry_is_current(), "Ordinary physics motion must not trigger mesh rebuilding")
		var broken_before: bool = row.tip_body.is_broken
		row.tip_body.is_broken = true
		row.update()
		check(not row.active, "Broken connected body must restore the original mesh")
		row.tip_body.is_broken = broken_before
		row.update()
		var old_b: NodePath = row.tip_joint.node_b
		row.tip_joint.node_b = NodePath("")
		row.update()
		check(not row.active, "Disconnected joints must not leave a visual bridge")
		row.tip_joint.node_b = old_b
		row.update()
	check(physics_snapshot(parts) == before, "Visual updates must preserve every body/collider/joint property")
	var cached_mesh: Mesh = actor._spider_stretch_rows[0].render_mesh
	actor.spider_limb_visual_stretch_enabled = false
	actor._update_spider_limb_visuals()
	check(actor._spider_stretch_rows.is_empty(), "Switching off must remove all render overrides")
	check(physics_snapshot(parts) == before, "Disabling the visuals must not change physics")
	actor.spider_limb_visual_stretch_enabled = true
	actor._update_spider_limb_visuals()
	check(actor._spider_stretch_rows[0].render_mesh == cached_mesh, "Repeated setup must reuse the cached split mesh")
	check(physics_snapshot(parts) == before, "Re-enabling must preserve physics")

func run() -> void:
	for name: String in ["Generate_Spider", "Generate_Spider_NPC"]:
		var actor: Node = load("res://Scenes/Creatures/Characters/" + name + ".tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		validate(actor)
		check(actor.generate_creature(), "Spider must regenerate with render-only deformation")
		validate(actor)
		actor.free()
	if not failed: print("PASS: Spider/NPC eight visual bridges, fixed-size caps, original UVs, toggle, regeneration, broken/disconnected cleanup and unchanged body/collider/joint settings.")
	quit(1 if failed else 0)
