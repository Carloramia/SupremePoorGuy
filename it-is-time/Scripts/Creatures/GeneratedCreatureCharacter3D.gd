@tool
extends "res://Scripts/Creatures/PhysicalCharacterController.gd"

signal creature_generation_finished(succeeded: bool)

const PERFORMANCE_STATS = preload("res://Scripts/Debug/ControlPerformanceStats.gd")
var _control_perf: PERFORMANCE_STATS = PERFORMANCE_STATS.new()

const PART_SCENE: PackedScene = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
const PART_GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const DAMAGE_SCENE: PackedScene = preload("res://Scenes/Creatures/Components/CharacterDamageController3D.tscn")
const GEOMETRY = preload("res://Scripts/Creatures/CreatureBoxGeometry.gd")
const SEGMENT_CONSTRAINT = preload("res://Scripts/Creatures/SegmentConstraint3D.gd")
const SEGMENT_SPRING = preload("res://Scripts/Creatures/SegmentDistanceSpring3D.gd")
const PLANAR_CONSTRAINTS = preload("res://Scripts/Creatures/CreaturePlanarConstraints3D.gd")
const HEAD_SUPPORT = preload("res://Scripts/Creatures/HeadPositionSupport3D.gd")
const BODY_PART = preload("res://Scripts/Creatures/PhysicalBodyParts.gd")
const DENSITY_DATA = preload("res://Scripts/Creatures/GeneratedCreatureDensityData.gd")
const FEATHER_GEOMETRY = preload("res://Scripts/Creatures/Generators/BirdFeatherGeometry.gd")

@export_group("Generation")
@export var generator_path: NodePath = ^"CreatureGenerator"
@export_tool_button("生成框架与物理角色", "Node3D") var generate_character_button: Callable:
	get:
		return Callable(self, &"generate_creature")
@export_tool_button("将当前部件姿态写入生成器", "Save") var capture_layout_button: Callable:
	get: return Callable(self, &"capture_manual_layout")
@export_tool_button("自动对齐连接点", "Joint3D") var align_layout_connections_button: Callable:
	get: return Callable(self, &"align_manual_connections")
## Maximum allowed distance between paired joint ports, in current scene units.
@export_range(0.0001, 1.0, 0.001, "or_greater") var manual_layout_connection_tolerance: float = 0.01

func align_manual_connections() -> bool:
	if not Engine.is_editor_hint():
		push_warning("[manual_layout] Connection alignment is editor-only.")
		return false
	return _align_manual_connections()

## Re-author joint anchors without changing any body transform or collider.
func _align_manual_connections() -> bool:
	var container := get_node_or_null("GeneratedParts") as Node3D
	if not is_inside_tree() or container == null: return false
	var joints := container.get_node_or_null("Joints")
	if joints == null: return false
	var pending: Array[Dictionary] = []
	var maximum_gap := 0.0
	# Validate the whole operation before changing any port.
	for node: Node in joints.get_children():
		var joint := node as Joint3D
		if joint == null or joint.has_meta(&"segment_rotation_constraint"): continue
		var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if a == null or b == null or a.is_broken or b.is_broken:
			push_warning("[manual_layout] Cannot align missing/broken endpoints: " + str(joint.name))
			return false
		var anchor_a := _capture_joint_anchor(a, joint, &"generated_joint_frame_a")
		var anchor_b := _capture_joint_anchor(b, joint, &"generated_joint_frame_b")
		if not anchor_a.is_finite() or not anchor_b.is_finite(): return false
		maximum_gap = maxf(maximum_gap, anchor_a.distance_to(anchor_b))
		pending.append({"joint":joint, "a":a, "b":b, "anchor":(anchor_a+anchor_b)*0.5})
	if pending.is_empty(): return false
	var scene_owner := _scene_owner()
	for entry: Dictionary in pending:
		var joint: Joint3D = entry.joint
		var a: PhysicalBodyPart3D = entry.a
		var b: PhysicalBodyPart3D = entry.b
		var kind := str(joint.get_meta(&"generated_connection_kind", str(joint.name).get_slice("_", 2)))
		var parent_body := a
		var child_body := b
		if kind == "Limb" and (str(a.get_meta(&"generated_role", "")) in ["Leg","ForeLeg"] or (str(a.get_meta(&"generated_role", "")) == "Limb" and str(b.get_meta(&"generated_role", "")) == "Limb")):
			parent_body = b
			child_body = a
		_align_connection_port(parent_body, joint, "JointOut_"+str(child_body.name), child_body, entry.anchor, scene_owner)
		_align_connection_port(child_body, joint, "JointIn_"+str(parent_body.name), parent_body, entry.anchor, scene_owner)
		joint.global_position = entry.anchor
		joint.set_meta(&"generated_joint_frame_a", a.global_transform.affine_inverse()*joint.global_transform)
		joint.set_meta(&"generated_joint_frame_b", b.global_transform.affine_inverse()*joint.global_transform)
	if Engine.is_editor_hint(): EditorInterface.mark_scene_as_unsaved()
	print("[manual_layout] Aligned %d joints; maximum_previous_gap=%.6f; body poses unchanged. Capture the layout to persist generation anchors." % [pending.size(),maximum_gap])
	return true

func _align_connection_port(body: PhysicalBodyPart3D, joint: Joint3D, port_name: String, other: PhysicalBodyPart3D, anchor: Vector3, scene_owner: Node) -> void:
	var port: Marker3D
	for child: Node in body.get_children():
		if child is Marker3D and child.get_meta(&"joint_name", "") == str(joint.name):
			port = child
			break
	if port == null:
		port = Marker3D.new()
		port.name = port_name
		body.add_child(port)
	port.position = body.global_transform.affine_inverse()*anchor
	port.set_meta(&"generated_connection_port", true)
	port.set_meta(&"joint_name", str(joint.name))
	port.set_meta(&"connected_part", str(other.name))
	port.owner = scene_owner

func capture_manual_layout() -> bool:
	if not Engine.is_editor_hint():
		push_warning("[manual_layout] Capture is editor-only; runtime physics poses are not authored layouts.")
		return false
	return _capture_manual_layout()

