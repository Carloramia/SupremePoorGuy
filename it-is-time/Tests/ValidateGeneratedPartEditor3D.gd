@tool
extends SceneTree

const EDIT = preload("res://addons/creature_part_editor/part_edit.gd")
const PANEL = preload("res://addons/creature_part_editor/panel.gd")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	check(Engine.is_editor_hint(), "Run with --editor")
	test_moved_body_anchors()
	for species: String in ["Human", "Wolf", "Spider", "Snake", "Bird", "Beast"]:
		var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_%s.tscn" % species).instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		# Work on the saved layout, including authored collision/model offsets.
		if not actor.has_node("GeneratedParts"): check(actor.generate_creature(), "Initial assembly: " + species)
		var parts: Node = actor.get_node("GeneratedParts")
		var body: PhysicalBodyPart3D
		for node: Node in parts.get_children():
			if node is PhysicalBodyPart3D and str(node.get_meta("generated_role", "")) == "Head": body = node; break
		check(body != null, "Head exists: " + species)
		if body == null: actor.free(); continue
		var current := EDIT.context(body)
		check(not current.is_empty(), "Generated part context: " + species)
		if current.is_empty(): actor.free(); continue
		var generator: Node = current.generator
		var old_layout: Resource = generator.manual_layout
		var old_manual: bool = generator.use_manual_layout
		var old_rules: Array = generator.part_scene_rules
		var bounds := GEOMETRY.bounds(body)
		var poses := {}
		var joint_poses := {}
		for node: Node in parts.get_children():
			if node is PhysicalBodyPart3D: poses[str(node.name)] = [node, node.transform, GEOMETRY.bounds(node)]
		for node: Node in parts.get_node("Joints").get_children():
			if node is Node3D: joint_poses[str(node.name)] = node.transform
		var transaction := EDIT.prepare(body, current.scene, float(current.multiplier)*1.25)
		check(not transaction.has("error"), "Prepare scale: " + species + " " + str(transaction.get("error", "")))
		if transaction.has("error"): actor.free(); continue
		check(generator.manual_layout == old_layout and generator.use_manual_layout == old_manual and generator.part_scene_rules == old_rules, "Preparation is non-mutating")
		var changed: PhysicalBodyPart3D = transaction.after.part
		check(GEOMETRY.bounds(body).is_equal_approx(bounds), "Preparation does not mutate source collision")
		var expected := bounds.size * Vector3(1.25, 1.25, 1.0 if body.paper_volume_enabled else 1.25)
		check(GEOMETRY.bounds(changed).size.is_equal_approx(expected), "Uniform scale and thickness: " + species)
		# Use the real editor manager so node references and scene history follow the plugin path.
		var manager := EditorInterface.get_editor_undo_redo()
		manager.create_action("Part editor validation", UndoRedo.MERGE_DISABLE, actor)
		manager.add_do_method(actor, &"restore_generated_part_edit", transaction.after)
		manager.add_undo_method(actor, &"restore_generated_part_edit", transaction.before)
		manager.add_do_reference(changed)
		manager.add_undo_reference(body)
		manager.commit_action()
		var history := manager.get_history_undo_redo(manager.get_object_history_id(actor))
		check(changed.get_parent() == parts and body.get_parent() == null, "Apply changes only selected node")
		check(history.undo(), "Editor undo")
		check(body.get_parent() == parts and generator.manual_layout == old_layout and generator.use_manual_layout == old_manual and generator.part_scene_rules == old_rules, "Undo restores node and generator state")
		check(history.redo(), "Editor redo")
		check(changed.scale.is_equal_approx(Vector3.ONE), "Rigid body keeps unit scale")
		for key: String in poses:
			var node: Node3D = parts.get_node(NodePath(key))
			check(node.transform.is_equal_approx(poses[key][1]), "Body position preserved: " + key)
			if node != changed: check(node == poses[key][0] and GEOMETRY.bounds(node).is_equal_approx(poses[key][2]), "Other bodies unchanged: " + key)
		for key: String in joint_poses: check(parts.get_node("Joints/"+key).transform.is_equal_approx(joint_poses[key]), "Joint anchors unchanged")
		check(actor.get_internal_collision_diagnostics().missing_pairs == 0, "Internal collision exceptions refreshed")
		var fresh_multiplier: float = EDIT.context(changed).multiplier
		check(is_equal_approx(fresh_multiplier, float(current.multiplier)*1.25), "UI reads persisted multiplier")
		var rejected := EDIT.prepare(changed, load("res://Scenes/Creatures/Characters/Generate_Human.tscn"), fresh_multiplier)
		check(rejected.has("error") and changed.get_parent() == parts, "Reject non-Part source without changing scene")
		check(EDIT.prepare(changed, current.scene, 0.0).has("error"), "Reject zero multiplier")
		# Re-applying the same absolute multiplier must not accumulate scale.
		var repeated := EDIT.prepare(changed, current.scene, fresh_multiplier)
		check(not repeated.has("error"), "Repeat preparation")
		if not repeated.has("error"):
			check(GEOMETRY.bounds(repeated.after.part).size.is_equal_approx(expected), "No accumulated scaling")
			repeated.after.part.free()
		manager.clear_history(manager.get_object_history_id(actor))
		# Saved scene and normal regeneration must both restore the edited internal geometry.
		var packed := PackedScene.new()
		check(packed.pack(actor) == OK, "Edited scene packs")
		var directory := "res://.godot/part_editor_validation"
		DirAccess.make_dir_recursive_absolute(directory)
		var path := directory.path_join(species+".tscn")
		check(ResourceSaver.save(packed, path) == OK, "Edited scene saves")
		var restored: Node3D = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
		restored.generate_on_ready = false
		root.add_child(restored)
		check(restored.generate_creature(), "Regenerate saved edit: " + species)
		var restored_part: PhysicalBodyPart3D = restored.get_node("GeneratedParts/"+str(changed.name))
		check(GEOMETRY.bounds(restored_part).size.is_equal_approx(expected), "Size survives disk reload/regeneration: " + species)
		check(restored_part.transform.is_equal_approx(changed.transform), "Pose survives regeneration")
		if species == "Human": test_replacement(restored, restored_part)
		if species == "Spider": test_spider_limb(restored)
		if species == "Bird": test_feather(restored)
		restored.free()
		actor.free()
		await process_frame
		print("PART_EDITOR_SPECIES_PASS ",species)
	if not failed: print("PASS: Generated part editing, validation, editor undo/redo, unchanged neighbors/joints, collision isolation, and disk/regeneration roundtrip.")
	quit(1 if failed else 0)

