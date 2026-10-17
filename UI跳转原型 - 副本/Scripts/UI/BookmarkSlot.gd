extends Control
## Reserve layout space while the bookmark translates; never scale its paper or text.
var movement: Tween
var wanted := false
@onready var button: Button = get_child(0)

func _ready() -> void:
	wanted = visible
	clip_contents = true

func set_present(present: bool, animate := true, delay := 0.0) -> void:
	if wanted == present and visible == present and not movement:
		return
	wanted = present
	if movement:
		movement.kill()
		movement = null
	if not animate:
		visible = present
		button.position.x = 0
		button.modulate.a = 1
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		return
	if present and not visible:
		button.position.x = -maxf(size.x,custom_minimum_size.x)
		button.modulate.a = 0
		show()
	if not visible:
		return
	button.mouse_filter = Control.MOUSE_FILTER_STOP if present else Control.MOUSE_FILTER_IGNORE
	movement = create_tween()
	movement.set_parallel(true)
	movement.tween_property(button,"position:x",0.0 if present else -maxf(size.x,custom_minimum_size.x),0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
	movement.tween_property(button,"modulate:a",1.0 if present else 0.0,0.2).set_delay(delay)
	movement.set_parallel(false)
	movement.tween_callback(func():
		visible = wanted
		button.position.x = 0
		button.modulate.a = 1
		movement = null)
