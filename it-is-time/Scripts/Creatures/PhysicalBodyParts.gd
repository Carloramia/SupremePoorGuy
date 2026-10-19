@tool
class_name PhysicalBodyPart3D
extends RigidBody3D

signal damaged(amount: float, remaining_hp: float, source: Node)
signal broken(source: Node)
signal slipping_changed(value: bool)
signal visual_state_changed(state: StringName)

const OUTLINE_SHADER: Shader = preload("res://Shaders/BodyPartOutline.gdshader")
const DEFAULT_DAMAGE_NUMBER_SCENE: PackedScene = preload("res://Scenes/VFX/DamageNumber3D.tscn")
const MIN_SIZE: float = 0.001
const VISUAL_SWITCHER = preload("res://Scripts/Creatures/BodyPartVisualSwitcher3D.gd")
const COLLISION_DEPTH_MULTIPLIER: float = 2.0
const COLLISION_DEPTH_META: StringName = &"body_part_collision_depth_multiplier"

enum BodyPartTag {
	Torso,
	Leg,
	Arm,
	Head,
	# Append to preserve existing serialized Torso/Leg/Arm/Head indices.
	ForeLeg,
	LegLimb,
	SubTorso,
	Wing, # All wing blocks; intermediate blocks additionally carry WingLimb.
	WingLimb,
	Feather,
	Tail,
	Horn,
	ArmLimb, # Append: existing serialized tag values remain unchanged.
}

@export_group("Classification")
## A part may carry more than one classification tag.
@export var tags: Array[BodyPartTag] = []:
	set(value):
		tags = value
		if is_node_ready() and not Engine.is_editor_hint():
			call_deferred("_sync_limb_terrain_collisions")

@export_group("Foot Ground State")
## LegLimb terrain filtering; characters may restore ground collisions without changing tags.
@export var ignore_limb_terrain: bool = true:
	set(value):
		ignore_limb_terrain = value
		if is_node_ready() and not Engine.is_editor_hint(): call_deferred("_sync_limb_terrain_collisions")
## External gameplay may enable slipping; an upright grounded foot is otherwise pinned.
@export var is_slipping: bool = false:
	set(value):
		if is_slipping == value: return
		is_slipping = value
		slipping_changed.emit(value)

@export_group("Foot Rotation Lock")
## World X/Z locks keep Leg and ForeLeg soles upright; Y stays available for turning.
@export var lock_foot_pitch_roll: bool = true:
	set(value):
		lock_foot_pitch_roll = value
		if is_node_ready(): sync_foot_rotation_lock()

@export_group("Arm Swing")
## Each entry assigns this part to one LimbSwingController3D control group.
## Only entries on parts carrying the Arm tag are loaded by the controller.
@export var arm_swing_bindings: Array[ArmSwingBinding] = []

@export_group("Head Position Support")
## Used by HeadPositionSupport3D only on Head-tagged parts outside planar mode.
@export var head_position_support_enabled: bool = true
@export_range(0.0, 200.0, 0.1) var head_position_gain: float = 120.0
@export_range(0.0, 100.0, 0.1) var head_position_damping: float = 22.0
@export_range(0.0, 200.0, 0.1) var head_no_neck_position_gain: float = 10.0
@export_range(0.0, 100.0, 0.1) var head_no_neck_position_damping: float = 6.0
## Maximum translation in either direction along each Head-Torso joint axis.
@export var head_no_neck_linear_slack: Vector3 = Vector3(0.06,0.06,0.06)
@export var head_gravity_compensation: bool = true
@export_range(0.0, 500.0, 0.1) var head_maximum_support_acceleration: float = 60.0

@export_group("Head Posture Damping")
## Preserve the initial orientation relative to the connected Torso, with soft torque.
@export var head_posture_damping_enabled: bool = true
@export_range(0.0, 200.0, 0.1) var head_posture_gain: float = 60.0
@export_range(0.0, 100.0, 0.1) var head_posture_damping: float = 16.0
@export_range(0.0, 500.0, 0.1) var head_maximum_angular_acceleration: float = 40.0
@export_range(0.0, 100000.0, 1.0) var head_maximum_posture_torque: float = 500.0

@export_group("Durability")
@export_range(1.0, 100000.0, 1.0, "or_greater") var max_hp: float = 100.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var armor: float = 10.0
## Percentage mitigation before fixed Armor: resilience / (resilience + 100).
@export_range(0.0, 10000.0, 0.1, "or_greater") var resilience: float = 0.0
## Runtime HP is derived from naked body mass using the global damage rules.
@export var mass_based_health: bool = true
var base_combat_mass: float = 0.0
@export var is_broken: bool = false:
	set(value):
		is_broken = value
		if is_node_ready() and not Engine.is_editor_hint():
			call_deferred("_sync_limb_terrain_collisions")
			if value: _start_broken_cleanup()
