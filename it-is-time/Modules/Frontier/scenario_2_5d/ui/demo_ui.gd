extends CanvasLayer

@export var scenario: ScenarioController
@export var hero: Node3D
var status: Label
var info: Label
var info_panel: PanelContainer
var interact: Button
var mode_button: Button
var fade_button: Button
var marker: MeshInstance3D
var behind: bool = true

func _ready() -> void:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	var theme := Theme.new()
	theme.default_font_size = 18
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202c30")
	style.border_color = Color("b7aa83")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	theme.set_stylebox("panel", "PanelContainer", style)
	screen.theme = theme
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(345, 0)
	screen.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	var title := Label.new()
	title.text = "PAPER OUTPOST   /   2.5D"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color("e6d4a5"))
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Middle mouse · drag\nWheel · smooth zoom\nLeft click · select / ground event"
	box.add_child(hint)
	mode_button = _button(box, "Mode: EXPLORE", func() -> void:
		scenario.set_scene_mode(SceneMode.Mode.COMBAT if scenario.get_scene_mode() == SceneMode.Mode.EXPLORE else SceneMode.Mode.EXPLORE))
	_button(box, "Hero: behind / in front", func() -> void:
		behind = not behind
		hero.position = Vector3(-5, 0, -3.2) if behind else Vector3(-5, 0, 4)
		status.text = "Hero moved to " + ("behind building" if behind else "in front of building"))
	fade_button = _button(box, "Occlusion fade: ON", func() -> void:
		scenario.occlusion_controller.enabled = not scenario.occlusion_controller.enabled
		fade_button.text = "Occlusion fade: " + ("ON" if scenario.occlusion_controller.enabled else "OFF"))
	_button(box, "Focus hero", func() -> void:
		scenario.set_focus_target(hero)
		scenario.focus_on_target())
	var lock := CheckButton.new()
	lock.text = "Lock camera input"
	lock.toggled.connect(func(value: bool) -> void: scenario.set_camera_input_enabled(not value))
	box.add_child(lock)
	info_panel = PanelContainer.new()
	screen.add_child(info_panel)
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	info_panel.offset_left = -354
	info_panel.offset_right = -24
	info_panel.offset_top = 24
	info_panel.custom_minimum_size = Vector2(330, 0)
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 12)
	info_panel.add_child(info_box)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 288
	info_box.add_child(info)
	interact = _button(info_box, "Interact · emit request", func() -> void:
		var object := scenario.interaction_controller.selected
		if is_instance_valid(object):
			object.request_interaction())
	info_panel.hide()
	var footer := PanelContainer.new()
	screen.add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 24
	footer.offset_right = -24
	footer.offset_top = -72
	footer.offset_bottom = -24
	status = Label.new()
	status.text = "Ready · Toggle fade OFF to verify true depth occlusion."
	footer.add_child(status)
	scenario.interaction_controller.interactable_selected.connect(_selection)
	scenario.scene_mode_changed.connect(func(mode: SceneMode.Mode) -> void: mode_button.text = "Mode: " + ("EXPLORE" if mode == SceneMode.Mode.EXPLORE else "COMBAT"))
	scenario.interaction_requested.connect(func(id: StringName, _data: InteractableDefinition, _state: InteractableRuntimeState) -> void: status.text = "interaction_requested: " + String(id))
	scenario.explore_ground_clicked.connect(func(point: Vector3) -> void: _ground(point, "explore_ground_clicked"))
	scenario.combat_ground_clicked.connect(func(point: Vector3) -> void: _ground(point, "combat_ground_clicked"))
	marker = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.22
	mesh.bottom_radius = 0.22
	mesh.height = 0.035
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("e8b56b")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat
	scenario.add_child.call_deferred(marker)
	marker.hide()

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _selection(object: Interactable3D) -> void:
	info_panel.visible = is_instance_valid(object)
	if object:
		var data := object.definition
		info.text = "%s\n\nType: %s\nID: %s\n\n%s" % [data.display_name, data.interaction_type, data.object_id, data.description]

func _ground(point: Vector3, event_name: String) -> void:
	status.text = "%s  (%.2f, %.2f, %.2f)" % [event_name, point.x, point.y, point.z]
	marker.position = point + Vector3(0, 0.03, 0)
	marker.show()
