extends Control

signal expanded_changed(is_expanded: bool)
signal material_selected(material_id: StringName)

@export_range(120.0, 800.0, 1.0) var panel_width: float = 360.0
@export_range(0.0, 2.0, 0.01) var transition_duration: float = 0.28

@onready var _tab_button: Button = $TabButton
@onready var _test_material_button: Button = $Panel/Margin/Content/testMaterial

var _is_expanded: bool = false
var _transition: Tween

func _ready() -> void:
	_tab_button.pressed.connect(toggle_panel)
	_test_material_button.pressed.connect(_select_test_material)
	reset_to_default()

func _select_test_material() -> void:
	_test_material_button.set_pressed_no_signal(true)
	material_selected.emit(&"TestMaterial")

func select_test_material() -> void:
	_select_test_material()

func is_test_material_selected() -> bool:
	return _test_material_button.button_pressed

func toggle_panel() -> void:
	set_expanded(not _is_expanded)

func set_expanded(value: bool, animated: bool = true) -> void:
	_is_expanded = value
	if is_instance_valid(_transition):
		_transition.kill()

	var target_left := -panel_width if value else 0.0
	var target_right := 0.0 if value else panel_width
	if not animated or transition_duration <= 0.0:
		offset_left = target_left
		offset_right = target_right
		expanded_changed.emit(_is_expanded)
		return

	_transition = create_tween().set_parallel(true)
	_transition.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT if value else Tween.EASE_IN
	)
	_transition.tween_property(self, "offset_left", target_left, transition_duration)
	_transition.tween_property(self, "offset_right", target_right, transition_duration)
	_transition.chain().tween_callback(expanded_changed.emit.bind(_is_expanded))

func reset_to_default() -> void:
	set_expanded(false, false)

func is_expanded() -> bool:
	return _is_expanded