@export var damage_logging_enabled: bool = false

@export_group("Broken Cleanup")
@export_range(0.0, 60.0, 0.5, "or_greater") var broken_linger_duration: float = 10.0
@export_range(0.05, 5.0, 0.05, "or_greater") var broken_fade_duration: float = 1.0

@export_group("Damage Feedback")
@export var damage_number_scene: PackedScene = DEFAULT_DAMAGE_NUMBER_SCENE
@export var damage_number_offset: Vector3 = Vector3(0.0, 0.75, 0.0)

@export_group("Visuals")
enum GeometryMode { BOX_FIT, CUSTOM_MODEL }
## Custom models retain authored transforms, collision XY profiles and joint markers.
@export var geometry_mode: GeometryMode = GeometryMode.BOX_FIT:
	set(value):
		if is_instance_valid(_custom_model) and _custom_model != _mesh: _custom_model.visible = false
		geometry_mode = value
		_last_signature.clear()
		_custom_model = null
		if is_node_ready(): _sync_geometry()
## A Node3D or MeshInstance3D under this body; Mesh Visible controls its subtree.
@export_node_path("Node3D") var custom_model_path: NodePath = ^"MeshInstance3D":
	set(value):
		if is_instance_valid(_custom_model) and _custom_model != _mesh: _custom_model.visible = false
		custom_model_path = value
		_custom_model = null
		if is_node_ready(): _sync_visual_visibility()
@export var sprite_visible: bool = true:
	set(value):
		sprite_visible = value
		_sync_visual_visibility()
@export var mesh_visible: bool = true:
	set(value):
		mesh_visible = value
		_sync_visual_visibility()

@export_group("Visual States")
@export var visual_states: Array[BodyPartVisualState3D] = []
## Empty restores the authored model. Runtime calls do not change this saved default.
@export var initial_visual_state: StringName = &"":
	set(value):
		initial_visual_state = value
		if is_node_ready() and not Engine.is_editor_hint(): set_visual_state(value)
## Empty automatically chooses the custom PaperVolume, custom mesh or box mesh.
@export_node_path("MeshInstance3D") var visual_state_mesh_path: NodePath

@export_group("Paper Model Volume")
## Requires a baked PaperVolume mesh under the custom model. Off for ordinary body parts.
@export var paper_volume_enabled: bool = false:
	set(value):
		paper_volume_enabled = value
		if is_node_ready(): _sync_geometry()
## Full depth along local Z, centered on the original paper plane.
## Generated Custom paper parts fit depth to Part Width * Overall Scale independently of XY;
## authored thickness and the scene rule Size Multiplier do not change the final depth.
@export_range(0.001, 2.0, 0.005, "or_greater") var paper_volume_thickness: float = 0.08:
	set(value):
		paper_volume_thickness = maxf(value,MIN_SIZE)
		if is_node_ready(): _sync_geometry()
@export var paper_side_color: Color = Color(0.65,0.65,0.65):
	set(value):
		paper_side_color = value
		if is_node_ready(): _sync_geometry()

@export_group("BodyPart Edges")
## Distances from the Sprite3D's local origin, in Godot 3D units.
@export_range(0.001, 100.0, 0.01, "or_greater") var left_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var right_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var top_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var bottom_distance: float = 1.28

@export_group("Collision")
## Base model depth perpendicular to the Sprite3D plane. The collider's local Z depth is doubled.
@export_range(0.001, 100.0, 0.01, "or_greater") var collision_thickness: float = 0.2

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D

var _material: ShaderMaterial
var _custom_model: Node3D
var _paper_volume: MeshInstance3D
var _paper_source_meshes: Array[MeshInstance3D] = []
var _paper_side_material: StandardMaterial3D
var _paper_collision_shape: ConvexPolygonShape3D
var _paper_original_depth: float = 0.02
var _paper_signature: Array = []
var _last_signature: Array = []
var _visual_switcher := VISUAL_SWITCHER.new()
var current_hp: float = 100.0
var _damage_service: Node
var _collision_logging_enabled: bool = false
var _foot_contact_samples: Array[Dictionary] = []
var _ignored_limb_terrain: Array[StaticBody3D] = []
var _broken_cleanup_tween: Tween
var _broken_visuals: Array[Dictionary] = []

