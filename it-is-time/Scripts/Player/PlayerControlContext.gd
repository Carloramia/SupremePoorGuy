extends RefCounted

static func controller(node: Node) -> Node:
	var host := application(node)
	if host != null: return host.get_active_controller()
	return node.get_tree().get_first_node_in_group(&"player_controller_3d") if node.is_inside_tree() else null

static func application(node: Node) -> Node:
	return node.get_tree().get_first_node_in_group(&"application_host") if node.is_inside_tree() else null

static func level(node: Node) -> Node:
	var current := node
	while current != null:
		if current.has_meta(&"gameplay_level"): return current
		current = current.get_parent()
	var host := application(node)
	if host != null and is_instance_valid(host.get_active_level()): return host.get_active_level()
	return node.get_tree().current_scene if node.get_tree().current_scene != null else node.get_tree().root

static func interface_open(node: Node) -> bool:
	var host := application(node)
	return host != null and host.is_gameplay_blocked()

static func is_free_cursor_mode(node: Node) -> bool:
	if not node.is_inside_tree(): return false
	var host := application(node)
	if host != null: return host.get_active_controller() == null
	var cursor := node.get_tree().get_first_node_in_group(&"terrain_cursor_3d")
	return cursor != null and cursor.get("free_cursor_mode") == true

static func character_of(node: Node) -> Node3D:
	var current := node
	while current != null:
		if current.is_in_group(&"physical_characters_3d"):
			return current as Node3D
		current = current.get_parent()
	return null

static func controlled_character(node: Node) -> Node3D:
	var source := controller(node)
	if source != null:
		return source.get_controlled_character()
	if is_free_cursor_mode(node): return null
	var anchor := node.get_tree().get_first_node_in_group(&"npc_navigation_target")
	return character_of(anchor) if anchor != null else null

static func anchor(node: Node) -> Node3D:
	var source := controller(node)
	if source != null:
		return source.get_control_anchor()
	if is_free_cursor_mode(node): return null
	return node.get_tree().get_first_node_in_group(&"npc_navigation_target") as Node3D

static func input_allowed(node: Node) -> bool:
	if interface_open(node): return false
	var source := controller(node)
	if source == null: return not is_free_cursor_mode(node)
	return source.get_controlled_character() == character_of(node) and source.gameplay_input_allowed()

static func action_pressed(node: Node, action: StringName) -> bool:
	if not input_allowed(node): return false
	var source := controller(node)
	if source != null:
		return input_allowed(node) and source.is_gameplay_action_pressed(action)
	return Input.is_action_pressed(action)
