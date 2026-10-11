extends Control
## Visual-only animation. This component never changes monsters, cost or save data.
signal completed(kind: String)
@export var enabled := true
var busy := false
@onready var motion: Control = $MotionRoot
@onready var animator: AnimationPlayer = $AnimationPlayer
@onready var shield: Control = $InputShield

func _ready() -> void:
	animator.animation_finished.connect(_finished)
	snap()

func reveal() -> void:
	_play("enter")

func dismiss() -> void:
	_play("exit")

func _play(kind: String) -> void:
	snap()
	if not enabled:
		completed.emit(kind)
		return
	busy = true
	shield.show()
	get_viewport().gui_release_focus()
	animator.play(kind)
	animator.advance(0)

func snap() -> void:
	animator.stop()
	motion.position = Vector2.ZERO
	busy = false
	shield.hide()

func _finished(kind: StringName) -> void:
	busy = false
	shield.hide()
	completed.emit(String(kind))

func _input(event: InputEvent) -> void:
	if busy and (event is InputEventKey or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()
