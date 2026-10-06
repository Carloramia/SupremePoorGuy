class_name CharacterDamageController3D
extends Node

const TORSO_TAG: int = 0
const HEAD_TAG: int = 3

@export var team_id: int = 0:
	get:
		var actor := get_parent()
		return actor.get_faction_id() if actor != null and actor.has_method("get_faction_id") else team_id
	set(value):
		team_id = value
		var actor := get_parent()
		if actor != null and actor.has_method("get_faction_id"): actor.faction_id = value
@export var damage_logging_enabled: bool = false

var _parts: Array[PhysicalBodyPart3D] = []
var _character_disabled: bool = false
var _integrity_check_pending: bool = false
var _integrity_source: Node

func _ready() -> void:
	add_to_group(&"damage_components")
	_discover_parts()
	get_tree().node_added.connect(_on_structure_node_added)
	_request_integrity_check()
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console != null and console.has_method("is_damage_tracking_enabled"):
		set_damage_logging_enabled(bool(console.call("is_damage_tracking_enabled")))

func _discover_parts() -> void:
	for part: PhysicalBodyPart3D in _parts:
		if is_instance_valid(part):
			var callback := _on_part_broken.bind(part)
			if part.broken.is_connected(callback): part.broken.disconnect(callback)
	_parts.clear()
	for node: Node in get_parent().find_children("*", "PhysicalBodyPart3D", true, false):
		var part := node as PhysicalBodyPart3D
		if part == null:
			continue
		_parts.append(part)
		part.broken.connect(_on_part_broken.bind(part))
		_watch_structure_node(part)
	for node: Node in get_parent().find_children("*", "", true, false):
		if _is_body_connection(node): _watch_structure_node(node)

func _is_body_connection(node: Node) -> bool:
	return (node is Joint3D and not node.has_meta(&"planar_depth_guide")) or node.has_method("is_segment_spring")

func _watch_structure_node(node: Node) -> void:
	if not node.tree_exiting.is_connected(_request_integrity_check):
		node.tree_exiting.connect(_request_integrity_check)

func _on_structure_node_added(node: Node) -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	if not node is PhysicalBodyPart3D and not _is_body_connection(node): return
	if not get_parent().is_ancestor_of(node): return
	_watch_structure_node(node)
	_request_integrity_check()

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_structure_node_added):
		get_tree().node_added.disconnect(_on_structure_node_added)

func _request_integrity_check() -> void:
	if is_queued_for_deletion() or not is_inside_tree() or _integrity_check_pending: return
	_integrity_check_pending = true
	call_deferred("_validate_body_integrity")

func _validate_body_integrity() -> void:
	_integrity_check_pending = false
	if is_queued_for_deletion() or not is_inside_tree(): return
	var actor := get_parent()
	if actor.get("require_head_and_torso_connectivity") != true: return
	_discover_parts()
	var graph: Dictionary = {}
	for part: PhysicalBodyPart3D in _parts:
		if not part.is_broken and not part.is_queued_for_deletion(): graph[part] = []
	for node: Node in actor.find_children("*", "", true, false):
		if not _is_body_connection(node) or node.is_queued_for_deletion(): continue
		if node.has_method("is_segment_spring") and not node.enabled: continue
		var first := node.get_node_or_null(node.node_a)
		var second := node.get_node_or_null(node.node_b)
		if graph.has(first) and graph.has(second):
			graph[first].append(second)
			graph[second].append(first)
	var visited: Dictionary = {}
	var source: Node = _integrity_source if is_instance_valid(_integrity_source) else null
	_integrity_source = null
	for start: PhysicalBodyPart3D in graph:
		if visited.has(start): continue
		var component: Array[PhysicalBodyPart3D] = [start]
		visited[start] = true
		var cursor := 0
		var has_head := false
		var has_torso := false
		while cursor < component.size():
			var part := component[cursor]
			cursor += 1
			has_head = has_head or HEAD_TAG in part.tags
			has_torso = has_torso or TORSO_TAG in part.tags
			for neighbor: PhysicalBodyPart3D in graph[part]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					component.append(neighbor)
		if has_head and has_torso: continue
		if damage_logging_enabled:
			var names: Array[StringName] = []
			for part: PhysicalBodyPart3D in component: names.append(part.name)
			print("[character_integrity] character=%s has_head=%s has_torso=%s broken_parts=%s" % [actor.name,has_head,has_torso,names])
		for part: PhysicalBodyPart3D in component: part.break_part(source)
	var any_living := false
	for part: PhysicalBodyPart3D in _parts: any_living = any_living or not part.is_broken
	if not _parts.is_empty() and not any_living: _disable_character_controllers()