func test_replacement(actor: Node3D, body: PhysicalBodyPart3D) -> void:
	var replacement: PackedScene = load("res://Scenes/Creatures/Bodyparts/Human/Head/Human5Head.tscn")
	var current := EDIT.context(body)
	var transaction := EDIT.prepare(body, replacement, float(current.multiplier))
	check(not transaction.has("error"), "Prepare source replacement")
	if transaction.has("error"): return
	actor.restore_generated_part_edit(transaction.after)
	var candidate: PhysicalBodyPart3D = transaction.after.part
	check(candidate.get_meta("generated_scene_path") == replacement.resource_path, "Replacement source applied")
	check(candidate.tags == body.tags and candidate.transform.is_equal_approx(body.transform), "Replacement retains role and pose")
	var size := GEOMETRY.bounds(candidate).size
	var panel := PANEL.new()
	panel.setup(candidate, null)
	check(panel.picker.edited_resource == replacement and is_equal_approx(panel.requested_multiplier(), float(current.multiplier)), "Inspector controls reflect replacement without rounding calibration")
	panel.free()
	body.free()
	check(actor.generate_creature(), "Regenerate source replacement")
	var regenerated: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Head")
	check(regenerated.get_meta("generated_scene_path") == replacement.resource_path and GEOMETRY.bounds(regenerated).size.is_equal_approx(size), "New source and size survive regeneration")

func test_spider_limb(actor: Node3D) -> void:
	for key: String in ["Leg_1_Limb_1", "Leg_1"]:
		var body: PhysicalBodyPart3D = actor.get_node("GeneratedParts/"+key)
		var context := EDIT.context(body)
		var transaction := EDIT.prepare(body, context.scene, float(context.multiplier)*1.1)
		check(not transaction.has("error"), "Spider limb edit: " + key)
		if transaction.has("error"): continue
		actor.restore_generated_part_edit(transaction.after)
		var candidate: PhysicalBodyPart3D = transaction.after.part
		var model_pose: Transform3D = candidate.get_node("Model").transform
		var bounds := GEOMETRY.bounds(candidate)
		body.free()
		check(actor.generate_creature(), "Spider limb regenerate")
		var part: PhysicalBodyPart3D = actor.get_node("GeneratedParts/"+key)
		check(GEOMETRY.bounds(part).is_equal_approx(bounds) and part.get_node("Model").transform.is_equal_approx(model_pose), "Spider procedural alignment must retain explicit model/collision edit: " + key)

