class_name SampleWeapon3D
extends SampleItem3D

@export_group("Hit Registration")
@export_range(0.01, 5.0, 0.01, "or_greater") var passive_hit_cooldown: float = 0.25

var wielder_character: Node
var wielder_team_id: int = -1
var swing_sequence: int = 0
var swing_damage_active: bool = false
var damage_logging_enabled: bool = false
var _swing_hit_parts: Dictionary = {}
var _passive_hit_times_msec: Dictionary = {}
var _active_swing_count: int = 0

func _ready() -> void:
	super._ready()
	add_to_group(&"damage_components")
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console != null and console.has_method("is_damage_tracking_enabled"):
		damage_logging_enabled = bool(console.call("is_damage_tracking_enabled"))

func set_wielder(character: Node, team_id: int) -> void:
	wielder_character = character
	wielder_team_id = team_id

func clear_wielder() -> void:
	wielder_character = null

func begin_damage_swing() -> void:
	swing_sequence += 1
	_active_swing_count += 1
	swing_damage_active = true
	_swing_hit_parts.clear()

func end_damage_swing() -> void:
	_active_swing_count = maxi(_active_swing_count - 1, 0)
	swing_damage_active = _active_swing_count > 0

func try_register_hit(target: Node) -> bool:
	return target != null and _register_hit(target)

func _register_hit(target: Node) -> bool:
	var target_id := target.get_instance_id()
	if swing_damage_active:
		if _swing_hit_parts.has(target_id):
			return false
		_swing_hit_parts[target_id] = swing_sequence
		return true
	var now_msec := Time.get_ticks_msec()
	var last_msec := int(_passive_hit_times_msec.get(target_id, -1000000))
	if now_msec - last_msec < int(passive_hit_cooldown * 1000.0):
		return false
	_passive_hit_times_msec[target_id] = now_msec
	return true

func set_damage_logging_enabled(enabled: bool) -> void:
	damage_logging_enabled = enabled


## Resolve a merged weapon by the exact contacting shape, so bare Arm contacts do not become weapon hits.
static func from_contact(collider: Object, shape_index: int) -> SampleWeapon3D:
	if collider is SampleWeapon3D:
		return collider as SampleWeapon3D
	if not collider is CollisionObject3D:
		return null
	var body := collider as CollisionObject3D
	var owner_id := body.shape_find_owner(shape_index)
	var owner := body.shape_owner_get_owner(owner_id) as Node
	if owner == null or not owner.has_meta(&"equipped_item"):
		return null
	var item_value: Variant = owner.get_meta(&"equipped_item")
	return item_value as SampleWeapon3D if is_instance_valid(item_value) else null
