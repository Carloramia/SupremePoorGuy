extends RefCounted

static func controller(node: Node) -> Node:
	return node.get_tree().get_first_node_in_group(&"player_controller_3d") if node.is_inside_tree() else null

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
	var anchor := node.get_tree().get_first_node_in_group(&"npc_navigation_target")
	return character_of(anchor) if anchor != null else null

static func anchor(node: Node) -> Node3D:
	var source := controller(node)
	if source != null:
		return source.get_control_anchor()
	return node.get_tree().get_first_node_in_group(&"npc_navigation_target") as Node3D

static func input_allowed(node: Node) -> bool:
	var source := controller(node)
	return source == null or (source.get_controlled_character() == character_of(node) and source.gameplay_input_allowed())

static func action_pressed(node: Node, action: StringName) -> bool:
	var source := controller(node)
	if source != null:
		return input_allowed(node) and source.is_gameplay_action_pressed(action)
	return Input.is_action_pressed(action)