## Kept separate so the capture/round-trip can be validated without the editor UI.
func _capture_manual_layout() -> bool:
	var generator := get_node_or_null(generator_path) as Node3D
	var container := get_node_or_null("GeneratedParts") as Node3D
	if generator == null or container == null or not _valid_settings(generator): return false
	var multiplier: float = generator.overall_scale
	if not is_finite(multiplier) or multiplier < 0.1: return false
	var parts: Array[Dictionary] = []
	var indices: Dictionary = {}
	var keys: Dictionary = {}
	var to_generator := generator.global_transform.affine_inverse()
	for child: Node in container.get_children():
		var body := child as PhysicalBodyPart3D
		if body == null: continue
		var key := str(body.get_meta(&"generated_part_key", ""))
		if key.is_empty() or keys.has(key) or body.is_broken:
			push_warning("[manual_layout] Missing/duplicate PartKey or broken part: " + str(body.name))
			return false
		var pose := to_generator * body.global_transform
		if not pose.basis.get_scale().is_equal_approx(Vector3.ONE) or not pose.origin.is_finite():
			push_warning("[manual_layout] Part roots must retain unit scale: " + str(body.name))
			return false
		pose.origin /= multiplier
		var layout: Dictionary = body.get_meta(&"generated_layout", {}).duplicate(true)
		layout.merge({"name": str(body.name), "part_key": key, "role": str(body.get_meta(&"generated_role", "")), "size": body.get_meta(&"generated_framework_size", body.get_meta(&"generated_size", Vector3.ONE)), "transform": pose}, true)
		layout.erase("scene_rule")
		layout.size /= multiplier
		if layout.has("connector_span"): layout.connector_span /= multiplier
		if body.has_meta(&"body_segment_id"): layout["segment_id"] = int(body.get_meta(&"body_segment_id"))
		layout["sub_torso"] = BODY_PART.BodyPartTag.SubTorso in body.tags
		# Older saved characters predate the full layout metadata.
		if layout.role in ["Wing", "WingLimb"] and not layout.has("wing_section"):
			layout["wing_section"] = str(body.get_meta(&"generated_part_type", "WingRoot")).trim_prefix("Wing")
		indices[body] = parts.size()
		keys[key] = true
		parts.append(layout)
	if parts.is_empty(): return false
	var connections: Array[Dictionary] = []
	var joints := container.get_node_or_null("Joints")
	if joints == null: return false
	for joint: Node in joints.get_children():
		if joint.has_meta(&"segment_rotation_constraint"): continue
		if not joint is Joint3D and not joint is SEGMENT_SPRING: continue
		var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if not indices.has(a) or not indices.has(b):
			push_warning("[manual_layout] Missing endpoint for " + str(joint.name))
			return false
		if joint is SEGMENT_SPRING:
			connections.append({"a": indices[a], "b": indices[b], "anchor": Vector3.ZERO, "basis": Basis.IDENTITY, "kind": "Segment"})
			continue
		var anchor_a := _capture_joint_anchor(a, joint, &"generated_joint_frame_a")
		var anchor_b := _capture_joint_anchor(b, joint, &"generated_joint_frame_b")
		var gap := anchor_a.distance_to(anchor_b)
		if gap > manual_layout_connection_tolerance:
			push_warning("[manual_layout] %s -> %s gap=%.6f exceeds tolerance=%.6f; previous layout retained." % [a.name, b.name, gap, manual_layout_connection_tolerance])
			return false
		var kind := str(joint.get_meta(&"generated_connection_kind", str(joint.name).get_slice("_", 2)))
		connections.append({"a": indices[a], "b": indices[b], "anchor": (to_generator * ((anchor_a + anchor_b) * 0.5)) / multiplier, "basis": (to_generator.basis * joint.global_basis).orthonormalized(), "kind": kind})
		if kind == "Wing":
			parts[indices[b]]["wing_open_basis"] = parts[indices[a]].transform.basis * Basis(joint.get_meta(&"wing_open_relative_a", Quaternion.IDENTITY))
		if kind == "Feather":
			parts[indices[b]]["feather_open_basis"] = parts[indices[a]].transform.basis * Basis(joint.get_meta(&"feather_open_relative_a", Quaternion.IDENTITY))
	var captured := preload("res://Scripts/Creatures/Generators/CreatureManualLayout.gd").new()
	captured.resource_local_to_scene = true
	captured.blueprint = {"parts": parts, "connections": connections}
	generator.manual_layout = captured
	generator.use_manual_layout = true
	if Engine.is_editor_hint(): EditorInterface.mark_scene_as_unsaved()
	print("[manual_layout] Captured %d parts and %d connections for %s; save the scene to persist." % [parts.size(), connections.size(), name])
	return true

func _capture_joint_anchor(body: PhysicalBodyPart3D, joint: Joint3D, frame_key: StringName) -> Vector3:
	for child: Node in body.get_children():
		if child is Marker3D and child.get_meta(&"joint_name", "") == str(joint.name): return child.global_position
	var frame: Transform3D = joint.get_meta(frame_key, body.global_transform.affine_inverse() * joint.global_transform)
	return body.global_transform * frame.origin

@export var generate_on_ready: bool = true
@export var show_framework: bool = false:
	set(value):
		show_framework = value
		var generator := get_node_or_null(generator_path) as Node3D
		if generator != null:
			generator.visible = value

@export_group("Physics Test Mode")
## Temporary isolation mode: no gravity, no weight/lift recovery servos.
@export var zero_gravity_test_mode: bool = false:
	set(value):
		zero_gravity_test_mode = value
		if is_node_ready(): _apply_physics_test_mode()

@export_group("Planar Constraints")
## Independent support and physical gait; inter-part joints are suspended and X/Y rotation stays locked.
@export var planar_constraints_enabled: bool = true:
	set(value):
		planar_constraints_enabled = value
		if is_node_ready() and not Engine.is_editor_hint(): _sync_planar_constraints()

func is_planar_mode_active() -> bool:
	return planar_constraints_enabled

func _sync_planar_constraints() -> void:
	var movement := get_node_or_null("GeneratedLegStepMovementController3D")
	if movement != null and movement.has_method("prepare_planar_mode_change"): movement.prepare_planar_mode_change()
	var guides := get_node_or_null("PlanarConstraints")
	if guides == null:
		guides = PLANAR_CONSTRAINTS.new()
		guides.name = "PlanarConstraints"
		add_child(guides)
	guides.clear_constraints()
	_sync_neck_joint_sliding()
	var container := get_node_or_null("GeneratedParts")
	if planar_constraints_enabled and container != null: guides.configure(container)
	_configure_body_part_collision_exceptions()

@export_group("Physical Parts")
## Optional species preset; matched by generated type, independently of overlapping physics tags.
@export var density_data: DENSITY_DATA
## Mass is density times volume; optional limits apply to all generated parts, including feathers.
@export_range(0.01, 100.0, 0.01, "or_greater") var mass_density: float = 1.0
@export_range(0.01, 10.0, 0.01, "or_greater") var minimum_part_mass: float = 0.1
## Thin feathers need a smaller mass floor than structural body blocks.
@export_range(0.001, 1.0, 0.001, "or_greater") var minimum_feather_mass: float = 0.005
@export_range(0.01, 100.0, 0.01, "or_greater") var maximum_part_mass: float = 10.0
@export_range(0.0, 10.0, 0.01, "or_greater") var part_linear_damping: float = 0.15
@export_range(0.0, 10.0, 0.01, "or_greater") var part_angular_damping: float = 1.0

@export_group("Joint Settings")
@export_range(0.0, 90.0, 0.1) var limb_angular_limit_degrees: float = 35.0
@export_range(0.0, 90.0, 0.1) var neck_angular_limit_degrees: float = 20.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var angular_spring_stiffness: float = 30.0
@export_range(0.0, 100.0, 0.1, "or_greater") var angular_spring_damping: float = 5.0

@export_group("Tail Joints")
## Segmented tails bend about local Z only; the root remains attached to Torso.
@export_range(0.0, 90.0, 0.1) var tail_joint_angular_limit_degrees: float = 25.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var tail_joint_spring_stiffness: float = 80.0
@export_range(0.0, 100.0, 0.1, "or_greater") var tail_joint_spring_damping: float = 8.0

@export_group("Wing Joint Limits")
@export var wing_joint_limits_enabled: bool = true
## Extra rotation beyond the generated folded/open poses. X/Y remain locked.
@export_range(0.0, 90.0, 0.1) var wing_root_limit_margin_degrees: float = 10.0
@export_range(0.0, 90.0, 0.1) var wing_middle_limit_margin_degrees: float = 10.0
@export_range(0.0, 90.0, 0.1) var wing_tip_limit_margin_degrees: float = 10.0

@export_group("Neck Linear Springs")
## Neck-Neck joints only; end connections to Torso/Head retain their current limits.
@export var neck_linear_springs_enabled: bool = true:
	set(value):
		neck_linear_springs_enabled = value
		if is_node_ready(): _sync_neck_joint_sliding()
@export var neck_joint_linear_slack: Vector3 = Vector3(0.06,0.06,0.06):
	set(value):
		if not value.is_finite(): return
		neck_joint_linear_slack = value.max(Vector3.ZERO)
		if is_node_ready(): _sync_neck_joint_sliding()
@export_range(0.0, 1000.0, 0.1, "or_greater") var neck_linear_spring_stiffness: float = 80.0:
	set(value):
		neck_linear_spring_stiffness = value
		if is_node_ready(): _sync_neck_joint_sliding()
@export_range(0.0, 100.0, 0.1, "or_greater") var neck_linear_spring_damping: float = 8.0:
	set(value):
		neck_linear_spring_damping = value
		if is_node_ready(): _sync_neck_joint_sliding()