func _sync_limb_terrain_collisions() -> void:
	if not is_inside_tree() or Engine.is_editor_hint(): return
	var ignore_terrain := ignore_limb_terrain and BodyPartTag.LegLimb in tags and not is_broken
	var tree := get_tree()
	if not ignore_terrain:
		if tree.node_added.is_connected(_on_limb_terrain_added):
			tree.node_added.disconnect(_on_limb_terrain_added)
		for terrain: StaticBody3D in _ignored_limb_terrain:
			if is_instance_valid(terrain): remove_collision_exception_with(terrain)
		_ignored_limb_terrain.clear()
		return
	if not tree.node_added.is_connected(_on_limb_terrain_added):
		tree.node_added.connect(_on_limb_terrain_added)
	for terrain: Node in tree.root.find_children("*", "StaticBody3D", true, false):
		_on_limb_terrain_added(terrain)

func _on_limb_terrain_added(node: Node) -> void:
	if node is StaticBody3D and ignore_limb_terrain and not is_broken and BodyPartTag.LegLimb in tags:
		# Preserve exceptions owned by other systems when restoring terrain collisions.
		if node not in get_collision_exceptions():
			add_collision_exception_with(node)
			_ignored_limb_terrain.append(node)

## Actual solver impulses, not the movement controller's commanded force.
func _record_foot_contacts(state: PhysicsDirectBodyState3D) -> void:
	if BodyPartTag.Leg not in tags and BodyPartTag.ForeLeg not in tags: return
	var frame := Engine.get_physics_frames()
	while not _foot_contact_samples.is_empty() and int(_foot_contact_samples[0].frame) < frame-4:
		_foot_contact_samples.pop_front()
	var contacts: Dictionary = {}
	for index: int in range(state.get_contact_count()):
		if SampleWeapon3D.from_contact(self,state.get_contact_local_shape(index)) != null: continue
		var id := state.get_contact_collider_id(index)
		var impulse := state.get_contact_impulse(index).length()
		if not contacts.has(id): contacts[id] = {"frame":frame,"collider_id":id,"impulse":0.0,"weighted_position":Vector3.ZERO}
		contacts[id].impulse += impulse
		contacts[id].weighted_position += state.get_contact_collider_position(index)*impulse
	for sample: Dictionary in contacts.values():
		sample["position"] = sample.weighted_position/maxf(float(sample.impulse),0.000001)
		_foot_contact_samples.append(sample)

## Peak single-tick contact-manifold impulse within the touchdown window.
func get_foot_contact_impact(collider: Object, since_frame: int) -> Dictionary:
	var best: Dictionary = {}
	if not is_instance_valid(collider): return best
	for sample: Dictionary in _foot_contact_samples:
		if int(sample.frame) >= since_frame and int(sample.collider_id) == collider.get_instance_id() and float(sample.impulse) > float(best.get("impulse",0.0)):
			best = sample.duplicate()
	return best

func _ready() -> void:
	sync_foot_rotation_lock()
	if not Engine.is_editor_hint():
		base_combat_mass = mass
		if mass_based_health: max_hp = preload("res://Resources/Damage/DefaultDamageRules.tres").health_for_mass(base_combat_mass)
	current_hp = 0.0 if is_broken else max_hp
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 8)
	add_to_group(&"damage_components")
	_damage_service = get_node_or_null("/root/DamageService")
	if _damage_service == null:
		push_warning("DamageService Autoload is unavailable; impulse damage is disabled.")
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console != null and console.has_method("is_damage_tracking_enabled"):
		damage_logging_enabled = bool(console.call("is_damage_tracking_enabled"))
	_sync_geometry()
	if not Engine.is_editor_hint() and not initial_visual_state.is_empty(): set_visual_state(initial_visual_state)
	if not Engine.is_editor_hint():
		add_to_group(&"physical_body_parts")
		call_deferred("_sync_limb_terrain_collisions")
		body_entered.connect(_on_collision_body_entered)
		body_exited.connect(_on_collision_body_exited)
		if console != null and console.has_method("is_collision_tracking_enabled"):
			set_collision_logging_enabled(bool(console.call("is_collision_tracking_enabled")))
		if is_broken: _start_broken_cleanup()

func set_collision_logging_enabled(enabled: bool) -> void:
	_collision_logging_enabled = enabled
	if enabled and is_inside_tree() and not Engine.is_editor_hint():
		# The parent adds pairwise exceptions after the BodyParts are ready.
		call_deferred("emit_collision_snapshot")

func is_collision_logging_enabled() -> bool:
	return _collision_logging_enabled

