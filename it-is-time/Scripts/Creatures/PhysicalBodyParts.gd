@tool
class_name PhysicalBodyPart3D
extends RigidBody3D

signal damaged(amount: float, remaining_hp: float, source: Node)
signal broken(source: Node)
signal slipping_changed(value: bool)

const OUTLINE_SHADER: Shader = preload("res://Shaders/BodyPartOutline.gdshader")
const DEFAULT_DAMAGE_NUMBER_SCENE: PackedScene = preload("res://Scenes/VFX/DamageNumber3D.tscn")
const MIN_SIZE: float = 0.001

enum BodyPartTag {
	Torso,
	Leg,
	Arm,
	Head,
	# Append to preserve existing serialized Torso/Leg/Arm/Head indices.
	ForeLeg,
	LegLimb,
	SubTorso,
}

@export_group("Classification")
## A part may carry more than one classification tag.
@export var tags: Array[BodyPartTag] = []

@export_group("Foot Ground State")
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
@export var is_broken: bool = false
@export var damage_logging_enabled: bool = false

@export_group("Damage Feedback")
@export var damage_number_scene: PackedScene = DEFAULT_DAMAGE_NUMBER_SCENE
@export var damage_number_offset: Vector3 = Vector3(0.0, 0.75, 0.0)

@export_group("Visuals")
@export var sprite_visible: bool = true:
	set(value):
		sprite_visible = value
		_sync_visual_visibility()
@export var mesh_visible: bool = true:
	set(value):
		mesh_visible = value
		_sync_visual_visibility()

@export_group("BodyPart Edges")
## Distances from the Sprite3D's local origin, in Godot 3D units.
@export_range(0.001, 100.0, 0.01, "or_greater") var left_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var right_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var top_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var bottom_distance: float = 1.28

@export_group("Collision")
## Collision depth perpendicular to the Sprite3D plane.
@export_range(0.001, 100.0, 0.01, "or_greater") var collision_thickness: float = 0.2

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D

var _material: ShaderMaterial
var _last_signature: Array = []
var current_hp: float = 100.0
var _damage_service: Node
var _collision_logging_enabled: bool = false

func _ready() -> void:
	sync_foot_rotation_lock()
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
	if not Engine.is_editor_hint():
		add_to_group(&"physical_body_parts")
		body_entered.connect(_on_collision_body_entered)
		body_exited.connect(_on_collision_body_exited)
		if console != null and console.has_method("is_collision_tracking_enabled"):
			set_collision_logging_enabled(bool(console.call("is_collision_tracking_enabled")))

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

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if Engine.is_editor_hint() or is_broken:
		return
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
		var impulse: float = weapon_impulses[weapon]
		var raw_damage := 0.0
		var hp_damage := 0.0
		var registered := false
		if is_instance_valid(_damage_service):
			raw_damage = float(_damage_service.call("calculate_weapon_raw_damage", impulse, weapon.swing_damage_active))
			var eligible_damage := float(_damage_service.call("apply_weapon_armor", raw_damage, armor, weapon.swing_damage_active))
			# Glancing contacts absorbed by armor must not spend this swing's one damage opportunity.
			if eligible_damage > 0.0:
				registered = weapon.try_register_hit(self)
				if registered:
					hp_damage = eligible_damage
		if damage_logging_enabled or weapon.damage_logging_enabled:
			print(
				("[part_impact] target=%s weapon=%s mode=%s registered=%s impulse=%.3f raw_damage=%.3f "
				+ "armor=%.3f hp_damage=%.3f hp=%.3f")
				% [name, weapon.name, "swing" if weapon.swing_damage_active else "passive", registered, impulse, raw_damage, armor, hp_damage, current_hp]
			)
		if hp_damage > 0.0:
			apply_damage(hp_damage, weapon)

func apply_damage(amount: float, source: Node = null) -> float:
	if is_broken or amount <= 0.0:
		return 0.0
	var applied := minf(amount, current_hp)
	current_hp = maxf(current_hp - applied, 0.0)
	damaged.emit(applied, current_hp, source)
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
	var scene_parent := get_tree().current_scene
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
	if is_broken:
		return
	current_hp = 0.0
	is_broken = true
	sync_foot_rotation_lock()
	broken.emit(source)
	if damage_logging_enabled:
		print(
			"[part_broken] target=%s source=%s"
			% [name, source.name if source != null else &"None"]
		)

func set_damage_logging_enabled(enabled: bool) -> void:
	damage_logging_enabled = enabled

func has_body_tag(tag: BodyPartTag) -> bool:
	return tag in tags

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
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
	var coordinator := get_parent().get_node_or_null("CharacterDamageController3D")
	if coordinator == null:
		return weapon.wielder_character == get_parent()
	return weapon.wielder_team_id >= 0 and weapon.wielder_team_id == int(coordinator.get("team_id"))

func _process(_delta: float) -> void:
	_sync_geometry()

func get_outline_edge_distances() -> Vector4:
	return Vector4(
		maxf(left_distance, MIN_SIZE),
		maxf(right_distance, MIN_SIZE),
		maxf(top_distance, MIN_SIZE),
		maxf(bottom_distance, MIN_SIZE)
	)

func _sync_geometry() -> void:
	_sync_visual_visibility()
	if not is_instance_valid(_sprite) or not is_instance_valid(_collision):
		return
	var edges := get_outline_edge_distances()
	var safe_thickness := maxf(collision_thickness, MIN_SIZE)
	var mesh_resource: Mesh = _mesh.mesh if is_instance_valid(_mesh) else null
	var mesh_bounds := mesh_resource.get_aabb() if mesh_resource != null else AABB()
	var signature := [edges, safe_thickness, _sprite.axis, _sprite.texture, mesh_resource, mesh_bounds]
	if signature == _last_signature:
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

	var width := edges.x + edges.y
	var height := edges.z + edges.w
	var horizontal_center := (edges.y - edges.x) * 0.5
	var vertical_center := (edges.z - edges.w) * 0.5
	var shape := _collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		_collision.shape = shape
	match _sprite.axis:
		Vector3.AXIS_X:
			shape.size = Vector3(safe_thickness, height, width)
			_collision.position = Vector3(0.0, vertical_center, -horizontal_center)
		Vector3.AXIS_Y:
			shape.size = Vector3(width, safe_thickness, height)
			_collision.position = Vector3(horizontal_center, 0.0, -vertical_center)
		_:
			shape.size = Vector3(width, height, safe_thickness)
			_collision.position = Vector3(horizontal_center, vertical_center, 0.0)
	_sync_mesh_geometry(shape.size)

func _sync_visual_visibility() -> void:
	if is_instance_valid(_sprite):
		_sprite.visible = sprite_visible
	if is_instance_valid(_mesh):
		_mesh.visible = mesh_visible

func _sync_mesh_geometry(size: Vector3) -> void:
	if not is_instance_valid(_mesh) or _mesh.mesh == null:
		return
	var bounds := _mesh.mesh.get_aabb()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return
	var model_scale := size / bounds.size
	_mesh.transform = _collision.transform * Transform3D(
		Basis.from_scale(model_scale), -bounds.get_center() * model_scale
	)
