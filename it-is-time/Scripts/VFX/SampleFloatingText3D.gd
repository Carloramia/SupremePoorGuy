class_name SampleFloatingText3D
extends Node3D

signal finished

@export_group("Motion")
@export_range(0.05, 10.0, 0.05, "or_greater") var lifetime: float = 0.9
@export_range(0.0, 20.0, 0.05, "or_greater") var rise_speed: float = 1.25
@export_range(0.0, 1.0, 0.01) var fade_in_ratio: float = 0.2
@export_range(0.0, 1.0, 0.01) var fade_start_ratio: float = 0.5

@export_group("Text")
@export var label_path: NodePath = NodePath("Label3D")

var _elapsed: float = 0.0
var _display_color: Color = Color.WHITE
var _alpha: float = 0.0
var _outline_alpha: float = -1.0
var _rise_offset: float = 0.0

@onready var _label: Label3D = get_node_or_null(label_path) as Label3D

func _ready() -> void:
	add_to_group(&"floating_text_3d")
	_apply_display_color()

func setup_text(value: String, color: Color = Color.WHITE) -> void:
	_display_color = color
	var label := _get_label()
	if label != null:
		label.text = value
		_apply_display_color()

func get_display_text() -> String:
	var label := _get_label()
	return label.text if label != null else ""

func _process(delta: float) -> void:
	_elapsed += delta
	var safe_lifetime := maxf(lifetime, 0.001)
	var fade_start := safe_lifetime * clampf(fade_start_ratio, 0.0, 1.0)
	var fade_in := minf(safe_lifetime * clampf(fade_in_ratio, 0.0, 1.0), fade_start)
	var fade_out := safe_lifetime - fade_start
	var entering := clampf(_elapsed / fade_in, 0.0, 1.0) if fade_in > 0.0 else 1.0
	var leaving := clampf((_elapsed - fade_start) / fade_out, 0.0, 1.0) if fade_out > 0.0 else float(_elapsed >= safe_lifetime)
	entering = 1.0 - pow(1.0 - entering, 3.0)
	leaving = pow(leaving, 3.0)
	# Keep position still during the readable hold between the two eased movements.
	var rise := rise_speed * (fade_in * entering + fade_out * leaving)
	global_position += Vector3.UP * (rise - _rise_offset)
	_rise_offset = rise
	_set_alpha(entering * (1.0 - leaving))
	if _elapsed >= safe_lifetime:
		finished.emit()
		queue_free()

func _get_label() -> Label3D:
	if is_instance_valid(_label):
		return _label
	return get_node_or_null(label_path) as Label3D

func _apply_display_color() -> void:
	_set_alpha(_alpha)

func _set_alpha(alpha: float) -> void:
	_alpha = alpha
	var label := _get_label()
	if label == null:
		return
	if _outline_alpha < 0.0:
		_outline_alpha = label.outline_modulate.a
	var color := _display_color
	color.a *= alpha
	label.modulate = color
	var outline := label.outline_modulate
	outline.a = _outline_alpha * _display_color.a * alpha
	label.outline_modulate = outline