func _sync_neck_joint_sliding() -> void:
	var container := get_node_or_null("GeneratedParts")
	if container == null: return
	for node: Node in container.find_children("*","Generic6DOFJoint3D",true,false):
		var joint := node as Generic6DOFJoint3D
		if joint.is_queued_for_deletion(): continue
		if PhysicsServer3D.joint_get_type(joint.get_rid()) == PhysicsServer3D.JOINT_TYPE_MAX: continue
		var a := joint.get_node_or_null(joint.node_a)
		var b := joint.get_node_or_null(joint.node_b)
		if a == null or b == null: continue
		if a.get_meta(&"generated_role","") != "Neck" or b.get_meta(&"generated_role","") != "Neck": continue
		for index: int in range(3):
			var axis: String = ["x","y","z"][index]
			var slack: float = neck_joint_linear_slack[index] if neck_linear_springs_enabled else 0.0
			joint.call("set_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,true)
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,-slack)
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,slack)
			joint.call("set_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING,neck_linear_springs_enabled and slack>0.0)
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS,maxf(neck_linear_spring_stiffness,0.0))
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING,maxf(neck_linear_spring_damping,0.0))
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_SPRING_EQUILIBRIUM_POINT,0.0)

@export_group("Passive Limb Links")
## Passive angular damping on LegLimb bodies, without any rest-pose motors or springs.
@export_range(0.0, 30.0, 0.1) var limb_hinge_damping: float = 3.0
## Maximum pivot translation in either direction, along the joint-local X/Y/Z axes (Godot units).
## Applies only between two LegLimb parts. Zero restores a rigid positional connection.
@export var limb_joint_linear_slack: Vector3 = Vector3(0.03, 0.03, 0.0):
	set(value):
		if not value.is_finite(): return
		limb_joint_linear_slack = value.max(Vector3.ZERO)
		if is_node_ready(): _sync_limb_joint_sliding()


@export_group("Body Segments")
## Assignment uses generator-local X only; nearby seeds merge transitively.
@export var segmented_torso_enabled: bool = true
@export_range(0.0, 100.0, 0.1) var segment_merge_length_percent: float = 10.0
@export_range(0.001, 1.0, 0.001) var segment_weight_decay_ratio: float = 0.2
@export_group("Segment Rotation Constraints")
## Preserve initial relative X/Y rotation; relative Z stays free.
@export var segment_rotation_constraints_enabled: bool = true:
	set(value):
		segment_rotation_constraints_enabled = value
		if is_node_ready() and has_node("GeneratedParts"):
			_sync_segment_rotation_constraints(get_node("GeneratedParts"))

@export_group("Segment Transverse Constraints")
## X follows the initial connection frame; Y/Z limit anchor drift while X can slide.
@export var segment_transverse_constraints_enabled: bool = true:
	set(value):
		segment_transverse_constraints_enabled = value
		if is_node_ready() and has_node("GeneratedParts"):
			_sync_segment_rotation_constraints(get_node("GeneratedParts"))
@export_range(0.0, 2.0, 0.01, "or_greater") var segment_transverse_slack: float = 0.05:
	set(value):
		segment_transverse_slack = value
		if is_node_ready() and has_node("GeneratedParts"):
			_sync_segment_rotation_constraints(get_node("GeneratedParts"))

@export_group("Segment Distance Springs")
@export var segment_translation_springs_enabled: bool = true
@export_range(0.0, 500.0, 0.1) var segment_spring_maximum_acceleration: float = 50.0
@export var segment_maximum_distance_lock_enabled: bool = true
@export_range(1.0, 3.0, 0.01, "or_greater") var segment_maximum_distance_ratio: float = 1.15
@export_range(0.1, 20.0, 0.1) var segment_spring_frequency: float = 3.0
@export_range(0.0, 2.0, 0.05) var segment_spring_damping_ratio: float = 1.0

var _last_generation_succeeded: bool = false
var _rebuilding: bool = false

func _ensure_control_performance_stats() -> void:
	# An editor script reload can leave a member uninitialized on an existing node.
	if not is_instance_valid(_control_perf):
		_control_perf = PERFORMANCE_STATS.new()
		if is_inside_tree(): _control_perf.register(self)

func _ready() -> void:
	_ensure_control_performance_stats()
	_control_perf.register(self)
	super._ready()
	_connect_generator()
	if not Engine.is_editor_hint():
		if generate_on_ready:
			call_deferred("generate_creature")
		elif has_node("GeneratedParts"):
			_configure_body_part_collision_exceptions()
			_reset_damage_controller()
			_activate_parts(get_node("GeneratedParts"))

func _connect_generator() -> void:
	var generator := get_node_or_null(generator_path) as Node3D
	if generator == null:
		return
	generator.visible = show_framework
	if not generator.is_connected(&"framework_generated", _on_framework_generated):
		generator.connect(&"framework_generated", _on_framework_generated)

func generate_creature() -> bool:
	_ensure_control_performance_stats()
	var started: int = _control_perf.start()
	var result: bool = _perf_impl_generate_creature()
	_control_perf.finish(&"generation_total", started)
	if not result: creature_generation_finished.emit(false)
	return result

func _perf_impl_generate_creature() -> bool:
	if not is_inside_tree() or _rebuilding:
		return false
	var generator := get_node_or_null(generator_path) as Node3D
	if generator == null or not _valid_settings(generator):
		push_warning("[generated_creature] Invalid settings or scaled character/generator; previous physics retained.")
		return false
	_connect_generator()
	_last_generation_succeeded = false
	if not generator.generate_torso():
		return false
	return _last_generation_succeeded

func _valid_settings(generator: Node3D) -> bool:
	if mass_limits_enabled:
		for value: float in [minimum_part_mass, minimum_feather_mass, maximum_part_mass]:
			if not is_finite(value) or value <= 0.0: return false
		if maximum_part_mass < maxf(minimum_part_mass, minimum_feather_mass): return false
	if density_data != null and not density_data.is_valid(): return false
	if not global_basis.get_scale().is_equal_approx(Vector3.ONE) or not generator.transform.basis.get_scale().is_equal_approx(Vector3.ONE):
		return false
	if not limb_joint_linear_slack.is_finite(): return false
	for value: float in [mass_density, part_linear_damping, part_angular_damping, limb_angular_limit_degrees, neck_angular_limit_degrees, angular_spring_stiffness, angular_spring_damping, tail_joint_angular_limit_degrees, tail_joint_spring_stiffness, tail_joint_spring_damping]:
		if not is_finite(value) or value < 0.0:
			return false
	return mass_density > 0.0

func _on_framework_generated(plan: Dictionary) -> void:
	_ensure_control_performance_stats()
	var started: int = _control_perf.start()
	_perf_impl__on_framework_generated(plan)
	_control_perf.finish(&"physics_assembly", started)