func emit_collision_snapshot() -> void:
	if not _collision_logging_enabled or not is_inside_tree():
		return
	var exceptions: Array[String] = []
	for body: PhysicsBody3D in get_collision_exceptions():
		if is_instance_valid(body):
			var body_path := str(body.get_path()) if body.is_inside_tree() else str(body.name)
			if body_path not in exceptions:
				exceptions.append(body_path)
	var contacts: Array[String] = []
	for body: Node3D in get_colliding_bodies():
		if is_instance_valid(body):
			contacts.append(str(body.get_path()))
	var shapes: Array[Dictionary] = []
	for child: Node in get_children():
		if child is CollisionShape3D:
			var collision := child as CollisionShape3D
			shapes.append({"name": str(child.name), "disabled": collision.disabled, "has_shape": collision.shape != null})
	var joints: Array[Dictionary] = []
	for node: Node in get_parent().find_children("*", "Joint3D", true, false):
		var joint := node as Joint3D
		if joint.is_queued_for_deletion():
			continue
		var a := joint.get_node_or_null(joint.node_a)
		var b := joint.get_node_or_null(joint.node_b)
		if a == self or b == self:
			joints.append({"name": str(joint.name), "exclude_collision": joint.exclude_nodes_from_collision})
	print("[part_collision_config] part=%s layer=%d mask=%d monitor=%s max_contacts=%d broken=%s shapes=%s exceptions=%s joints=%s contacts=%s" % [
		get_path(), collision_layer, collision_mask, contact_monitor, max_contacts_reported,
		is_broken, shapes, exceptions, joints, contacts
	])

func _on_collision_body_entered(body: Node3D) -> void:
	_log_collision_event("enter", body)

func _on_collision_body_exited(body: Node3D) -> void:
	_log_collision_event("exit", body)

func _log_collision_event(event_name: String, body: Node3D) -> void:
	if not _collision_logging_enabled or not is_inside_tree() or not is_instance_valid(body):
		return
	var other := body as PhysicsBody3D
	var ignored := false
	if other != null:
		ignored = other in get_collision_exceptions() or self in other.get_collision_exceptions()
	print("[part_collision] event=%s part=%s other=%s other_is_part=%s same_character=%s ignored=%s position=%s velocity=%s broken=%s" % [
		event_name, get_path(), body.get_path() if body.is_inside_tree() else body.name, body is PhysicalBodyPart3D,
		body is PhysicalBodyPart3D and body.get_parent() == get_parent(),
		ignored, global_position, linear_velocity, is_broken
	])

## Opt-in solver contact cache. Ordinary creatures do not pay for this scan.
var surface_contact_tracking: bool = false
## Snake support must come from terrain/platforms, not from another creature or item.
var surface_contact_terrain_only: bool = false
var _support_surface_contact: Dictionary = {}

func get_support_surface_contact() -> Dictionary:
	if not surface_contact_tracking or is_broken: return {}
	if Engine.get_physics_frames() > int(_support_surface_contact.get("frame", -10)) + 1:
		# Sleeping bodies stop integration callbacks; retain their still-existing solver contact.
		if not sleeping or _support_surface_contact.is_empty(): return {}
		var collider := instance_from_id(int(_support_surface_contact.collider_id)) as Node3D
		if not is_instance_valid(collider) or not collider.is_inside_tree() or collider not in get_colliding_bodies(): return {}
	return _support_surface_contact

func _record_support_surface(state: PhysicsDirectBodyState3D) -> void:
	_support_surface_contact = {}
	var gravity := state.total_gravity
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	var best := 0.5
	for index: int in state.get_contact_count():
		var collider := state.get_contact_collider_object(index)
		if collider == null or (collider is PhysicalBodyPart3D and collider.get_parent() == get_parent()): continue
		if surface_contact_terrain_only and not (collider is StaticBody3D or collider is AnimatableBody3D): continue
		var normal := state.get_contact_local_normal(index).normalized()
		var alignment := normal.dot(up)
		if alignment < best: continue
		best = alignment
		_support_surface_contact = {"frame": Engine.get_physics_frames(), "normal": normal,
			"position": state.get_contact_collider_position(index),
			"velocity": state.get_contact_collider_velocity_at_position(index),
			"collider_id": state.get_contact_collider_id(index)}

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if Engine.is_editor_hint() or is_broken:
		return
	_record_foot_contacts(state)
	if surface_contact_tracking: _record_support_surface(state)
	var weapon_impulses: Dictionary = {}
	for contact_index: int in range(state.get_contact_count()):
		# Hits against the held weapon geometry do not damage the holder's own body part.
		if SampleWeapon3D.from_contact(self, state.get_contact_local_shape(contact_index)) != null:
			continue
		var weapon := SampleWeapon3D.from_contact(
			state.get_contact_collider_object(contact_index), state.get_contact_collider_shape(contact_index))
		if weapon == null or _is_friendly_weapon(weapon):
			continue
		var impulse := state.get_contact_impulse(contact_index).length()
		weapon_impulses[weapon] = maxf(float(weapon_impulses.get(weapon, 0.0)), impulse)
	for weapon: SampleWeapon3D in weapon_impulses:
		weapon.apply_contact_damage(self, float(weapon_impulses[weapon]))