func _on_part_broken(source: Node, part: PhysicalBodyPart3D) -> void:
	_integrity_source = source
	call_deferred("_handle_part_broken", part, source)
	_request_integrity_check()

func _handle_part_broken(part: PhysicalBodyPart3D, source: Node) -> void:
	# Regeneration may remove this controller before an already queued break callback runs.
	if not is_inside_tree() or is_queued_for_deletion(): return
	if not is_instance_valid(part):
		return
	var inventory := get_parent().get_node_or_null("InventoryController3D")
	if inventory != null and inventory.has_method("handle_part_broken"):
		inventory.call("handle_part_broken", part)
	# Capture connections before the joints are queued for removal.
	var connected_parts := _get_connected_parts(part)
	var removed_joints := _remove_connected_joints(part)
	_request_integrity_check()
	if TORSO_TAG in part.tags:
		for other_part: PhysicalBodyPart3D in connected_parts:
			if not other_part.is_broken and TORSO_TAG not in other_part.tags:
				other_part.break_part(source)
	if not _character_disabled and _all_heads_broken():
		_disable_character_controllers()
		for other_part: PhysicalBodyPart3D in _parts:
			if is_instance_valid(other_part) and not other_part.is_broken:
				other_part.break_part(source)
	if damage_logging_enabled:
		print(
			("[character_damage] character=%s broken_part=%s removed_joints=%s "
			+ "all_heads_broken=%s")
			% [get_parent().name, part.name, removed_joints, _character_disabled]
		)

func _remove_connected_joints(part: PhysicalBodyPart3D) -> Array[StringName]:
	var removed: Array[StringName] = []
	for joint: Node in get_parent().find_children("*", "", true, false):
		if not _is_body_connection(joint) or joint.is_queued_for_deletion():
			continue
		var body_a := joint.get_node_or_null(joint.node_a)
		var body_b := joint.get_node_or_null(joint.node_b)
		if body_a != part and body_b != part:
			continue
		removed.append(joint.name)
		joint.queue_free()
	return removed

func _get_connected_parts(part: PhysicalBodyPart3D) -> Array[PhysicalBodyPart3D]:
	var connected: Array[PhysicalBodyPart3D] = []
	for joint: Node in get_parent().find_children("*", "", true, false):
		if not _is_body_connection(joint) or joint.is_queued_for_deletion():
			continue
		var body_a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var body_b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		var other: PhysicalBodyPart3D
		if body_a == part:
			other = body_b
		elif body_b == part:
			other = body_a
		if other != null and other not in connected:
			connected.append(other)
	return connected

## A character without Head parts does not trigger the whole-body cascade.
func _all_heads_broken() -> bool:
	var found_head := false
	for part: PhysicalBodyPart3D in _parts:
		if not is_instance_valid(part) or HEAD_TAG not in part.tags:
			continue
		found_head = true
		if not part.is_broken:
			return false
	return found_head

func _disable_character_controllers() -> void:
	if _character_disabled:
		return
	_character_disabled = true
	for child: Node in get_parent().find_children("*", "", true, false):
		if child is PhysicalBodyPart3D or child is Joint3D or child == self:
			continue
		if child.has_method("set_character_control_enabled"):
			child.call("set_character_control_enabled", false)
		elif child.name.to_lower().contains("controller") or child.name.to_lower().contains("state_machine"):
			child.set_process(false)
			child.set_physics_process(false)
			child.set_process_input(false)
			child.set_process_unhandled_input(false)

func is_character_disabled() -> bool:
	return _character_disabled

func get_parts() -> Array[PhysicalBodyPart3D]:
	return _parts.duplicate()

func set_damage_logging_enabled(enabled: bool) -> void:
	damage_logging_enabled = enabled
	for part: PhysicalBodyPart3D in _parts:
		if is_instance_valid(part):
			part.set_damage_logging_enabled(enabled)