func _perf_impl__on_framework_generated(plan: Dictionary) -> void:
	if _rebuilding:
		return
	var generator := get_node(generator_path) as Node3D
	if not _valid_settings(generator):
		push_warning("[generated_creature] Physics assembly requires unit scale and finite settings.")
		return
	_rebuilding = true
	var blueprint_started: int = _control_perf.start()
	var blueprint: Dictionary = plan.manual_blueprint.duplicate(true) if plan.has("manual_blueprint") else _build_blueprint(plan, float(generator.torso_connection_distance))
	_control_perf.finish(&"blueprint", blueprint_started)
	if blueprint.is_empty():
		push_warning("[generated_creature] Frame connectivity could not be converted; previous physics retained.")
		_rebuilding = false
		return
	var bodies_started: int = _control_perf.start()
	# Persistent root settings are resolved again for every blueprint, never stored on preview nodes.
	for layout: Dictionary in blueprint.parts:
		layout["scene_rule"] = generator.get_part_scene_rule(_get_generated_part_type(layout), str(layout.name), str(layout.get("part_key", layout.name)))
	# Use one scaled width for every paper model, including saved manual layouts.
	# Authored thickness and per-rule Size Multiplier must not affect this depth.
	blueprint["paper_depth"] = float(generator.part_width) * float(generator.overall_scale)
	var staging := _instantiate_blueprint(blueprint, generator.transform)
	_control_perf.finish(&"instantiate_bodies_joints", bodies_started)
	if staging == null:
		_rebuilding = false
		return
	var previous := get_node_or_null("GeneratedParts")
	# The runtime-only action script is a placeholder while generating in the editor.
	if not Engine.is_editor_hint():
		var action := get_node_or_null("CreatureActionController3D")
		if action != null: action.cancel_action(&"regenerated")
		var dive := get_node_or_null("BirdDiveAttackController3D")
		if dive != null: dive.cancel_action(&"regenerated")
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	staging.name = "GeneratedParts"
	add_child(staging)
	_sync_segment_rotation_constraints(staging)
	_apply_physics_test_mode()
	var scene_owner := _scene_owner()
	staging.owner = scene_owner
	for part: Node in staging.get_children():
		part.owner = scene_owner
		for child: Node in part.get_children():
			if child.has_meta(&"generated_connection_port"): child.owner = scene_owner
		if part.has_meta(&"generated_scene_path"):
			# Fitting changes descendants of an instantiated Part, not just exported root values.
			# Preserve those overrides when the generated character is packed/saved in the editor.
			scene_owner.set_editable_instance(part, true)
		if part.name == &"Joints":
			for joint: Node in part.get_children():
				joint.owner = scene_owner
	_control_perf.count(&"generated_parts", blueprint.parts.size())
	_control_perf.count(&"generated_joints", blueprint.connections.size())
	var exceptions_started: int = _control_perf.start()
	_configure_body_part_collision_exceptions()
	_control_perf.finish(&"collision_exceptions", exceptions_started)
	if body_parts_ignore_each_other:
		_control_perf.count(&"collision_exception_pairs", blueprint.parts.size() * (blueprint.parts.size() - 1) / 2)
	if not Engine.is_editor_hint():
		_reset_damage_controller()
		_activate_parts(staging)
	else:
		EditorInterface.mark_scene_as_unsaved()
	var collision_audit := get_internal_collision_diagnostics()
	print("[generated_collision] ", collision_audit)
	if body_parts_ignore_each_other and collision_audit.missing_pairs > 0:
		push_warning("[generated_collision] Internal collision exceptions are incomplete.")
	_last_generation_succeeded = true
	_rebuilding = false
	var springs := 0
	for connection: Dictionary in blueprint.connections:
		if connection.kind == "Segment": springs += 1
	print("[generated_creature] character=%s parts=%d physical_joints=%d segment_springs=%d connected=true internal_collisions_ignored=%s" % [name, blueprint.parts.size(), blueprint.connections.size() - springs, springs, body_parts_ignore_each_other])
	creature_generation_finished.emit(true)

func _scene_owner() -> Node:
	if Engine.is_editor_hint():
		var edited := get_tree().edited_scene_root
		if edited != null and (edited == self or edited.is_ancestor_of(self)):
			return edited
	return self

func _reset_damage_controller() -> void:
	var previous := get_node_or_null("CharacterDamageController3D")
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	# Add after all Part ready callbacks, so initial discovery sees the complete character.
	var damage := DAMAGE_SCENE.instantiate()
	add_child(damage)
	damage.owner = _scene_owner()

func _migrate_saved_body_segments(container: Node) -> void:
	for link: Node in container.find_children("*", "", true, false):
		if link.has_method("is_segment_spring"):
			link.maximum_distance_lock_enabled = segment_maximum_distance_lock_enabled
			link.maximum_distance_ratio = segment_maximum_distance_ratio
	var bodies: Array[RigidBody3D] = []
	var layouts: Array[Dictionary] = []
	var indices: Array[int] = []
	var migrate := false
	for node: Node in container.get_children():
		if not node is PhysicalBodyPart3D or BODY_PART.BodyPartTag.Torso not in node.tags: continue
		migrate = migrate or int(node.get_meta(&"segment_layout_version", 0)) < 3
		indices.append(bodies.size())
		bodies.append(node)
		layouts.append({"sub_torso": BODY_PART.BodyPartTag.SubTorso in node.tags, "size": node.get_meta(&"generated_size", Vector3.ONE), "transform": node.transform})
	if not migrate or bodies.is_empty(): return
	var edges: Array[Dictionary] = []
	var old_joints: Array[Node] = []
	for node: Node in container.find_children("*", "Generic6DOFJoint3D", true, false):
		if node.has_meta(&"segment_rotation_constraint"): continue
		var a := node.get_node_or_null(node.node_a) as RigidBody3D
		var b := node.get_node_or_null(node.node_b) as RigidBody3D
		if a not in bodies or b not in bodies: continue
		edges.append({"a": bodies.find(a), "b": bodies.find(b), "anchor": node.position, "distance": a.position.distance_squared_to(b.position)})
		old_joints.append(node)
	var owners := _partition_torso_graph(layouts, indices, edges)
	_complete_segment_edges(layouts, indices, owners, edges)
	for index: int in range(bodies.size()):
		bodies[index].set_meta(&"body_segment_id", owners[index])
		bodies[index].set_meta(&"segment_layout_version", 3)
	for node: Node in old_joints:
		node.get_parent().remove_child(node)
		node.queue_free()
	var parents: Array[int] = []
	for index: int in range(bodies.size()): parents.append(index)
	var joints := container.get_node("Joints")
	for cross: bool in [false, true]:
		for edge: Dictionary in edges:
			if (owners[edge.a] != owners[edge.b]) != cross: continue
			var first := _root(parents, edge.a)
			var second := _root(parents, edge.b)
			if first == second: continue
			parents[first] = second
			var link: Node
			if cross:
				link = SEGMENT_SPRING.new()
				link.rest_reference_yaw = global_basis.get_euler().y
				link.enabled = segment_translation_springs_enabled
				link.frequency = segment_spring_frequency
				link.damping_ratio = segment_spring_damping_ratio
				link.maximum_acceleration = segment_spring_maximum_acceleration
				link.maximum_distance_lock_enabled = segment_maximum_distance_lock_enabled
				link.maximum_distance_ratio = segment_maximum_distance_ratio
			else:
				var joint := Generic6DOFJoint3D.new()
				joint.position = edge.anchor
				joint.exclude_nodes_from_collision = true
				link = joint
			link.name = "BodyLink_%d_%d" % [edge.a, edge.b]
			link.node_a = NodePath("../../" + str(bodies[edge.a].name))
			link.node_b = NodePath("../../" + str(bodies[edge.b].name))
			joints.add_child(link)
			link.owner = _scene_owner()
	# Removing a Joint can clear collision exceptions in the physics backend.
	_configure_body_part_collision_exceptions()

func _activate_parts(container: Node) -> void:
	_apply_physics_test_mode()
	for part: Node in container.get_children():
		if part is PhysicalBodyPart3D:
			# Migrate already-saved generated scenes as well as newly generated parts.
			if part.get_meta(&"generated_role", "") == "Limb" and BODY_PART.BodyPartTag.LegLimb not in part.tags:
				part.tags.append(BODY_PART.BodyPartTag.LegLimb)
		if part is PhysicalBodyPart3D and str(part.name).begins_with("SubTorso") and BODY_PART.BodyPartTag.SubTorso not in part.tags:
			part.tags.append(BODY_PART.BodyPartTag.SubTorso)
		if part is PhysicalBodyPart3D:
			part.sync_foot_rotation_lock()
			if BODY_PART.BodyPartTag.LegLimb in part.tags:
				part.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
				part.angular_damp = 0.0
		if part is RigidBody3D:
			(part as RigidBody3D).freeze = false
	_migrate_saved_body_segments(container)
	_sync_segment_rotation_constraints(container)
	_sync_neck_joint_sliding()
	for node: Node in container.find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		var body_a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var body_b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if body_a == null or body_b == null: continue
		if BODY_PART.BodyPartTag.LegLimb in body_a.tags or BODY_PART.BodyPartTag.LegLimb in body_b.tags:
			for axis: String in ["x", "y", "z"]:
				joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
				joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
		if _is_limb_subtorso_pair(body_a, body_b): _lock_limb_root_yaw(joint)
		if BODY_PART.BodyPartTag.LegLimb not in body_a.tags or BODY_PART.BodyPartTag.LegLimb not in body_b.tags: continue
		_configure_limb_joint_sliding(joint)
	if get_node_or_null("HeadPositionSupport3D") == null:
		var support := HEAD_SUPPORT.new()
		support.name = "HeadPositionSupport3D"
		add_child(support)
	get_node("HeadPositionSupport3D").set_character_control_enabled(true)
	# Future optional controllers can refresh their queries after regeneration.
	for node: Node in find_children("*", "", true, false):
		if node.has_method("refresh_physics_query_cache"):
			node.call("refresh_physics_query_cache")
	_sync_planar_constraints()

