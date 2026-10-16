@tool
extends Button
## Native Button owns input/focus/text. Shader layers are mouse-ignoring children.
@export var profile: Resource = preload("res://ui_module/shader_lab/presets/medium.tres"):
	set(value):
		profile = value
		_sync()
var hovered := false
var last_disabled := false

func _ready() -> void:
	mouse_entered.connect(func(): hovered = true; _sync())
	mouse_exited.connect(func(): hovered = false; _sync())
	button_down.connect(_sync)
	button_up.connect(_sync)
	focus_entered.connect(_sync)
	focus_exited.connect(_sync)
	_sync()

func _sync() -> void:
	if not is_node_ready():
		return
	$Paper.profile = profile
	$Ink.profile = profile
	$Focus.profile = profile
	last_disabled = disabled
	var tint := Color("#e9dec3")
	if disabled:
		tint = Color("#c4c3b7")
	elif is_pressed():
		tint = Color("#b9c3a1")
	elif hovered:
		tint = Color("#f1e5c8")
	$Paper.paper_color = tint
	$Ink.modulate = Color(1, 1, 1, 0.45 if disabled else 1.0)
	$Focus.visible = has_focus()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and is_node_ready() and disabled != last_disabled:
		# disabled can change from another script, without a signal.
		_sync()
