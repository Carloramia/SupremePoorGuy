@tool
extends Node3D

@export_group("Faction")
@export var faction_id: int = 0
var _combat_anchor: Node3D

@export_group("Body Integrity")
## Every living connected component must contain both a Head and a Torso.
@export var require_head_and_torso_connectivity: bool = true

@export_group("Mass Limits")
## Generated characters use this inherited switch when calculating part masses.
@export var mass_limits_enabled: bool = true

func get_faction_id() -> int: return faction_id

## Choose a living Torso by distance, rather than the largest-mass combat anchor.
func get_nearest_combat_torso(from: Vector3) -> Node3D:
	var damage := get_node_or_null("CharacterDamageController3D")
	var parts: Array = damage.get_parts() if damage != null else _get_physical_body_parts()
	var nearest: Node3D
	var best := INF
	for part in parts:
		if not is_instance_valid(part) or part.is_queued_for_deletion() or part.is_broken or 0 not in part.tags: continue
		var distance := from.distance_squared_to(part.global_position)
		if distance < best:
			best = distance
			nearest = part
	return nearest if is_instance_valid(nearest) else get_combat_anchor()

func is_combat_alive() -> bool:
	var damage := get_node_or_null("CharacterDamageController3D")
	return damage == null or not damage.is_character_disabled()

func get_combat_anchor() -> Node3D:
	if is_instance_valid(_combat_anchor) and not _combat_anchor.is_queued_for_deletion() and not bool(_combat_anchor.get("is_broken")): return _combat_anchor
	_combat_anchor = null
	var damage := get_node_or_null("CharacterDamageController3D")
	var parts: Array = damage.get_parts() if damage != null else _get_physical_body_parts()
	var mass := -1.0
	for part in parts:
		if is_instance_valid(part) and not part.is_broken and 0 in part.tags and part.mass > mass:
			_combat_anchor = part
			mass = part.mass
	return _combat_anchor if is_instance_valid(_combat_anchor) else self

@export_group("Collision")
## Adds pairwise collision exceptions between every physical BodyPart in this character.
## Collision with terrain, other characters, and external physics bodies is unchanged.
@export var body_parts_ignore_each_other: bool = true

var _collision_refresh_pending: bool = false
var _body_parts_cache: Array[RigidBody3D] = []
var _body_rids_cache: Array[RID] = []
var _body_parts_cache_dirty: bool = true
var _body_parts_revision: int = 0

func _ready() -> void:
	if Engine.is_editor_hint(): return
	add_to_group(&"physical_characters_3d")
	if not get_tree().node_added.is_connected(_on_body_part_added): get_tree().node_added.connect(_on_body_part_added)
	_configure_body_part_collision_exceptions()
	if not Engine.is_editor_hint(): call_deferred("_ensure_damage_controller")

func _ensure_damage_controller() -> void:
	if is_queued_for_deletion() or has_node("CharacterDamageController3D") or _get_physical_body_parts().is_empty(): return
	var damage := (load("res://Scenes/Creatures/Components/CharacterDamageController3D.tscn") as PackedScene).instantiate()
	damage.name = "CharacterDamageController3D"
	add_child(damage)

func _configure_body_part_collision_exceptions() -> void:
	if not body_parts_ignore_each_other:
		return
	# Joint teardown can clear an engine collision exception for its two bodies,
	# even if that pair was also excluded by the character. Restore after teardown.
	for node: Node in find_children("*", "Joint3D", true, false):
		if not node.tree_exited.is_connected(_on_internal_joint_removed):
			node.tree_exited.connect(_on_internal_joint_removed)
	var body_parts := _get_physical_body_parts()
	for first_index: int in range(body_parts.size()):
		for second_index: int in range(first_index + 1, body_parts.size()):
			var first_part := body_parts[first_index]
			var second_part := body_parts[second_index]
			first_part.add_collision_exception_with(second_part)
			second_part.add_collision_exception_with(first_part)

func _on_internal_joint_removed() -> void:
	if is_inside_tree() and not is_queued_for_deletion() and not _collision_refresh_pending:
		_collision_refresh_pending = true
		call_deferred("_restore_internal_collision_exceptions")

func _restore_internal_collision_exceptions() -> void:
	_collision_refresh_pending = false
	if is_inside_tree() and not is_queued_for_deletion():
		_configure_body_part_collision_exceptions()

func _get_physical_body_parts() -> Array[RigidBody3D]:
	_refresh_body_parts_cache()
	var result: Array[RigidBody3D] = []
	for body: RigidBody3D in _body_parts_cache:
		if is_instance_valid(body) and not body.is_queued_for_deletion(): result.append(body)
	return result

func _invalidate_body_parts_cache() -> void:
	_body_parts_cache_dirty = true
	_body_parts_revision += 1
	_combat_anchor = null

func _on_body_part_added(node: Node) -> void:
	if node is PhysicalBodyPart3D and is_ancestor_of(node): _invalidate_body_parts_cache()

func _on_cached_part_broken(_source: Node) -> void:
	_invalidate_body_parts_cache()

func _refresh_body_parts_cache() -> void:
	# Editor-generated children can change before _ready; do not cache editor queries.
	if not _body_parts_cache_dirty and not Engine.is_editor_hint(): return
	_body_parts_cache.clear()
	_body_rids_cache.clear()
	for node: Node in find_children("*", "RigidBody3D", true, false):
		if not node is PhysicalBodyPart3D or node.is_queued_for_deletion(): continue
		var body := node as PhysicalBodyPart3D
		_body_parts_cache.append(body)
		_body_rids_cache.append(body.get_rid())
		if not body.tree_exiting.is_connected(_invalidate_body_parts_cache): body.tree_exiting.connect(_invalidate_body_parts_cache)
		if not body.broken.is_connected(_on_cached_part_broken): body.broken.connect(_on_cached_part_broken)
	_body_parts_cache_dirty = false

func get_physical_body_rids() -> Array[RID]:
	_refresh_body_parts_cache()
	return _body_rids_cache.duplicate()

func get_body_parts_revision() -> int:
	_refresh_body_parts_cache()
	return _body_parts_revision

## Read actual engine exceptions instead of reporting only the Inspector switch.
func get_internal_collision_diagnostics() -> Dictionary:
	var parts := _get_physical_body_parts()
	var exceptions: Dictionary = {}
	for part: RigidBody3D in parts:
		exceptions[part] = part.get_collision_exceptions()
	var missing: Array[String] = []
	var missing_count := 0
	for i: int in range(parts.size()):
		for j: int in range(i + 1, parts.size()):
			if parts[j] not in exceptions[parts[i]] or parts[i] not in exceptions[parts[j]]:
				missing_count += 1
				if missing.size() < 12: missing.append("%s <-> %s" % [parts[i].name, parts[j].name])
	return {"enabled": body_parts_ignore_each_other, "parts": parts.size(), "pairs": parts.size() * (parts.size() - 1) / 2, "missing_pairs": missing_count, "missing_examples": missing}