func _is_limb_subtorso_pair(a: PhysicalBodyPart3D, b: PhysicalBodyPart3D) -> bool:
	return (BODY_PART.BodyPartTag.LegLimb in a.tags and BODY_PART.BodyPartTag.SubTorso in b.tags) or (BODY_PART.BodyPartTag.LegLimb in b.tags and BODY_PART.BodyPartTag.SubTorso in a.tags)

func _lock_limb_root_yaw(joint: Generic6DOFJoint3D) -> void:
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)

func _configure_limb_joint_sliding(joint: Generic6DOFJoint3D) -> void:
	var axes := ["x", "y", "z"]
	for index: int in range(3):
		var axis: String = axes[index]
		var slack: float = limb_joint_linear_slack[index]
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -slack)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, slack)
		# Sliding is passive within hard bounds, without position motors or centering springs.
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR, false)
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, false)
		if axis != "z":
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)

func _sync_limb_joint_sliding() -> void:
	var container := get_node_or_null("GeneratedParts")
	if container == null: return
	for node: Node in container.find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if a != null and b != null and BODY_PART.BodyPartTag.LegLimb in a.tags and BODY_PART.BodyPartTag.LegLimb in b.tags:
			_configure_limb_joint_sliding(joint)

func _apply_physics_test_mode() -> void:
	var container := get_node_or_null("GeneratedParts")
	if container != null:
		for part: Node in container.get_children():
			if not part is RigidBody3D: continue
			if zero_gravity_test_mode:
				if not part.has_meta(&"gravity_scale_before_test"): part.set_meta(&"gravity_scale_before_test", part.gravity_scale)
				part.gravity_scale = 0.0
			else:
				part.gravity_scale = float(part.get_meta(&"gravity_scale_before_test", part.gravity_scale))
				part.remove_meta(&"gravity_scale_before_test")
	var movement := get_node_or_null("GeneratedLegStepMovementController3D")
	if movement != null and not Engine.is_editor_hint():
		movement.set_simplified_physics_mode(zero_gravity_test_mode)
		if zero_gravity_test_mode: movement.set_recovery_control_active(false)

func _sync_segment_rotation_constraints(container: Node) -> void:
	var joints := container.get_node_or_null("Joints")
	if joints == null: return
	for node: Node in joints.get_children():
		if node.has_meta(&"segment_rotation_constraint") and not (segment_rotation_constraints_enabled or segment_transverse_constraints_enabled):
			joints.remove_child(node)
			node.queue_free()
	if not (segment_rotation_constraints_enabled or segment_transverse_constraints_enabled): return
	for spring: Node in joints.get_children():
		if not spring.has_method("is_segment_spring") or spring.is_queued_for_deletion(): continue
		var joint_name := "Rotation_" + str(spring.name)
		var a := spring.get_node_or_null(spring.node_a) as RigidBody3D
		var b := spring.get_node_or_null(spring.node_b) as RigidBody3D
		if a == null or b == null or bool(a.get("is_broken")) or bool(b.get("is_broken")): continue
		var joint := joints.get_node_or_null(NodePath(joint_name)) as Generic6DOFJoint3D
		var created := joint == null
		if created:
			joint = SEGMENT_CONSTRAINT.new()
			joint.name = joint_name
			joint.set_meta(&"segment_rotation_constraint", true)
			joint.node_a = spring.node_a
			joint.node_b = spring.node_b
			joint.position = (a.position + b.position) * 0.5
			var generator := get_node_or_null(generator_path) as Node3D
			joint.basis = generator.basis.orthonormalized() if generator != null else Basis.IDENTITY
		elif joint.get_script() != SEGMENT_CONSTRAINT:
			joint.set_script(SEGMENT_CONSTRAINT)
		joint.exclude_nodes_from_collision = true
		for axis: String in ["x", "y", "z"]:
			var transverse := segment_transverse_constraints_enabled and axis != "x"
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, transverse)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -segment_transverse_slack)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, segment_transverse_slack)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, false)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR, false)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, segment_rotation_constraints_enabled and axis != "z")
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
		if created:
			joints.add_child(joint)
			joint.owner = _scene_owner()
		joint.call("capture_reference")

func _append_part(parts: Array[Dictionary], node_name: String, role: String, size: Vector3, transform: Transform3D) -> int:
	parts.append({"name": node_name, "part_key": node_name, "role": role, "size": size, "transform": transform})
	return parts.size() - 1

func _add_connection(connections: Array[Dictionary], first: int, second: int, anchor: Vector3, kind: String, basis: Basis = Basis.IDENTITY) -> void:
	connections.append({"a": first, "b": second, "anchor": anchor, "kind": kind, "basis": basis})

## Equal decay gives nearest-X ownership; merged regions use the strongest member.
func _partition_torso_graph(parts: Array[Dictionary], indices: Array[int], _edges: Array[Dictionary]) -> Array[int]:
	var seeds: Array[int] = []
	var minimum := INF
	var maximum := -INF
	for index: int in range(indices.size()):
		var part: Dictionary = parts[indices[index]]
		var box := GEOMETRY.box(part.size, part.transform)
		minimum = minf(minimum, box.aabb.position.x)
		maximum = maxf(maximum, box.aabb.end.x)
		if bool(part.get("sub_torso", false)): seeds.append(index)
	if seeds.is_empty(): seeds.append(0)
	var parents: Array[int] = []
	for index: int in range(seeds.size()): parents.append(index)
	var threshold := maxf(maximum - minimum, 0.001) * segment_merge_length_percent / 100.0
	for first: int in range(seeds.size()):
		for second: int in range(first):
			var x_a: float = parts[indices[seeds[first]]].transform.origin.x
			var x_b: float = parts[indices[seeds[second]]].transform.origin.x
			if not segmented_torso_enabled or absf(x_a - x_b) < threshold:
				parents[_root(parents, first)] = _root(parents, second)
	var region_ids: Dictionary = {}
	for index: int in range(seeds.size()):
		var root_id := _root(parents, index)
		if not region_ids.has(root_id): region_ids[root_id] = region_ids.size()
	var owners: Array[int] = []
	var decay := maxf((maximum - minimum) * segment_weight_decay_ratio, 0.001)
	for index: int in range(indices.size()):
		var best_log_weight := -INF
		var owner := 0
		for seed: int in range(seeds.size()):
			var delta: float = absf(parts[indices[index]].transform.origin.x - parts[indices[seeds[seed]]].transform.origin.x)
			# Compare logarithms to avoid exponential underflow; ties use seed order.
			var log_weight := -delta / decay
			if log_weight > best_log_weight:
				best_log_weight = log_weight
				owner = region_ids[_root(parents, seed)]
		owners.append(owner)
		parts[indices[index]]["segment_id"] = owner
	return owners