func apply_damage(amount: float, source: Node = null) -> float:
	if get_meta(&"summon_presentation",false) or is_broken or amount <= 0.0: return 0.0
	var character := preload("res://Scripts/Player/PlayerControlContext.gd").character_of(self)
	if character != null and character.has_method("distribute_part_damage"):
		return character.distribute_part_damage(self, amount, source)
	return apply_local_damage(amount, source)

## Final HP settlement for an already calculated share; bypasses further redistribution.
func apply_local_damage(amount: float, source: Node = null) -> float:
	if get_meta(&"summon_presentation",false): return 0.0
	if is_broken or amount <= 0.0:
		return 0.0
	var applied := minf(amount, current_hp)
	current_hp = maxf(current_hp - applied, 0.0)
	damaged.emit(applied, current_hp, source)
	if applied > 0.0: CombatAudio3D.play_at(self, &"hit")
	if is_inside_tree():
		call_deferred("_spawn_damage_number", applied, global_position)
	if damage_logging_enabled:
		print(
			"[part_damage] target=%s amount=%.3f hp=%.3f/%.3f source=%s"
			% [name, applied, current_hp, max_hp, source.name if source != null else &"None"]
		)
	if is_zero_approx(current_hp):
		break_part(source)
	return applied

func _spawn_damage_number(amount: float, hit_position: Vector3) -> void:
	if amount <= 0.0 or not is_inside_tree():
		return
	var popup_scene := damage_number_scene if damage_number_scene != null else DEFAULT_DAMAGE_NUMBER_SCENE
	var popup := popup_scene.instantiate() as Node3D
	if popup == null:
		push_warning("Damage Number Scene must instantiate a Node3D.")
		return
	var scene_parent := preload("res://Scripts/Player/PlayerControlContext.gd").level(self)
	if scene_parent == null:
		scene_parent = get_tree().root
	scene_parent.add_child(popup)
	popup.global_position = hit_position + damage_number_offset
	if popup.has_method("setup_damage"):
		popup.call("setup_damage", amount)

func sync_foot_rotation_lock() -> void:
	var enabled := lock_foot_pitch_roll and not is_broken and (BodyPartTag.Leg in tags or BodyPartTag.ForeLeg in tags)
	if enabled:
		if not has_meta(&"foot_previous_locks"):
			set_meta(&"foot_previous_locks", Vector2i(int(axis_lock_angular_x), int(axis_lock_angular_z)))
		axis_lock_angular_x = true
		axis_lock_angular_z = true
	elif has_meta(&"foot_previous_locks"):
		var previous: Vector2i = get_meta(&"foot_previous_locks")
		axis_lock_angular_x = previous.x != 0
		axis_lock_angular_z = previous.y != 0
		remove_meta(&"foot_previous_locks")

func break_part(source: Node = null) -> void:
	if get_meta(&"summon_presentation",false): return
	if is_broken:
		return
	current_hp = 0.0
	is_broken = true
	_start_broken_cleanup()
	sync_foot_rotation_lock()
	broken.emit(source)
	CombatAudio3D.play_at(self, &"break")
	if damage_logging_enabled:
		print(
			"[part_broken] target=%s source=%s"
			% [name, source.name if source != null else &"None"]
		)

