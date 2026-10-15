extends Control
## Visual-only animation. This component never changes monsters, cost or save data.
signal completed(kind: String)
@export var enabled := true
var busy := false
var horizontal := false
var slide: Tween
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
	if horizontal:
		motion.position.x = -get_viewport_rect().size.x if kind == "enter" else 0.0
		slide = create_tween()
		slide.set_parallel(true)
		slide.tween_property(motion,"position:x",0.0 if kind == "enter" else -get_viewport_rect().size.x,0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if kind == "exit":
			slide.tween_property(motion,"modulate:a",0.0,0.4)
		slide.set_parallel(false)
		slide.tween_callback(func(): _finished(kind))
		return
	animator.play(kind)
	animator.advance(0)

func snap() -> void:
	if slide:
		slide.kill()
	animator.stop()
	motion.position = Vector2.ZERO
	motion.modulate.a = 1.0
	busy = false
	shield.hide()

func _finished(kind: StringName) -> void:
	busy = false
	shield.hide()
	completed.emit(String(kind))

func _input(event: InputEvent) -> void:
	if busy and (event is InputEventKey or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()