## Supplement same-region edges so X-only assignment cannot leave a fragmented rigid segment.
func _complete_segment_edges(parts: Array[Dictionary], indices: Array[int], owners: Array[int], edges: Array[Dictionary]) -> void:
	for first: int in range(indices.size()):
		for second: int in range(first):
			if owners[first] != owners[second]: continue
			var exists := false
			for edge: Dictionary in edges:
				if (edge.a == first and edge.b == second) or (edge.b == first and edge.a == second): exists = true; break
			if exists: continue
			var a := GEOMETRY.box(parts[indices[first]].size, parts[indices[first]].transform)
			var b := GEOMETRY.box(parts[indices[second]].size, parts[indices[second]].transform)
			var points := _nearest_box_points(a.aabb, b.aabb)
			edges.append({"a": first, "b": second, "anchor": (points[0] + points[1]) * 0.5, "distance": points[0].distance_squared_to(points[1])})
	edges.sort_custom(_body_edge_less)

func _body_edge_less(a: Dictionary, b: Dictionary) -> bool:
	var first_required: bool = a.get("required", false)
	var second_required: bool = b.get("required", false)
	if first_required != second_required: return first_required
	return a.distance < b.distance

func _build_blueprint(plan: Dictionary, connection_distance: float) -> Dictionary:
	var parts: Array[Dictionary] = []
	var connections: Array[Dictionary] = []
	var torso_indices: Array[int] = []
	var torso_boxes: Array[Dictionary] = []
	for key: String in ["torsos", "network_torsos"]:
		var layouts: Array = plan[key]
		for index: int in range(layouts.size()):
			var layout: Dictionary = layouts[index]
			var node_name := ("SubTorso" if key == "torsos" else "Torso") + ("" if index == 0 else "_%d" % [index + 1])
			var transform := Transform3D(layout.get("basis", Basis.IDENTITY), layout.position)
			torso_indices.append(_append_part(parts, node_name, "Torso", layout.size, transform))
			parts.back()["sub_torso"] = bool(layout.get("sub_torso", key == "torsos"))
			torso_boxes.append(GEOMETRY.box(layout.size, transform))
	if torso_indices.is_empty():
		return {}
	var separate_supports: bool = plan.get("separate_subtorsos", false)
	var support_count: int = plan.torsos.size() if separate_supports else 0
	# Kruskal: connect only legal body neighbors, with N-1 links instead of redundant loops.
	var candidates: Array[Dictionary] = []
	for first: int in range(torso_boxes.size()):
		for second: int in range(first):
			var connected := GEOMETRY.connected(torso_boxes[first], torso_boxes[second], maxf(connection_distance, 0.0))
			if separate_supports and second < support_count:
				# Independent supports may be separated from the body shell. Their rigid attachment
				# is intentional, and must not depend on the surface-distance cutoff.
				connected = first >= support_count and first - support_count == int(plan.torsos[second].parent_torso_index)
			if connected:
				var points := _nearest_box_points(torso_boxes[first].aabb, torso_boxes[second].aabb)
				candidates.append({"a": first, "b": second, "anchor": (points[0] + points[1]) * 0.5, "distance": points[0].distance_squared_to(points[1]), "required": separate_supports and second < support_count})
	candidates.sort_custom(_body_edge_less)
	var segments := _partition_torso_graph(parts, torso_indices, candidates)
	if segments.is_empty(): return {}
	if separate_supports:
		# A support belongs to its attached Torso's segment. This prevents multiple feet
		# attached to one body block from introducing springs inside that rigid unit.
		for support: int in range(support_count):
			var parent: int = support_count + int(plan.torsos[support].parent_torso_index)
			segments[support] = segments[parent]
			parts[torso_indices[support]]["segment_id"] = segments[parent]
	_complete_segment_edges(parts, torso_indices, segments, candidates)
	# First build a rigid tree inside every segment, then a tree between segments.
	var parents: Array[int] = []
	for index: int in range(torso_indices.size()): parents.append(index)
	var body_links := 0
	for cross_segment: bool in [false, true]:
		for edge: Dictionary in candidates:
			var crosses: bool = segments[edge.a] != segments[edge.b]
			if crosses != cross_segment: continue
			var first := _root(parents, edge.a)
			var second := _root(parents, edge.b)
			if first == second: continue
			parents[first] = second
			_add_connection(connections, torso_indices[edge.a], torso_indices[edge.b], edge.anchor, "Segment" if crosses else "Torso")
			body_links += 1
	if body_links != torso_indices.size() - 1: return {}
	var counts := {"Leg": 0, "ForeLeg": 0}
	for layout: Dictionary in plan.layouts:
		var role: String = layout.role
		counts[role] += 1
		var node_name := "%s_%d" % [role, counts[role]]
		if separate_supports and layout.has("sub_torso_index"):
			parts[torso_indices[int(layout.sub_torso_index)]]["part_key"] = "SubTorso_" + node_name
		var size: Vector3 = layout.size
		var horizontal: Vector2 = layout.final_position
		var position := Vector3(horizontal.x, size.y * 0.5, horizontal.y)
		var previous := _append_part(parts, node_name, role, size, Transform3D(Basis.IDENTITY, position))
		var points: PackedVector3Array = layout.limb_points
		for index: int in range(points.size() - 1):
			var start := position + points[index]
			var end := position + points[index + 1]
			var direction := end - start
			var basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
			var block_size: Vector3 = layout.limb_block_sizes[index]
			var next := _append_part(parts, "%s_Limb_%d" % [node_name, index + 1], "Limb", block_size, Transform3D(basis, (start + end) * 0.5))
			parts[next]["connector_span"] = direction.length()
			_add_connection(connections, previous, next, start, "Limb", basis)
			previous = next
		var tip := position + points[-1]
		var nearest := _nearest_torso(tip, torso_indices, torso_boxes)
		if separate_supports and layout.has("sub_torso_index"):
			var support: int = layout.sub_torso_index
			nearest = {"index": torso_indices[support], "point": tip}
		_add_connection(connections, int(nearest.index), previous, (tip + Vector3(nearest.point)) * 0.5, "Limb")
	for index: int in range(plan.necks.size()):
		var neck: Dictionary = plan.necks[index]
		var points: PackedVector3Array = neck.points
		var neck_indices: Array[int] = torso_indices.slice(support_count)
		var neck_boxes: Array[Dictionary] = torso_boxes.slice(support_count)
		var nearest := _nearest_torso(points[0], neck_indices, neck_boxes)
		var previous: int = nearest.index
		for segment: int in range(neck.blocks.size()):
			var block: Dictionary = neck.blocks[segment]
			var is_head: bool = block.name == "Head"
			var node_name := "Head_%d" % [index + 1] if is_head else "Neck_%d_%d" % [index + 1, segment + 1]
			var next := _append_part(parts, node_name, "Head" if is_head else "Neck", block.size, Transform3D(block.basis, block.position))
			var anchor := points[mini(segment, points.size() - 1)]
			if segment == 0:
				anchor = (anchor + Vector3(nearest.point)) * 0.5
			_add_connection(connections, previous, next, anchor, "Neck", block.basis)
			previous = next
	# Bake size into geometry/positions; rigid bodies and joint bases retain unit scale.
	for index: int in range(plan.get("wings",[]).size()):
		var wing: Dictionary = plan.wings[index]
		var previous: int = torso_indices[support_count+int(wing.parent_torso_index)]
		for segment: int in range(wing.blocks.size()):
			var block: Dictionary = wing.blocks[segment]
			var tip: bool = segment == wing.blocks.size()-1
			var next := _append_part(parts,"Wing_%d_%s_%d" % [index+1,block.get("section","Segment"),segment+1],"Wing" if tip else "WingLimb",block.size,Transform3D(block.basis,block.position))
			parts[next]["wing_section"] = str(block.get("section", ""))
			# Expanded sections align with the wing root within its generated XY plane.
			parts[next]["wing_open_basis"] = wing.blocks[0].basis
			_add_connection(connections,previous,next,wing.points[segment],"Wing",block.basis)
			for feather_index: int in range(block.get("feathers",[]).size()):
				var feather: Dictionary = block.feathers[feather_index]
				var wing_transform := Transform3D(block.basis,block.position)
				var feather_root: Transform3D = wing_transform * Transform3D(feather.transform)
				var torso_basis: Basis = parts[torso_indices[support_count+int(wing.parent_torso_index)]].transform.basis
				var folded_root := Transform3D(torso_basis*Basis(Vector3.BACK,PI*0.5),feather_root.origin)
				var center := folded_root * Transform3D(Basis.IDENTITY,Vector3(0,feather.size.y*0.5,0))
				var feather_part := _append_part(parts,"Feather_%d_%d_%03d" % [index+1,segment+1,feather_index+1],"Feather",feather.size,center)
				parts[feather_part]["feather_color"] = feather.get("color",Color.WHITE)
				parts[feather_part]["feather_open_basis"] = feather_root.basis
				_add_connection(connections,next,feather_part,feather_root.origin,"Feather",block.basis)
			previous = next
	var multiplier: float = plan.get(&"overall_scale", 1.0)
	for part: Dictionary in parts:
		part.size *= multiplier
		if part.has("connector_span"): part.connector_span *= multiplier
		var transform: Transform3D = part.transform
		transform.origin *= multiplier
		part.transform = transform
	for connection: Dictionary in connections:
		connection.anchor *= multiplier
	return {"parts": parts, "connections": connections, "overall_scale": multiplier, "create_connection_markers": plan.get("create_connection_markers",false)}

