class_name SampleFloatingText3D
extends Node3D

signal finished

@export_group("Motion")
@export_range(0.05, 10.0, 0.05, "or_greater") var lifetime: float = 0.9
@export_range(0.0, 20.0, 0.05, "or_greater") var rise_speed: float = 1.25
@export_range(0.0, 1.0, 0.01) var fade_start_ratio: float = 0.5

@export_group("Text")
@export var label_path: NodePath = NodePath("Label3D")

var _elapsed: float = 0.0
var _display_color: Color = Color.WHITE

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
	global_position += Vector3.UP * rise_speed * delta
	var safe_lifetime := maxf(lifetime, 0.001)
	var fade_start := safe_lifetime * clampf(fade_start_ratio, 0.0, 1.0)
	var alpha := 1.0
	if _elapsed > fade_start:
		alpha = 1.0 - inverse_lerp(fade_start, safe_lifetime, _elapsed)
	_set_alpha(clampf(alpha, 0.0, 1.0))
	if _elapsed >= safe_lifetime:
		finished.emit()
		queue_free()

func _get_label() -> Label3D:
	if is_instance_valid(_label):
		return _label
	return get_node_or_null(label_path) as Label3D

func _apply_display_color() -> void:
	var label := _get_label()
	if label != null:
		label.modulate = _display_color

func _set_alpha(alpha: float) -> void:
	var label := _get_label()
	if label == null:
		return
	var color := _display_color
	color.a *= alpha
	label.modulate = color