func _start_broken_cleanup() -> void:
	if Engine.is_editor_hint() or not is_inside_tree() or get_meta(&"summon_presentation",false) or _broken_cleanup_tween != null: return
	# Cleanup must outlive disabled character controllers, while still respecting battle pause.
	_broken_cleanup_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_broken_cleanup_tween.tween_interval(maxf(broken_linger_duration,0.0))
	_broken_cleanup_tween.tween_callback(_capture_broken_visuals)
	_broken_cleanup_tween.tween_method(_set_broken_fade,0.0,1.0,maxf(broken_fade_duration,0.001)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_broken_cleanup_tween.tween_callback(_finish_broken_cleanup)

func _capture_broken_visuals() -> void:
	for visual: GeometryInstance3D in find_children("*","GeometryInstance3D",true,false):
		var entry := {"node":visual,"transparency":visual.transparency}
		if visual is Sprite3D or visual is Label3D:
			entry["alpha"] = visual.modulate.a
		elif visual is MeshInstance3D and DisplayServer.get_name() != "headless":
			# Paper cutout materials must use alpha blending instead of disappearing at the cut threshold.
			if visual.material_override != null:
				visual.material_override = _broken_fade_material(visual.material_override)
			elif visual.mesh != null:
				for surface: int in visual.mesh.get_surface_count():
					var material: Material = visual.get_active_material(surface)
					if material != null:
						visual.set_surface_override_material(surface,_broken_fade_material(material))
			if visual.material_overlay != null:
				visual.material_overlay = _broken_fade_material(visual.material_overlay)
		_broken_visuals.append(entry)
	if damage_logging_enabled: print("[part_cleanup] part=%s event=fade_begin" % get_path())

func _broken_fade_material(source: Material) -> Material:
	if not source is BaseMaterial3D: return source
	var material := source.duplicate() as BaseMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _set_broken_fade(progress: float) -> void:
	for entry: Dictionary in _broken_visuals:
		if not is_instance_valid(entry.node): continue
		if entry.has("alpha"): entry.node.modulate.a = entry.alpha*(1.0-progress)
		else: entry.node.transparency = lerpf(entry.transparency,1.0,progress)

func _finish_broken_cleanup() -> void:
	if damage_logging_enabled: print("[part_cleanup] part=%s event=removed" % get_path())
	queue_free()

func set_damage_logging_enabled(enabled: bool) -> void:
	damage_logging_enabled = enabled

func has_body_tag(tag: BodyPartTag) -> bool:
	return tag in tags

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if geometry_mode == GeometryMode.CUSTOM_MODEL:
		var model := get_node_or_null(custom_model_path) as Node3D if not custom_model_path.is_empty() else null
		if model == null or model == self or not is_ancestor_of(model):
			warnings.append("Custom Model Path must select a visual node beneath this body.")
		if sprite_visible:
			warnings.append("Custom models retain authored geometry; disable Sprite Visible when using only the model.")
	if not arm_swing_bindings.is_empty() and BodyPartTag.Arm not in tags:
		warnings.append("Arm Swing Bindings are ignored unless this part has the Arm tag.")
	for binding: ArmSwingBinding in arm_swing_bindings:
		if binding == null:
			warnings.append("Arm Swing Bindings contains an empty entry.")
			continue
		if binding.control_group_name.is_empty():
			warnings.append("An Arm Swing Binding has no control group name.")
		if binding.swing_preset == null:
			warnings.append("An Arm Swing Binding has no swing preset.")
	return warnings

func _is_friendly_weapon(weapon: SampleWeapon3D) -> bool:
	if weapon.wielder_character == get_parent(): return true
	var coordinator := get_parent().get_node_or_null("CharacterDamageController3D")
	if coordinator == null:
		return weapon.wielder_character == get_parent()
	var source_team := weapon.wielder_team_id
	if is_instance_valid(weapon.wielder_character) and weapon.wielder_character.has_method("get_faction_id"):
		source_team = weapon.wielder_character.get_faction_id()
	return source_team >= 0 and source_team == int(coordinator.get("team_id"))

func _process(_delta: float) -> void:
	_sync_geometry()

func get_outline_edge_distances() -> Vector4:
	return Vector4(
		maxf(left_distance, MIN_SIZE),
		maxf(right_distance, MIN_SIZE),
		maxf(top_distance, MIN_SIZE),
		maxf(bottom_distance, MIN_SIZE)
	)

## Prepare staged generation geometry before entering the tree; no physics or gameplay callbacks.
func prepare_generated_geometry() -> void:
	_sprite = get_node_or_null("Sprite3D") as Sprite3D
	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	_sync_geometry()

func _sync_geometry() -> void:
	_sync_visual_visibility()
	if geometry_mode == GeometryMode.CUSTOM_MODEL:
		_sync_paper_volume()
		return
	if not is_instance_valid(_sprite) or not is_instance_valid(_collision):
		return
	var edges := get_outline_edge_distances()
	var safe_thickness := maxf(collision_thickness, MIN_SIZE)
	var mesh_resource: Mesh = _visual_switcher.source_mesh(_mesh) if is_instance_valid(_mesh) else null
	var mesh_bounds := mesh_resource.get_aabb() if mesh_resource != null else AABB()
	var signature := [edges, safe_thickness, _sprite.axis, _sprite.texture, mesh_resource, mesh_bounds]
	if signature == _last_signature:
		_sync_collision_depth(_box_visual_size(edges, safe_thickness).z)
		return
	_last_signature = signature

	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = OUTLINE_SHADER
		_sprite.material_override = _material
	_material.set_shader_parameter(&"sprite_texture", _sprite.texture)
	_material.set_shader_parameter(&"sprite_axis", _sprite.axis)
	_material.set_shader_parameter(&"edge_distances", edges)
	_sprite.extra_cull_margin = maxf(edges.x + edges.y, edges.z + edges.w)

	var horizontal_center := (edges.y - edges.x) * 0.5
	var vertical_center := (edges.z - edges.w) * 0.5
	var shape := _collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		_collision.shape = shape
	var visual_size := _box_visual_size(edges, safe_thickness)
	shape.size = visual_size
	match _sprite.axis:
		Vector3.AXIS_X:
			_collision.position = Vector3(0.0, vertical_center, -horizontal_center)
		Vector3.AXIS_Y:
			_collision.position = Vector3(horizontal_center, 0.0, -vertical_center)
		_:
			_collision.position = Vector3(horizontal_center, vertical_center, 0.0)
	_sync_mesh_geometry(visual_size)
	_sync_collision_depth(visual_size.z)

func _box_visual_size(edges: Vector4, depth: float) -> Vector3:
	var width := edges.x + edges.y
	var height := edges.z + edges.w
	match _sprite.axis:
		Vector3.AXIS_X: return Vector3(depth, height, width)
		Vector3.AXIS_Y: return Vector3(width, depth, height)
	return Vector3(width, height, depth)

## Keep authored XY and center; set an absolute depth so reload/regeneration never compounds it.
func _sync_collision_depth(visual_depth: float) -> void:
	if not is_instance_valid(_collision) or _collision.shape == null: return
	var shape := _collision.shape
	var depth := visual_depth * COLLISION_DEPTH_MULTIPLIER / maxf(_collision.basis.z.length(), MIN_SIZE)
	if shape is BoxShape3D:
		if not is_equal_approx(shape.size.z, depth):
			var size: Vector3 = shape.size
			size.z = depth
			shape.size = size
	elif shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = shape.points
		var low := INF
		var high := -INF
		for point: Vector3 in points:
			low = minf(low, point.z)
			high = maxf(high, point.z)
		if high <= low: return
		if not is_equal_approx(high - low, depth):
			var center := (low + high) * 0.5
			for index: int in points.size(): points[index].z = center + (points[index].z - center) * depth / (high - low)
			shape.points = points
	else: return
	if shape.get_meta(COLLISION_DEPTH_META, 1.0) != COLLISION_DEPTH_MULTIPLIER:
		shape.set_meta(COLLISION_DEPTH_META, COLLISION_DEPTH_MULTIPLIER)

func _sync_visual_visibility() -> void:
	if is_instance_valid(_sprite):
		_sprite.visible = sprite_visible and get_visual_state().is_empty()
	if geometry_mode == GeometryMode.CUSTOM_MODEL:
		if not is_instance_valid(_custom_model) and not custom_model_path.is_empty():
			var candidate := get_node_or_null(custom_model_path) as Node3D
			if candidate != null and candidate != self and is_ancestor_of(candidate): _custom_model = candidate
		if is_instance_valid(_mesh) and _mesh != _custom_model:
			_mesh.visible = false
		if is_instance_valid(_custom_model): _custom_model.visible = mesh_visible
		return
	if is_instance_valid(_mesh):
		_mesh.visible = mesh_visible

func _sync_paper_volume() -> void:
	if not is_instance_valid(_custom_model): return
	if not is_instance_valid(_paper_volume) or _paper_volume.get_parent() != _custom_model:
		_paper_volume = _custom_model.get_node_or_null("PaperVolume") as MeshInstance3D
		_paper_source_meshes.clear()
		_paper_side_material = null
		_paper_signature.clear()
		if _paper_volume == null: return
		for node: Node in _custom_model.find_children("*","MeshInstance3D",true,false):
			if node != _paper_volume: _paper_source_meshes.append(node as MeshInstance3D)
	var shape := _collision.shape if is_instance_valid(_collision) else null
	var convex := shape as ConvexPolygonShape3D
	if convex != _paper_collision_shape:
		_paper_collision_shape = convex
		if convex != null and not convex.points.is_empty():
			var low := INF
			var high := -INF
			for point: Vector3 in convex.points:
				low = minf(low,point.z)
				high = maxf(high,point.z)
			# Keep the flat depth stable even after an editor save stores expanded points.
			_paper_original_depth = maxf(float(_paper_volume.get_meta("flat_collision_depth",(high-low)/float(shape.get_meta(COLLISION_DEPTH_META,1.0)))),MIN_SIZE)
	var model_depth_scale := _custom_model.basis.z.length()
	var signature := [paper_volume_enabled,paper_volume_thickness,paper_side_color,shape,_paper_volume,model_depth_scale,_collision.transform if is_instance_valid(_collision) else Transform3D.IDENTITY]
	if signature == _paper_signature: return
	_paper_signature = signature
	_paper_volume.visible = paper_volume_enabled
	for visual: MeshInstance3D in _paper_source_meshes:
		if is_instance_valid(visual): visual.visible = not paper_volume_enabled
	if _visual_switcher.is_target(_paper_volume): _visual_switcher.update_paper_depth(paper_volume_thickness)
	else: _paper_volume.scale.z = paper_volume_thickness
	if _paper_side_material == null:
		_paper_side_material = _paper_volume.mesh.surface_get_material(2).duplicate() as StandardMaterial3D
		_paper_volume.set_surface_override_material(2,_paper_side_material)
	_paper_side_material.albedo_color = paper_side_color
	_sync_collision_depth((paper_volume_thickness if paper_volume_enabled else _paper_original_depth) * model_depth_scale)

func _sync_mesh_geometry(size: Vector3) -> void:
	if not is_instance_valid(_mesh) or _mesh.mesh == null:
		return
	var source := _visual_switcher.source_mesh(_mesh)
	if source == null: return
	var bounds := source.get_aabb()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return
	var model_scale := size / bounds.size
	var pose := _collision.transform * Transform3D(
		Basis.from_scale(model_scale), -bounds.get_center() * model_scale
	)
	if _visual_switcher.is_target(_mesh): _visual_switcher.update_base_transform(pose)
	else: _mesh.transform = pose

func get_visual_state() -> StringName:
	return _visual_switcher.current_state

func get_available_visual_states() -> Array[StringName]:
	var result: Array[StringName] = []
	for state: BodyPartVisualState3D in visual_states:
		if state != null and not state.state_name.is_empty() and state.mesh != null and state.state_name not in result:
			result.append(state.state_name)
	return result

## Swaps render resources in place; the rigid body, collider, joints and sockets are untouched.
func set_visual_state(state_name: StringName) -> bool:
	if state_name.is_empty():
		var changed := not get_visual_state().is_empty()
		_visual_switcher.restore()
		_sync_visual_visibility()
		if changed: visual_state_changed.emit(&"")
		return true
	if not is_inside_tree():
		push_warning("[part_visual] Set Initial Visual State before entering the tree, or call set_visual_state after ready.")
		return false
	var selected: BodyPartVisualState3D
	for state: BodyPartVisualState3D in visual_states:
		if state != null and state.state_name == state_name:
			if selected != null:
				push_warning("[part_visual] Duplicate state '%s' on %s." % [state_name,name])
				return false
			selected = state
	var target := _resolve_visual_state_mesh()
	if target != null and not is_ancestor_of(target): target = null
	var anchor_position: Variant = null
	if selected != null and not selected.anchor_path.is_empty():
		var anchor := get_node_or_null(selected.anchor_path) as Node3D
		if anchor == null or not is_ancestor_of(anchor) or not selected.mesh_anchor.is_finite() or target == null:
			push_warning("[part_visual] Invalid visual anchor on %s; current appearance retained." % name)
			return false
		var frame := target.get_parent()
		while frame != null and not frame is Node3D: frame = frame.get_parent()
		if frame == null: return false
		anchor_position = (frame as Node3D).to_local(anchor.global_position)
	if not _visual_switcher.apply(selected,target,anchor_position):
		push_warning("[part_visual] Missing or invalid state/mesh '%s' on %s; current appearance retained." % [state_name,name])
		return false
	if target == _paper_volume and target.mesh.get_surface_count() > 2 and _paper_side_material != null:
		target.set_surface_override_material(2,_paper_side_material)
	_sync_visual_visibility()
	visual_state_changed.emit(state_name)
	return true

func _resolve_visual_state_mesh() -> MeshInstance3D:
	if not visual_state_mesh_path.is_empty(): return get_node_or_null(visual_state_mesh_path) as MeshInstance3D
	if geometry_mode == GeometryMode.BOX_FIT: return _mesh
	var model := get_node_or_null(custom_model_path) as Node3D
	if model == null: return null
	var paper := model.get_node_or_null("PaperVolume") as MeshInstance3D
	if paper_volume_enabled and paper != null: return paper
	if model is MeshInstance3D: return model as MeshInstance3D
	for child: Node in model.find_children("*","MeshInstance3D",true,false):
		if child != paper: return child as MeshInstance3D
	return null