func _root(parents: Array[int], index: int) -> int:
	while parents[index] != index:
		index = parents[index]
	return index

func _nearest_box_points(first: AABB, second: AABB) -> PackedVector3Array:
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	for axis: int in range(3):
		if first.end[axis] < second.position[axis]:
			a[axis] = first.end[axis]
			b[axis] = second.position[axis]
		elif second.end[axis] < first.position[axis]:
			a[axis] = first.position[axis]
			b[axis] = second.end[axis]
		else:
			a[axis] = (maxf(first.position[axis], second.position[axis]) + minf(first.end[axis], second.end[axis])) * 0.5
			b[axis] = a[axis]
	return PackedVector3Array([a, b])

func _nearest_torso(point: Vector3, indices: Array[int], boxes: Array[Dictionary]) -> Dictionary:
	var result := {"index": indices[0], "point": Vector3.ZERO}
	var distance := INF
	for index: int in range(boxes.size()):
		var bounds: AABB = boxes[index].aabb
		var closest := point.clamp(bounds.position, bounds.end)
		if closest.is_equal_approx(point):
			var face_distance := INF
			for axis: int in range(3):
				for face: float in [bounds.position[axis], bounds.end[axis]]:
					var next := absf(point[axis] - face)
					if next < face_distance:
						face_distance = next
						closest = point
						closest[axis] = face
		var next := point.distance_squared_to(closest)
		if next < distance:
			distance = next
			result = {"index": indices[index], "point": closest}
	return result

func _get_generated_part_type(layout: Dictionary) -> String:
	if bool(layout.get("sub_torso", false)): return "SubTorso"
	var role := str(layout.role)
	if role == "Limb": return "LegLimb"
	if role == "Wing" or role == "WingLimb":
		var section := str(layout.get("wing_section", ""))
		if section in ["Root", "Middle", "Tip"]: return "Wing" + section
	return role

