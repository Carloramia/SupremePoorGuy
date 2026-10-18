@tool
extends RefCounted

const CHARACTER = preload("res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd")
const RULE = preload("res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const SNAPSHOT = preload("res://Scripts/Creatures/Generators/ManualPartSnapshot.gd")

static func context(body: PhysicalBodyPart3D) -> Dictionary:
	if not is_instance_valid(body) or not body.is_inside_tree() or not body.has_meta(&"generated_role"): return {}
	# Module snapshots are separate from the generator's base PartSceneRules.
	if body.has_meta(&"generated_module_id"): return {}
	var container := body.get_parent()
	var actor := container.get_parent() as CHARACTER
	if actor == null or container.name != &"GeneratedParts": return {}
	var generator := actor.get_node_or_null(actor.generator_path)
	if generator == null: return {}
	var key := str(body.get_meta(&"generated_part_key", str(body.name)))
	var type := str(body.get_meta(&"generated_part_type", body.get_meta(&"generated_role", "")))
	var rule: RULE = generator.get_part_scene_rule(type, str(body.name), key)
	# Some generators bake the source multiplier into their frame and return a normalized fit rule.
	for authored: RULE in generator.part_scene_rules:
		if authored != null and authored.part_key == key:
			rule = authored
			break
	var scene: PackedScene = CHARACTER.PART_SCENE if rule == null else rule.part_scene
	return {"actor":actor, "generator":generator, "key":key, "type":type, "rule":rule,
		"scene":scene, "multiplier":1.0 if rule == null else rule.size_multiplier}

static func prepare(body: PhysicalBodyPart3D, scene: PackedScene, multiplier: float) -> Dictionary:
	if not Engine.is_editor_hint(): return {"error":"只能在编辑器中修改生成部件。"}
	var current := context(body)
	if current.is_empty(): return {"error":"请选择 GeneratedParts 下的物理部件。"}
	if scene == null or not scene.resource_path.begins_with("res://") or not ResourceLoader.exists(scene.resource_path):
		return {"error":"请指定已保存的物理部件场景（.tscn）。"}
	if not is_finite(multiplier) or multiplier < 0.01 or not is_finite(float(current.multiplier)) or float(current.multiplier) <= 0.0:
		return {"error":"尺寸倍率必须是大于等于 0.01 的有限数值。"}
	var actor: CHARACTER = current.actor
	var generator: Node = current.generator
	var layout: Resource = actor.build_manual_layout(true)
	if layout == null: return {"error":"无法保存当前布局；请检查关节两端是否有效、部件是否完好且根节点保持单位缩放。"}
	var original_size := GEOMETRY.bounds(body).size
	var factor := multiplier / float(current.multiplier)
	var same_scene := scene.resource_path == str(body.get_meta(&"generated_scene_path", body.scene_file_path))
	var instance: Node = body.duplicate() if same_scene else scene.instantiate()
	var candidate := instance as PhysicalBodyPart3D
	if candidate == null:
		if instance != null: instance.free()
		return {"error":"引用场景的根节点必须继承 _PhysicalSampleBodyParts。"}
	if not candidate.scale.is_equal_approx(Vector3.ONE):
		candidate.free()
		return {"error":"物理部件场景的刚体根节点必须保持 (1, 1, 1) 缩放。"}
	# Geometry preparation may update paper collision points; never share them with the source/undo node.
	for collider: CollisionShape3D in candidate.find_children("*", "CollisionShape3D", true, false):
		if collider.shape != null: collider.shape = collider.shape.duplicate(true)
	candidate.name = body.name
	var selected: Dictionary
	for part: Dictionary in layout.blueprint.parts:
		if str(part.part_key) == current.key: selected = part; break
	if selected.is_empty():
		candidate.free()
		return {"error":"保存布局中未找到选中部件。"}
	if same_scene:
		var snapshot := SNAPSHOT.capture(body, 1.0, scene.resource_path)
		if not _scale_snapshot(snapshot, factor, body.paper_volume_enabled) or not SNAPSHOT.apply_to(candidate, snapshot, 1.0, scene.resource_path):
			candidate.free()
			return {"error":"部件几何不支持此次缩放；原布局已保留。"}
	else:
		# Fit the replacement to the current envelope, uniformly, then apply the requested size change.
		var fit_rule := RULE.new()
		fit_rule.size_mode = RULE.SizeMode.FIT_UNIFORM
		fit_rule.size_multiplier = factor
		if GEOMETRY.fit(candidate, original_size, fit_rule, str(selected.role), float(generator.part_width)*float(generator.overall_scale)).size == Vector3.ZERO:
			candidate.free()
			return {"error":"物理部件需要有效的 Box/Convex 碰撞形状和模型。"}
		actor._prepare_generated_part(candidate, selected, {"overall_scale":float(generator.overall_scale)})
		candidate.tags = body.tags.duplicate()
		candidate.arm_swing_bindings = body.arm_swing_bindings.duplicate(true)
		for node: Node in body.get_children():
			if node.has_meta(&"generated_connection_port"): candidate.add_child(node.duplicate())
	candidate.transform = body.transform
	candidate.freeze = true
	for key: StringName in body.get_meta_list(): candidate.set_meta(key, body.get_meta(key))
	candidate.set_meta(&"generated_scene_path", scene.resource_path)
	var bounds := GEOMETRY.bounds(candidate)
	if not bounds.size.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		candidate.free()
		return {"error":"修改后尺寸无效；原布局已保留。"}
	selected.internal_snapshot = SNAPSHOT.capture(candidate, float(generator.overall_scale), scene.resource_path)
	if selected.internal_snapshot.is_empty():
		candidate.free()
		return {"error":"修改后部件快照保存失败；原布局已保留。"}
	selected.size = bounds.size / float(generator.overall_scale)
	selected["part_editor_override"] = true
	candidate.set_meta(&"generated_part_key", current.key)
	candidate.set_meta(&"generated_size", bounds.size)
	candidate.set_meta(&"generated_framework_size", bounds.size)
	var saved: Dictionary = selected.duplicate(true)
	candidate.set_meta(&"generated_layout", saved)
	var density := float(body.get_meta(&"generated_density", actor.mass_density))
	var minimum: float = actor.minimum_feather_mass if str(selected.role) == "Feather" else actor.minimum_part_mass
	var mass := bounds.size.x * bounds.size.y * bounds.size.z * density
	candidate.mass = clampf(mass, minimum, actor.maximum_part_mass) if actor.mass_limits_enabled else mass
	var rule: RULE = RULE.new() if current.rule == null else current.rule.duplicate()
	rule.part_key = current.key
	rule.part_name = str(body.name)
	rule.part_type = current.type
	rule.part_scene = scene
	rule.size_multiplier = multiplier
	var rules: Array[RULE] = [rule]
	for existing: RULE in generator.part_scene_rules:
		if existing == null or existing.part_key != current.key: rules.append(existing)
	var before := {"part":body, "other":candidate, "name":str(body.name), "index":body.get_index(),
		"rules":generator.part_scene_rules, "layout":generator.manual_layout, "use_manual":generator.use_manual_layout,
		"owners":_owners(body, actor._scene_owner()), "joint_anchors":_joint_anchors(body.get_parent(), false)}
	var after := {"part":candidate, "other":body, "name":str(body.name), "index":body.get_index(),
		"rules":rules, "layout":layout, "use_manual":true, "owners":_owners(candidate, actor._scene_owner()),
		"joint_anchors":_joint_anchors(body.get_parent(), true)}
	return {"actor":actor, "before":before, "after":after}

static func _joint_anchors(container: Node, use_live: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in container.get_node("Joints").get_children():
		var joint := node as Joint3D
		if joint == null or joint.has_meta(&"segment_rotation_constraint"): continue
		var entry := {"path":container.get_path_to(joint), "frames":{}, "ports":[]}
		for endpoint: String in ["a", "b"]:
			var body := joint.get_node(joint.get("node_" + endpoint)) as Node3D
			var key := StringName("generated_joint_frame_" + endpoint)
			if use_live: entry.frames[key] = body.global_transform.affine_inverse() * joint.global_transform
			elif joint.has_meta(key): entry.frames[key] = joint.get_meta(key)
			for child: Node in body.get_children():
				if child is Marker3D and child.get_meta(&"joint_name", "") == str(joint.name):
					entry.ports.append({"path":container.get_path_to(child),
						"position":body.to_local(joint.global_position) if use_live else child.position})
		result.append(entry)
	return result

static func _owners(part: Node, fallback: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = [{"path":NodePath("."), "owner":fallback if part.owner == null else part.owner}]
	for node: Node in part.find_children("*", "", true, false):
		result.append({"path":part.get_path_to(node), "owner":fallback if node.owner == null else node.owner})
	return result

static func _scale_snapshot(snapshot: Dictionary, factor: float, paper: bool) -> bool:
	if snapshot.is_empty(): return false
	var ratio := Vector3(factor, factor, 1.0 if paper else factor)
	var scale_basis := Basis.from_scale(ratio)
	for key: StringName in SNAPSHOT.LENGTH_PROPERTIES:
		if key != &"collision_thickness" or not paper: snapshot.properties[key] *= factor
	for entry: Dictionary in snapshot.nodes:
		var pose: Transform3D = entry.transform
		if entry.has("shape"):
			var shape: Shape3D = entry.shape
			var points := PackedVector3Array()
			if shape is ConvexPolygonShape3D: points = shape.points
			elif shape is BoxShape3D:
				var half: Vector3 = shape.size * 0.5
				for x: float in [-half.x, half.x]:
					for y: float in [-half.y, half.y]:
						for z: float in [-half.z, half.z]: points.append(Vector3(x,y,z))
			else: return false
			for index: int in points.size(): points[index] = scale_basis * (pose * points[index])
			var replacement := ConvexPolygonShape3D.new()
			replacement.resource_local_to_scene = true
			replacement.points = points
			entry.shape = replacement
			entry.transform = Transform3D.IDENTITY
		else:
			# Box sprites get their vertex extents from the scaled edge parameters in the shader.
			var box_sprite: bool = int(snapshot.properties.geometry_mode) == PhysicalBodyPart3D.GeometryMode.BOX_FIT and entry.class == "Sprite3D"
			entry.transform = Transform3D(pose.basis if box_sprite else scale_basis * pose.basis, scale_basis * pose.origin)
	return true
