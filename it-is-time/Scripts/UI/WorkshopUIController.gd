extends Node

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

const WORKSHOP_SCENE: PackedScene = preload("res://Scenes/Workshop/Playerworkshop.tscn")
const BLUR_MASK_SCENE: PackedScene = preload("res://Scenes/Masks/BlurMask.tscn")
const WEAPON_TEST_SCENE: PackedScene = preload("res://Scenes/Items/Weapon_Test.tscn")
const INTERFACE_GROUP: StringName = &"ui_interface_2d"

@export_range(0.0, 2.0, 0.01) var transition_duration: float = 0.35
@export var minimum_workshop_layer: int = 100
@export_range(0.0, 100.0, 0.1, "or_greater") var weapon_spawn_height: float = 8.0

var _workshop: CanvasLayer
var _blur_mask: CanvasLayer
var _transitioning: bool = false
var _was_tree_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"BPressed") and not event.is_echo():
		get_viewport().set_input_as_handled()
		toggle_workshop()

func toggle_workshop() -> void:
	if _transitioning:
		return
	_workshop = _find_workshop()
	if is_instance_valid(_workshop) and _is_top_interface(_workshop):
		_close_workshop()
	else:
		_open_workshop()

func _open_workshop() -> void:
	_transitioning = true
	_was_tree_paused = get_tree().paused
	if not is_instance_valid(_workshop):
		_workshop = WORKSHOP_SCENE.instantiate() as CanvasLayer
		_get_ui_parent().add_child(_workshop)
	var build_callback := Callable(self, "_on_weapon_build_requested")
	if not _workshop.is_connected(&"weapon_build_requested", build_callback):
		_workshop.connect(&"weapon_build_requested", build_callback)
	_reset_right_panel()

	var previous_top_layer := _get_top_interface_layer(_workshop)
	_workshop.layer = maxi(minimum_workshop_layer, previous_top_layer + 2)
	_ensure_blur_mask()
	_blur_mask.layer = _workshop.layer - 1
	_blur_mask.show_mask()
	get_tree().paused = true

	var viewport_height := get_viewport().get_visible_rect().size.y
	_workshop.offset = Vector2(0.0, -viewport_height)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_workshop, "offset", Vector2.ZERO, transition_duration)
	tween.finished.connect(_finish_transition, CONNECT_ONE_SHOT)

func _close_workshop() -> void:
	_transitioning = true
	_reset_right_panel()
	var viewport_height := get_viewport().get_visible_rect().size.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_workshop, "offset", Vector2(0.0, -viewport_height), transition_duration)
	tween.finished.connect(_finish_close, CONNECT_ONE_SHOT)

func _finish_close() -> void:
	if is_instance_valid(_workshop):
		_workshop.remove_from_group(INTERFACE_GROUP)
		_workshop.queue_free()
	_workshop = null
	_reposition_or_remove_mask()
	_transitioning = false
	get_tree().paused = _was_tree_paused

func _finish_transition() -> void:
	_transitioning = false

func _on_weapon_build_requested(
	material_cells: Array[Vector2i],
	attachment_canvas_position: Vector2,
	attachment_grid_position: Vector2,
	item_rotation: float,
	holder_name: StringName
) -> void:
	if _transitioning or material_cells.is_empty():
		return
	var player_target := PLAYER_CONTEXT.anchor(self)
	if PLAYER_CONTEXT.controller(self) != null and PLAYER_CONTEXT.controlled_character(self) == null:
		push_warning("Cannot build an item while Controller is detached. Attach to a character first.")
		return
	if not is_instance_valid(player_target):
		push_warning("Cannot build Weapon_Test: Character_Test_2 target was not found.")
		return
	var weapon := WEAPON_TEST_SCENE.instantiate() as RigidBody3D
	if weapon == null:
		return
	_get_ui_parent().add_child(weapon)
	weapon.global_position = player_target.global_position + Vector3.UP * weapon_spawn_height
	weapon.call(
		&"build_from_material_cells",
		material_cells,
		attachment_canvas_position,
		attachment_grid_position,
		item_rotation,
		holder_name,
		true
	)
	_close_workshop()

func _reset_right_panel() -> void:
	if not is_instance_valid(_workshop):
		return
	var right_panel := _workshop.get_node_or_null("WorkshopRightpanel")
	if right_panel != null and right_panel.has_method("reset_to_default"):
		right_panel.reset_to_default()

func _ensure_blur_mask() -> void:
	_blur_mask = _find_blur_mask()
	if is_instance_valid(_blur_mask):
		return
	_blur_mask = BLUR_MASK_SCENE.instantiate() as CanvasLayer
	_get_ui_parent().add_child(_blur_mask)

func _reposition_or_remove_mask() -> void:
	_blur_mask = _find_blur_mask()
	if not is_instance_valid(_blur_mask):
		return
	var top_interface := _get_top_interface()
	if top_interface == null:
		_blur_mask.queue_free()
		_blur_mask = null
		return
	_blur_mask.layer = top_interface.layer - 1
	_blur_mask.show_mask()

func _find_workshop() -> CanvasLayer:
	for node: Node in get_tree().get_nodes_in_group(&"player_workshop"):
		if node is CanvasLayer and not node.is_queued_for_deletion():
			return node as CanvasLayer
	return null

func _find_blur_mask() -> CanvasLayer:
	for node: Node in get_tree().get_nodes_in_group(&"blur_mask"):
		if node is CanvasLayer and not node.is_queued_for_deletion():
			return node as CanvasLayer
	return null

func _is_top_interface(interface: CanvasLayer) -> bool:
	return _get_top_interface() == interface

func _get_top_interface(excluded: CanvasLayer = null) -> CanvasLayer:
	var top_interface: CanvasLayer
	for node: Node in get_tree().get_nodes_in_group(INTERFACE_GROUP):
		if node is not CanvasLayer or node == excluded or node.is_queued_for_deletion():
			continue
		var interface := node as CanvasLayer
		if not interface.visible:
			continue
		if top_interface == null or interface.layer > top_interface.layer:
			top_interface = interface
	return top_interface

func _get_top_interface_layer(excluded: CanvasLayer = null) -> int:
	var top_interface := _get_top_interface(excluded)
	return top_interface.layer if top_interface != null else 0

func _get_ui_parent() -> Node:
	return get_tree().current_scene if get_tree().current_scene != null else get_tree().root