func _instantiate_blueprint(blueprint: Dictionary, generator_transform: Transform3D) -> Node3D:
	var container := Node3D.new()
	var bodies: Array[RigidBody3D] = []
	for layout: Dictionary in blueprint.parts:
		var rule: Resource = layout.get("scene_rule")
		var scene: PackedScene = PART_SCENE if rule == null else rule.part_scene
		var instance: Node = scene.instantiate() if scene != null else null
		var part := instance as PhysicalBodyPart3D
		if part == null:
			if instance != null: instance.free()
			push_warning("[generated_creature] Invalid Part scene for %s; previous physics retained." % layout.name)
			container.free()
			return null
		if not part.scale.is_equal_approx(Vector3.ONE):
			push_warning("[generated_creature] Part %s must have unit root scale; use the scene rule's Size Multiplier." % layout.name)
			part.free()
			container.free()
			return null
		part.name = layout.name
		part.freeze = true
		part.transform = generator_transform * Transform3D(layout.transform)
		var size: Vector3 = layout.size
		if rule == null:
			part.left_distance = size.x * 0.5
			part.right_distance = size.x * 0.5
			part.top_distance = size.y * 0.5
			part.bottom_distance = size.y * 0.5
			part.collision_thickness = size.z
			part.sprite_visible = false
			part.mesh_visible = true
		else:
			var fit_size := size
			if rule.align_connectors_to_frame and layout.role == "Limb":
				fit_size.y = float(layout.get("connector_span", size.y))
			var actual := PART_GEOMETRY.fit(part, fit_size, rule, str(layout.role), float(blueprint.get("paper_depth", fit_size.z)))
			if actual.size == Vector3.ZERO:
				push_warning("[generated_creature] Part %s requires a valid Box/Convex CollisionShape3D and positive scale; previous physics retained." % layout.name)
				part.free()
				container.free()
				return null
			size = actual.size
			part.set_meta(&"generated_scene_path", scene.resource_path)
			part.set_meta(&"generated_scene_rule_key", rule.part_name if not rule.part_name.is_empty() else rule.part_type)
		if layout.role == "Feather" and rule == null:
			var mesh := part.get_node("MeshInstance3D") as MeshInstance3D
			mesh.mesh = FEATHER_GEOMETRY.create_mesh(size)
			var material := StandardMaterial3D.new()
			material.albedo_color = layout.get("feather_color",Color.WHITE)
			material.roughness = 0.9
			mesh.material_override = material
		var part_type := _get_generated_part_type(layout)
		var density := mass_density if density_data == null else density_data.get_density(part_type, mass_density)
		var minimum_mass := minimum_feather_mass if layout.role == "Feather" else minimum_part_mass
		var calculated_mass := size.x * size.y * size.z * density
		part.mass = clampf(calculated_mass, minimum_mass, maximum_part_mass) if mass_limits_enabled else calculated_mass
		part.linear_damp = part_linear_damping
		part.angular_damp = part_angular_damping
		# Preserve authored tags and health/armor; required generated tags are added once.
		var authored_tags: Array = part.tags.duplicate() if rule != null else []
		part.tags = []
		match layout.role:
			"Torso": part.tags.append(BODY_PART.BodyPartTag.Torso)
			"Leg": part.tags.append(BODY_PART.BodyPartTag.Leg)
			"ForeLeg": part.tags.append(BODY_PART.BodyPartTag.ForeLeg)
			"Limb": part.tags.append(BODY_PART.BodyPartTag.LegLimb)
			"Wing": part.tags.append(BODY_PART.BodyPartTag.Wing)
			"WingLimb":
				part.tags.append(BODY_PART.BodyPartTag.Wing)
				part.tags.append(BODY_PART.BodyPartTag.WingLimb)
			"Head": part.tags.append(BODY_PART.BodyPartTag.Head)
			"Feather": part.tags.append(BODY_PART.BodyPartTag.Feather)
			"Tail": part.tags.append(BODY_PART.BodyPartTag.Tail)
			"Horn": part.tags.append(BODY_PART.BodyPartTag.Horn)
		if bool(layout.get("sub_torso", false)): part.tags.append(BODY_PART.BodyPartTag.SubTorso)
		for tag: int in authored_tags:
			if tag not in part.tags: part.tags.append(tag)
		if layout.has("segment_id"): part.set_meta(&"body_segment_id", int(layout.segment_id))
		if layout.has("segment_id"): part.set_meta(&"segment_layout_version", 3)
		var saved_layout := layout.duplicate(true)
		saved_layout.erase("scene_rule")
		part.set_meta(&"generated_layout", saved_layout)
		part.set_meta(&"generated_role", layout.role)
		part.set_meta(&"generated_part_key", layout.get("part_key", layout.name))
		part.set_meta(&"generated_part_type", part_type)
		part.set_meta(&"generated_density", density)
		part.set_meta(&"generated_size", size)
		part.set_meta(&"generated_framework_size", layout.size)
		container.add_child(part)
		bodies.append(part)
	var joints := Node3D.new()
	joints.name = "Joints"
	container.add_child(joints)
	for index: int in range(blueprint.connections.size()):
		var connection: Dictionary = blueprint.connections[index]
		if connection.kind == "Segment":
			var spring := SEGMENT_SPRING.new()
			spring.rest_reference_yaw = generator_transform.basis.get_euler().y
			spring.name = "SegmentSpring_%03d" % [index + 1]
			spring.node_a = NodePath("../../" + str(bodies[connection.a].name))
			spring.node_b = NodePath("../../" + str(bodies[connection.b].name))
			spring.enabled = segment_translation_springs_enabled
			spring.frequency = segment_spring_frequency
			spring.damping_ratio = segment_spring_damping_ratio
			spring.maximum_acceleration = segment_spring_maximum_acceleration
			spring.maximum_distance_lock_enabled = segment_maximum_distance_lock_enabled
			spring.maximum_distance_ratio = segment_maximum_distance_ratio
			joints.add_child(spring)
			continue
		var joint := Generic6DOFJoint3D.new()
		joint.name = "Joint_%03d_%s" % [index + 1, connection.kind]
		joint.transform = generator_transform * Transform3D(connection.basis, connection.anchor)
		joint.set_meta(&"generated_connection_kind", connection.kind)
		joint.exclude_nodes_from_collision = true
		var a: RigidBody3D = bodies[connection.a]
		var b: RigidBody3D = bodies[connection.b]
		var anchor_a := joint.position
		var anchor_b := joint.position
		var rule_a: Resource = blueprint.parts[connection.a].get("scene_rule")
		var rule_b: Resource = blueprint.parts[connection.b].get("scene_rule")
		if not blueprint.get("manual_layout", false) and rule_a != null and rule_a.use_joint_markers: anchor_a = PART_GEOMETRY.connection_marker(a, anchor_a)
		if not blueprint.get("manual_layout", false) and rule_b != null and rule_b.use_joint_markers: anchor_b = PART_GEOMETRY.connection_marker(b, anchor_b)
		joint.position = (anchor_a + anchor_b) * 0.5
		if blueprint.get("create_connection_markers",false):
			var parent_body := a
			var child_body := b
			# Limb chains are stored foot-to-root; expose ports in the anatomical root-to-foot direction.
			if connection.kind == "Limb" and (blueprint.parts[connection.a].role in ["Leg","ForeLeg"] or (blueprint.parts[connection.a].role == "Limb" and blueprint.parts[connection.b].role == "Limb")):
				parent_body = b
				child_body = a
			_add_connection_port(parent_body,"JointOut_" + str(child_body.name),joint.position,str(joint.name),str(child_body.name))
			_add_connection_port(child_body,"JointIn_" + str(parent_body.name),joint.position,str(joint.name),str(parent_body.name))
		# Keep the generated rest pose across gait-cache refreshes and participation changes.
		var rest_a := a.basis.orthonormalized().get_rotation_quaternion()
		var rest_b := b.basis.orthonormalized().get_rotation_quaternion()
		joint.set_meta(&"generated_rest_b_relative_a", rest_a.inverse() * rest_b)
		joint.set_meta(&"generated_joint_frame_a", a.transform.affine_inverse()*joint.transform)
		joint.set_meta(&"generated_joint_frame_b", b.transform.affine_inverse()*joint.transform)
		if connection.kind == "Feather":
			var open_basis: Basis = blueprint.parts[connection.b].feather_open_basis
			var wing_basis: Basis = blueprint.parts[connection.a].transform.basis
			joint.set_meta(&"feather_open_relative_a", (wing_basis.inverse()*open_basis).get_rotation_quaternion())
		if connection.kind == "Wing":
			var open_a: Basis = blueprint.parts[connection.a].get("wing_open_basis", a.basis)
			var open_b: Basis = blueprint.parts[connection.b].wing_open_basis
			# Root Torso and open wing bases must share the generator's coordinate system.
			if not blueprint.parts[connection.a].has("wing_open_basis"):
				open_a = blueprint.parts[connection.a].transform.basis
			joint.set_meta(&"wing_open_relative_a", (open_a.orthonormalized().inverse() * open_b.orthonormalized()).get_rotation_quaternion())
		joint.node_a = NodePath("../../" + str(a.name))
		joint.node_b = NodePath("../../" + str(b.name))
		var angle := 0.0 if connection.kind == "Torso" else deg_to_rad(neck_angular_limit_degrees if connection.kind == "Neck" else limb_angular_limit_degrees)
		for axis: String in ["x", "y", "z"]:
			var locked_limb_axis: bool = axis != "z" and BODY_PART.BodyPartTag.LegLimb in a.tags and BODY_PART.BodyPartTag.LegLimb in b.tags
			locked_limb_axis = locked_limb_axis or (axis == "y" and _is_limb_subtorso_pair(a, b))
			var axis_angle := 0.0 if locked_limb_axis else angle
			if connection.kind in ["Wing","Feather"]: axis_angle = PI if axis == "z" else 0.0
			if connection.kind == "Tail": axis_angle = deg_to_rad(tail_joint_angular_limit_degrees) if axis == "z" else 0.0
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -axis_angle)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, axis_angle)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, connection.kind not in ["Torso", "Wing", "Feather"] and not locked_limb_axis and BODY_PART.BodyPartTag.LegLimb not in a.tags and BODY_PART.BodyPartTag.LegLimb not in b.tags)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, angular_spring_stiffness)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, angular_spring_damping)
			if connection.kind == "Tail":
				joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, axis == "z")
				joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, tail_joint_spring_stiffness)
				joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, tail_joint_spring_damping)
		if connection.kind == "Wing":
			_configure_wing_joint_limits(joint, str(blueprint.parts[connection.b].get("wing_section", "Root")))
		if BODY_PART.BodyPartTag.LegLimb in a.tags and BODY_PART.BodyPartTag.LegLimb in b.tags:
			_configure_limb_joint_sliding(joint)
		joints.add_child(joint)
	return container

func _add_connection_port(body: RigidBody3D, port_name: String, anchor: Vector3, joint_name: String, other_name: String) -> void:
	var marker := Marker3D.new()
	marker.name = port_name
	marker.position = body.transform.affine_inverse() * anchor
	marker.set_meta(&"generated_connection_port",true)
	marker.set_meta(&"joint_name",joint_name)
	marker.set_meta(&"connected_part",other_name)
	body.add_child(marker)

func _configure_wing_joint_limits(joint: Generic6DOFJoint3D, section: String) -> void:
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, wing_joint_limits_enabled)
	if not wing_joint_limits_enabled: return
	var margin_degrees := wing_root_limit_margin_degrees
	if section == "Middle": margin_degrees = wing_middle_limit_margin_degrees
	elif section == "Tip": margin_degrees = wing_tip_limit_margin_degrees
	var margin := deg_to_rad(clampf(margin_degrees, 0.0, 90.0)) if is_finite(margin_degrees) else 0.0
	var closed: Quaternion = joint.get_meta(&"generated_rest_b_relative_a")
	var opened: Quaternion = joint.get_meta(&"wing_open_relative_a")
	# Joint frames coincide at creation. Their relative angle is the negative of B's
	# rotation from rest; both generated endpoints must stay inside the allowed arc.
	var delta := Basis(closed.inverse() * opened)
	var open_angle := -atan2(delta.x.y, delta.x.x)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, maxf(-PI, minf(0.0, open_angle) - margin))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, minf(PI, maxf(0.0, open_angle) + margin))

func set_control_performance_tracking_enabled(enabled: bool) -> void:
	_ensure_control_performance_stats()
	_control_perf.set_enabled(enabled)

func consume_control_performance_stats() -> Dictionary:
	_ensure_control_performance_stats()
	return _control_perf.consume()
