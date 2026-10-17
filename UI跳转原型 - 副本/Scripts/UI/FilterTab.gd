extends Button
## Two staggered rails reserve room for future icon filters. Only position changes on activation.
@export var extension := 12.0
var resting_x := 0.0
var movement: Tween

func _ready() -> void:
	resting_x = position.x

func set_active(active: bool, animate := true) -> void:
	set_pressed_no_signal(active)
	if movement:
		movement.kill()
	var target := resting_x + (extension if active else 0.0)
	if animate:
		movement = create_tween()
		movement.tween_property(self,"position:x",target,0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		position.x = target
