@tool
extends "res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd"

const HUMAN_SWING = preload("res://Resources/Combat/HumanArmSwing.tres")

@export_group("Initial Equipment")
## A built SampleWeapon3D scene, equipped after the generated Arm chain is ready.
@export var initial_weapon_scene: PackedScene

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint(): return
	creature_generation_finished.connect(_on_human_generation_finished)
	_equip_initial_weapon.call_deferred()

func _on_human_generation_finished(succeeded: bool) -> void:
	if succeeded: _equip_initial_weapon.call_deferred()

func _equip_initial_weapon() -> void:
	if Engine.is_editor_hint() or initial_weapon_scene == null: return
	var inventory := get_node_or_null("InventoryController3D")
	if inventory == null: return
	for item: Variant in inventory.get_items():
		if is_instance_valid(item): return
	if not inventory.equip_initial_weapon(initial_weapon_scene):
		push_warning("[human_equipment] Initial weapon could not be equipped: " + str(get_path()))

func _before_replacing_generated_parts(_previous: Node) -> void:
	var inventory := get_node_or_null("InventoryController3D")
	if inventory != null and not Engine.is_editor_hint(): inventory._unequip_current_item()

func _prepare_generated_part(part: PhysicalBodyPart3D, layout: Dictionary, blueprint: Dictionary) -> void:
	get_node(generator_path).apply_reference_connectors(part, str(layout.name))
	if layout.name == "Arm_R":
		var socket := Marker3D.new()
		socket.name = "ItemSocket3D"
		socket.position = part.get_node("JointOut").position
		part.add_child(socket)
	if layout.name == "Torso": _add_waist_visual(part, float(blueprint.get("overall_scale",1.0)))

func _on_framework_generated(plan: Dictionary) -> void:
	super._on_framework_generated(plan)
	var container := get_node_or_null("GeneratedParts")
	if container == null: return
	var scene_owner := _scene_owner()
	for path: NodePath in [^"Arm_R/ItemSocket3D", ^"Torso/WaistVisual"]:
		var node := container.get_node_or_null(path)
		if node == null: continue
		node.owner = scene_owner
		for child: Node in node.find_children("*", "", true, false): child.owner = scene_owner

func _instantiate_blueprint(blueprint: Dictionary, generator_transform: Transform3D) -> Node3D:
	# KEEP_SIZE preserves source proportions; scale the geometry as well as the layout.
	var scale_factor := float(blueprint.get("overall_scale", 1.0))
	for layout: Dictionary in blueprint.parts:
		if layout.scene_rule != null:
			layout.scene_rule = layout.scene_rule.duplicate()
			layout.scene_rule.size_multiplier *= scale_factor
	var container := super._instantiate_blueprint(blueprint, generator_transform)
	if container == null: return null
	for node: Node in container.get_children():
		if not node is PhysicalBodyPart3D: continue
		var part := node as PhysicalBodyPart3D
		if part.get_meta("generated_role", "") == "ArmLimb":
			part.tags.erase(BODY_PART.BodyPartTag.Arm)
			if BODY_PART.BodyPartTag.ArmLimb not in part.tags: part.tags.append(BODY_PART.BodyPartTag.ArmLimb)
		elif part.get_meta("generated_role", "") == "Arm":
			if BODY_PART.BodyPartTag.Arm not in part.tags: part.tags.append(BODY_PART.BodyPartTag.Arm)
	var hand := container.get_node("Arm_R") as PhysicalBodyPart3D
	if hand.arm_swing_bindings.is_empty():
		var binding := ArmSwingBinding.new()
		binding.swing_preset = HUMAN_SWING
		binding.drive_body_path = ^"../Arm_R_Limb_2"
		binding.follower_paths = [^"../Arm_R_Limb_1", ^"."]
		for joint: Joint3D in container.get_node("Joints").get_children():
			if str(joint.node_a) == "../../Torso" and str(joint.node_b) == "../../Arm_R_Limb_2":
				binding.joint_path = NodePath("../Joints/" + str(joint.name))
		hand.arm_swing_bindings.append(binding)
	_configure_human_joints(container)
	return container

func _activate_parts(container: Node) -> void:
	_configure_human_joints(container)
	super._activate_parts(container)
	var swing := get_node_or_null("LimbSwingController3D")
	if swing != null: swing.refresh_arm_bindings(true)

func _configure_human_joints(container: Node) -> void:
	for joint: Generic6DOFJoint3D in container.get_node("Joints").get_children():
		var kind: String = joint.get_meta("generated_connection_kind", "")
		var upper_arm := str(joint.node_a) == "../../Torso" and kind == "HumanArm"
		var foot := str(joint.node_b) in ["../../Leg_R", "../../Leg_L"]
		var angles := Vector3(10.0, 0.0, 60.0) if kind == "HumanLeg" else Vector3(0.0, 0.0, 100.0)
		if foot: angles = Vector3(0.0, 0.0, 35.0)
		if upper_arm: angles = Vector3(10.0, 0.0, 140.0)
		if kind == "HumanHead": angles = Vector3(5.0, 10.0, 15.0)
		angles *= PI / 180.0
		if kind == "HumanLeg": joint.set_meta("authored_walk_limits", angles)
		for index: int in 3:
			var axis: String = ["x", "y", "z"][index]
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -angles[index])
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, angles[index])
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, kind != "HumanLeg" and angles[index] > 0.0)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, 40.0)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, 8.0)
	preload("res://Scripts/Creatures/HumanKneeGeometry3D.gd").configure(container)

func _add_waist_visual(torso: PhysicalBodyPart3D, multiplier: float) -> void:
	var generator := get_node(generator_path)
	if not generator.waist_visual_enabled: return
	if torso.has_node("WaistVisual"): return
	var rule: GeneratedPartSceneRule = generator.get_part_scene_rule("Decoration", "WaistVisual", "WaistVisual")
	if rule == null or rule.part_scene == null: return
	rule = rule.duplicate()
	rule.size_multiplier *= multiplier
	var instance := rule.part_scene.instantiate()
	if not instance is PhysicalBodyPart3D:
		instance.free()
		return
	var source := instance as PhysicalBodyPart3D
	var bounds := PART_GEOMETRY.fit(source, Vector3.ONE, rule, "Decoration", generator.part_width * multiplier)
	generator.apply_reference_connectors(source, "WaistVisual")
	var model := source.get_node_or_null(source.custom_model_path) as Node3D
	if bounds.size == Vector3.ZERO or model == null:
		source.free()
		return
	# Reuse the external volume mesh, excluding the GLB's hidden textured quad.
	var paper := model.get_node_or_null("PaperVolume") as MeshInstance3D
	if paper == null:
		source.free()
		return
	var visual := Node3D.new()
	visual.transform = model.transform
	visual.name = "WaistVisual"
	var mesh := MeshInstance3D.new()
	mesh.name = "PaperVolume"
	mesh.transform = paper.transform
	mesh.mesh = paper.mesh
	mesh.material_override = paper.material_override
	visual.add_child(mesh)
	visual.position += generator.waist_attachment_shift(torso, source, multiplier)
	torso.add_child(visual)
	source.free()