func test_feather(actor: Node3D) -> void:
	var body: PhysicalBodyPart3D
	for node: Node in actor.get_node("GeneratedParts").get_children():
		if node is PhysicalBodyPart3D and node.get_meta("generated_role", "") == "Feather": body = node; break
	check(body != null, "Bird has procedural feathers")
	if body == null: return
	var current := EDIT.context(body)
	var transaction := EDIT.prepare(body, current.scene, float(current.multiplier)*1.2)
	check(not transaction.has("error"), "Procedural feather edit")
	if transaction.has("error"): return
	actor.restore_generated_part_edit(transaction.after)
	var candidate: PhysicalBodyPart3D = transaction.after.part
	var key := str(candidate.name)
	var visual: MeshInstance3D = candidate.get_node("MeshInstance3D")
	var mesh_bounds := visual.mesh.get_aabb()
	var pose := visual.transform
	var shape_bounds := GEOMETRY.bounds(candidate)
	body.free()
	check(actor.generate_creature(), "Regenerate procedural feather")
	var restored: PhysicalBodyPart3D = actor.get_node("GeneratedParts/"+key)
	check(restored.get_node("MeshInstance3D").mesh.get_aabb().is_equal_approx(mesh_bounds) and restored.get_node("MeshInstance3D").transform.is_equal_approx(pose), "Procedural mesh must not become a box or accumulate scale")
	check(GEOMETRY.bounds(restored).is_equal_approx(shape_bounds), "Procedural feather collider persists")

func test_moved_body_anchors() -> void:
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var body: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Arm_L_Limb_2")
	var shoulder: Joint3D
	for node: Node in actor.get_node("GeneratedParts/Joints").get_children():
		if node is Joint3D and node.get_node_or_null(node.node_a).name == &"Torso" and node.get_node_or_null(node.node_b) == body: shoulder = node
	check(shoulder != null, "Human left shoulder joint exists")
	if shoulder == null: actor.free(); return
	var torso: PhysicalBodyPart3D = shoulder.get_node(shoulder.node_a)
	# Moving the rigid body leaves its generated connection marker behind the live joint.
	body.position.x += 0.179207
	var old_gap: float = actor._capture_joint_anchor(torso, shoulder, &"generated_joint_frame_a").distance_to(actor._capture_joint_anchor(body, shoulder, &"generated_joint_frame_b"))
	check(old_gap > 0.17, "Reproduce stale connection markers")
	check(actor.build_manual_layout() == null, "Explicit manual capture still rejects misaligned old markers")
	var current := EDIT.context(body)
	var transaction := EDIT.prepare(body, current.scene, float(current.multiplier)*1.1)
	check(not transaction.has("error"), "Convenient edit accepts manually moved body with valid live joints")
	if transaction.has("error"): actor.free(); return
	var changed: PhysicalBodyPart3D = transaction.after.part
	var pose := body.transform
	var joint_pose := shoulder.transform
	var generator: Node = current.generator
	var layout: Resource = generator.manual_layout
	check(body.transform.is_equal_approx(pose) and shoulder.transform.is_equal_approx(joint_pose) and generator.manual_layout == layout, "Anchor repair preparation is non-mutating")
	var manager := EditorInterface.get_editor_undo_redo()
	manager.create_action("Repair stale part anchors", UndoRedo.MERGE_DISABLE, actor)
	manager.add_do_method(actor, &"restore_generated_part_edit", transaction.after)
	manager.add_undo_method(actor, &"restore_generated_part_edit", transaction.before)
	manager.add_do_reference(changed)
	manager.add_undo_reference(body)
	manager.commit_action()
	check(actor.build_manual_layout() != null, "Applying the edit reconciles both connection endpoints")
	check(changed.transform.is_equal_approx(pose) and shoulder.transform.is_equal_approx(joint_pose), "Anchor repair preserves the edited body and physical joint poses")
	var history := manager.get_history_undo_redo(manager.get_object_history_id(actor))
	check(history.undo(), "Undo reconciled anchors")
	var undo_gap: float = actor._capture_joint_anchor(torso, shoulder, &"generated_joint_frame_a").distance_to(actor._capture_joint_anchor(body, shoulder, &"generated_joint_frame_b"))
	check(is_equal_approx(undo_gap, old_gap) and generator.manual_layout == layout, "Undo restores the original connection markers and layout")
	check(history.redo() and actor.build_manual_layout() != null, "Redo reconciles the anchors again")
	var bounds := GEOMETRY.bounds(changed)
	manager.clear_history(manager.get_object_history_id(actor))
	check(actor.generate_creature(), "Regenerate repaired anchors")
	var regenerated: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Arm_L_Limb_2")
	check(regenerated.transform.is_equal_approx(pose) and GEOMETRY.bounds(regenerated).is_equal_approx(bounds), "Edited pose and geometry survive repaired capture")
	check(actor.build_manual_layout() != null, "Regenerated connection markers remain aligned")
	actor.free()
	print("PART_EDITOR_ANCHOR_REPAIR_PASS")
