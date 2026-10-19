@tool
extends Node3D

@export_group("Faction")
@export var faction_id: int = 0
var _combat_anchor: Node3D
var _ragdoll_sources: Dictionary = {}
var _ragdoll_modes: Dictionary = {}
var _hit_ragdoll_timer: Timer
var _control_components: Array[Node] = []
var _control_components_dirty := true
var _control_refresh_pending := false
var _base_combat_mass := 0.0

## Cached naked anatomy; equipment mass and later Broken parts cannot change an action's damage.
func get_base_combat_mass() -> float:
	if _base_combat_mass <= 0.0:
		for part: PhysicalBodyPart3D in _get_physical_body_parts():
			_base_combat_mass += part.base_combat_mass if part.base_combat_mass > 0.0 else part.mass
	return _base_combat_mass

func reset_combat_mass() -> void:
	_base_combat_mass = 0.0
	get_base_combat_mass()

func _is_control_component(node: Node) -> bool:
	if node is PhysicalBodyPart3D or node is Joint3D or node is CharacterDamageController3D: return false
	var label := str(node.name).to_lower()
	return node.has_method("set_character_control_enabled") or label.contains("controller") or label.contains("statemachine") or label.contains("state_machine")

func _invalidate_control_components() -> void:
	_control_components_dirty = true

func get_control_components() -> Array[Node]:
	if _control_components_dirty or Engine.is_editor_hint():
		_control_components.clear()
		for node: Node in find_children("*", "", true, false):
			if not _is_control_component(node) or node.is_queued_for_deletion(): continue
			_control_components.append(node)
			if not node.tree_exiting.is_connected(_invalidate_control_components): node.tree_exiting.connect(_invalidate_control_components)
		_control_components_dirty = false
	var result: Array[Node] = []
	for node: Node in _control_components:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and is_ancestor_of(node): result.append(node)
	return result

func _cancel_component_actions(component: Node, reason: StringName) -> void:
	if component.has_method("cancel_action"): component.cancel_action(reason)
	elif component.has_method("cancel_player_actions"): component.cancel_player_actions()
	elif component.has_method("cancel_npc_attack"): component.cancel_npc_attack()

func cancel_character_actions(reason: StringName) -> void:
	for component: Node in get_control_components(): _cancel_component_actions(component, reason)

func disable_character_controls() -> void:
	for component: Node in get_control_components():
		_cancel_component_actions(component, &"character_disabled")
		if component.has_method("set_character_control_enabled"):
			component.set_character_control_enabled(false)
		else:
			component.set_process(false)
			component.set_physics_process(false)
			component.set_process_input(false)
			component.set_process_unhandled_input(false)

func _suspend_ragdoll_components() -> void:
	_control_refresh_pending = false
	if not is_temporarily_ragdolled(): return
	for component: Node in get_control_components():
		if _ragdoll_modes.has(component): continue
		_ragdoll_modes[component] = component.process_mode
		_cancel_component_actions(component, &"ragdoll")
		if component.has_method("release_support_for_impact"): component.release_support_for_impact(0.1)
		component.process_mode = Node.PROCESS_MODE_DISABLED

func is_temporarily_ragdolled() -> bool:
	return not _ragdoll_sources.is_empty()

## Target-owned timer survives cancellation or deletion of the attacking hitbox.
func apply_timed_hit_ragdoll(duration: float) -> void:
	if Engine.is_editor_hint() or duration <= 0.0 or not is_inside_tree() or not is_combat_alive(): return
	if not is_instance_valid(_hit_ragdoll_timer):
		_hit_ragdoll_timer = Timer.new()
		_hit_ragdoll_timer.name = "HitRagdollTimer"
		_hit_ragdoll_timer.one_shot = true
		# Keep counting when this character's controllers are disabled, but respect game pause.
		_hit_ragdoll_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(_hit_ragdoll_timer)
		_hit_ragdoll_timer.timeout.connect(_end_hit_ragdoll)
	set_temporary_ragdoll(_hit_ragdoll_timer,true)
	_hit_ragdoll_timer.start(maxf(duration,_hit_ragdoll_timer.time_left))

func _end_hit_ragdoll() -> void:
	if is_instance_valid(_hit_ragdoll_timer): set_temporary_ragdoll(_hit_ragdoll_timer,false)

func set_temporary_ragdoll(source: Node, value: bool) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(source): return
	var id := source.get_instance_id()
	if value:
		if _ragdoll_sources.has(id): return
		_ragdoll_sources[id] = true
		if _ragdoll_sources.size() > 1: return
		_suspend_ragdoll_components()
	else:
		_ragdoll_sources.erase(id)
		if not _ragdoll_sources.is_empty(): return
		for child: Variant in _ragdoll_modes:
			# Death may have disabled controllers while ragdolled; never revive them on release.
			if is_instance_valid(child) and is_combat_alive(): child.process_mode = _ragdoll_modes[child]
		_ragdoll_modes.clear()

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
var _body_connections: Array[Node] = []
var _body_connections_dirty := true

func _invalidate_body_connections() -> void:
	_body_connections_dirty = true

func get_body_connections() -> Array[Node]:
	if _body_connections_dirty or Engine.is_editor_hint():
		_body_connections.clear()
		for node: Node in find_children("*", "", true, false):
			if not node is Joint3D and not node.has_method("is_segment_spring"): continue
			_body_connections.append(node)
			if not node.tree_exiting.is_connected(_invalidate_body_connections): node.tree_exiting.connect(_invalidate_body_connections)
		_body_connections_dirty = false
	var result: Array[Node] = []
	for node: Node in _body_connections:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and is_ancestor_of(node) and not node.has_meta(&"planar_depth_guide"):
			result.append(node)
	return result

func get_body_parts_with_tag(tag: int, include_broken: bool = false) -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	for part: PhysicalBodyPart3D in _get_physical_body_parts():
		if tag in part.tags and (include_broken or not part.is_broken): result.append(part)
	return result

func get_living_body_mass() -> float:
	var total := 0.0
	for part: PhysicalBodyPart3D in _get_physical_body_parts():
		if not part.is_broken: total += part.mass
	return total

func _ready() -> void:
	if Engine.is_editor_hint(): return
	add_to_group(&"physical_characters_3d")
	if not get_tree().node_added.is_connected(_on_body_part_added): get_tree().node_added.connect(_on_body_part_added)
	_configure_body_part_collision_exceptions()
	get_base_combat_mass()
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
	if not is_ancestor_of(node): return
	if node is PhysicalBodyPart3D: _invalidate_body_parts_cache()
	if node is Joint3D or node.has_method("is_segment_spring"): _invalidate_body_connections()
	if _is_control_component(node):
		_invalidate_control_components()
		if is_temporarily_ragdolled() and not _control_refresh_pending:
			_control_refresh_pending = true
			call_deferred("_suspend_ragdoll_components")

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
