extends SceneTree

const ALIGN = preload("res://Scripts/Creatures/SpiderLimbHoleAlignment.gd")
var failed := false
var assets: Dictionary = {}

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

# Read the textured face independently of the connector markers.
func texture_hole(body: Node3D, source_y: float) -> Vector3:
	var visual := body.get_node("Model/PaperVolume") as MeshInstance3D
	var info: Dictionary = assets[visual.mesh.resource_path]
	var uv := Vector2(-float(info.top_left_world[0]), float(info.top_left_world[1]) - source_y) * float(info.pixels_per_unit)
	uv /= Vector2(info.texture_size[0], info.texture_size[1])
	var arrays := visual.mesh.surface_get_arrays(0)
	var coords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i: int in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var v := coords[b] - coords[a]
		var w := coords[c] - coords[a]
		if absf(v.cross(w)) < 0.00000001: continue
		var u := (uv - coords[a]).cross(w) / v.cross(w)
		var t := v.cross(uv - coords[a]) / v.cross(w)
		if u >= -0.0001 and t >= -0.0001 and u + t <= 1.0001:
			return visual.global_transform * (points[a] + (points[b] - points[a]) * u + (points[c] - points[a]) * t)
	check(false, "Texture hole must be inside the source face")
	return Vector3.ZERO

func snapshot(parts: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for body: Node in parts.get_children():
		if not body is PhysicalBodyPart3D: continue
		var collision := body.get_node("CollisionShape3D") as CollisionShape3D
		result[str(body.name)] = [body.transform, collision.transform, collision.shape, collision.shape.size, body.mass, body.collision_layer, body.collision_mask]
	return result

func validate(actor: Node) -> void:
	var parts := actor.get_node("GeneratedParts") as Node3D
	check(not actor.spider_limb_visual_stretch_enabled, "Default visuals must keep their original aspect ratio without dynamic stretching")
	var before := snapshot(parts)
	var poses: Dictionary = {}
	for index: int in range(1, 9):
		var upper := parts.get_node("Leg_%d_Limb_1" % index) as PhysicalBodyPart3D
		var foot := parts.get_node("Leg_%d" % index) as PhysicalBodyPart3D
		var model := upper.get_node("Model") as Node3D
		check(is_equal_approx(model.scale.x, model.scale.y), "Source X/Y ratio must survive: " + str(upper.name))
		var upper_hole := upper.get_node("JointIn") as Node3D
		var foot_hole := foot.get_node("JointIn") as Node3D
		var normal := upper.global_basis.z.normalized()
		check((texture_hole(upper, 1.0) - upper_hole.global_position).slide(normal).length() < 0.0001, "Upper marker must match the actual texture hole")
		check((texture_hole(upper, -1.0) - upper.get_node("JointOut").global_position).slide(normal).length() < 0.0001, "Root marker must match the actual texture hole")
		check((texture_hole(foot, 1.4) - foot_hole.global_position).slide(normal).length() < 0.0001, "Lower marker must match the actual texture hole")
		check((upper_hole.global_position - foot_hole.global_position).slide(normal).length() < 0.0001, "Upper/lower texture holes must coincide in their sheet plane")
		poses[str(upper.name)] = [model.transform, upper_hole.transform, upper.get_node("JointOut").transform]
	for joint: Generic6DOFJoint3D in parts.get_node("Joints").get_children():
		if not joint.get_meta(&"spider_hole_aligned", false): continue
		for body: Node3D in [joint.get_node(joint.node_a), joint.get_node(joint.node_b)]:
			var hole := body.get_node("JointIn") as Node3D
			check((joint.global_position - hole.global_position).slide(body.global_basis.z.normalized()).length() < 0.0001, "Physical pivot must pass through the texture hole")
		for axis: String in ["x", "y", "z"]:
			check(joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "Knee translation must be locked")
			check(is_zero_approx(joint.call("get_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)), "Knee translation must have zero travel")
		check(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) > joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT), "Z hinge must still bend")
	check(ALIGN.align(parts) == 8, "All eight chains must remain recognizable after alignment")
	check(snapshot(parts) == before, "Hole alignment must preserve rigid bodies and collision geometry")
	for key: String in poses:
		var upper := parts.get_node(key)
		var after: Array = [upper.get_node("Model").transform, upper.get_node("JointIn").transform, upper.get_node("JointOut").transform]
		for i: int in 3: check(poses[key][i].is_equal_approx(after[i]), "Repeated alignment must not accumulate scale or rotation")
	actor._update_spider_limb_visuals()
	check(actor._spider_stretch_rows.is_empty(), "Default rendering must not move or stretch the sheet away from its physical root")
	check(snapshot(parts) == before, "Rendering must not write body or collision properties")

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Spider/Metadata/frame_fitted_manifest.json"))
	for row: Dictionary in manifest.models: assets[row.mesh] = row
	for suffix: String in ["", "_NPC"]:
		var actor: Node = load("res://Scenes/Creatures/Characters/Generate_Spider" + suffix + ".tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		validate(actor)
		for generation: int in 2:
			check(actor.generate_creature(), "Spider must regenerate aligned limbs")
			validate(actor)
		actor.get_node("SpiderGenerator").overall_scale = 2.0
		check(actor.generate_creature(), "Scaled Spider must regenerate")
		validate(actor)
		actor.free()
	if not failed: print("PASS: Spider/NPC original visual ratios, texture holes and knee pivots aligned, locked knee translation, repeatable regeneration/scaling, unchanged bodies and colliders.")
	quit(1 if failed else 0)
