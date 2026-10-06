extends CanvasLayer

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

var _inventory: Node
var _slots: Array[PanelContainer] = []
var _icons: Array[TextureRect] = []

func _ready() -> void:
	if not bool(get_parent().get("inventory_ui_enabled")):
		visible = false
		set_process(false)
		return
	layer = 50
	_build_ui()

func bind_inventory(inventory: Node) -> void:
	_inventory = inventory
	if not inventory.inventory_changed.is_connected(_on_inventory_changed):
		inventory.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed(inventory.get_items(), inventory.get_selected_slot())

func _process(_delta: float) -> void:
	visible = not _is_external_interface_open() and (PLAYER_CONTEXT.controller(self) == null or PLAYER_CONTEXT.controlled_character(self) == PLAYER_CONTEXT.character_of(self))

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bar := HBoxContainer.new()
	bar.name = "Slots"
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position = Vector2(-158.0, -86.0)
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	for index: int in 4:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(72.0, 72.0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(panel)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)
		var number := Label.new()
		number.text = str(index + 1)
		number.position = Vector2(6.0, 3.0)
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(number)
		_slots.append(panel)
		_icons.append(icon)

func _on_inventory_changed(items: Array, selected_slot: int) -> void:
	for index: int in range(_slots.size()):
		var selected := index == selected_slot
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.14, 0.9)
		style.border_width_left = 3 if selected else 1
		style.border_width_top = 3 if selected else 1
		style.border_width_right = 3 if selected else 1
		style.border_width_bottom = 3 if selected else 1
		style.border_color = Color.WHITE if selected else Color(0.55, 0.55, 0.58, 1.0)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		_slots[index].add_theme_stylebox_override("panel", style)
		var item := items[index] as SampleItem3D if index < items.size() else null
		_icons[index].texture = item.get_item_image() if is_instance_valid(item) else null

func _is_external_interface_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"ui_interface_2d"):
		if node is CanvasLayer and (node as CanvasLayer).visible and not node.is_queued_for_deletion():
			return true
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	return console != null and console.has_method("is_console_open") and bool(console.call("is_console_open"))
