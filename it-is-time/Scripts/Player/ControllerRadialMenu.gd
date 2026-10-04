extends CanvasLayer

signal option_chosen(action: StringName)

@export_range(60.0, 400.0, 1.0) var outer_radius: float = 150.0
@export_range(10.0, 200.0, 1.0) var inner_radius: float = 55.0
@export var background_color: Color = Color(0.12, 0.14, 0.18, 0.65)
@export var highlight_color: Color = Color(0.25, 0.65, 0.9, 0.8)
@export var text_color: Color = Color.WHITE
@export_range(12, 48, 1) var font_size: int = 22
@export_range(0.0, 1.0, 0.01) var popup_duration: float = 0.12

var options: Array[ControllerWheelOption] = []
var hovered_index: int = -1
var screen_center: Vector2 = Vector2.ZERO
var _view: Node2D
var _tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	add_to_group(&"ui_interface_2d")
	_view = Node2D.new()
	_view.set_script(preload("res://Scripts/Player/ControllerRadialMenuView.gd"))
	add_child(_view)
	_view.menu = self
	visible = false

func open_at(center: Vector2, entries: Array[ControllerWheelOption]) -> void:
	options = entries
	hovered_index = -1
	var viewport_size := get_viewport().get_visible_rect().size
	var padding := Vector2.ONE * (outer_radius + 12.0)
	screen_center = center.clamp(padding.min(viewport_size * 0.5), (viewport_size - padding).max(viewport_size * 0.5))
	_view.position = screen_center
	visible = true
	if is_instance_valid(_tween): _tween.kill()
	_view.scale = Vector2.ONE * 0.65
	_view.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_view, "scale", Vector2.ONE, popup_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_view, "modulate:a", 1.0, popup_duration)
	_view.queue_redraw()

func pick_at(screen_position: Vector2) -> int:
	var offset := screen_position - screen_center
	if options.is_empty() or offset.length() < inner_radius or offset.length() > outer_radius:
		return -1
	var angle := fposmod(offset.angle() + PI * 0.5 + PI / options.size(), TAU)
	var index := mini(int(angle / (TAU / options.size())), options.size() - 1)
	return index if options[index] != null and options[index].enabled else -1

func _process(_delta: float) -> void:
	if not visible: return
	var picked := pick_at(get_viewport().get_mouse_position())
	if picked != hovered_index:
		hovered_index = picked
		_view.queue_redraw()

func close_menu(commit: bool = false) -> void:
	var chosen: StringName = &""
	if commit and hovered_index >= 0 and hovered_index < options.size() and options[hovered_index].enabled:
		chosen = options[hovered_index].action
	visible = false
	if is_instance_valid(_tween): _tween.kill()
	if not chosen.is_empty(): option_chosen.emit(chosen)

func set_character_control_enabled(_enabled: bool) -> void:
	# This UI belongs to the persistent player, not to the possessed body.
	pass
