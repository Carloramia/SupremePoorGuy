extends Node2D
## Cosmetic rain is driven by the same authoritative rule as the summon modifier.
var map: Control
var elapsed:=0.0
func _process(delta: float) -> void:
	elapsed+=delta
	visible=preload("res://Scripts/Events/HexMapProgress.gd").rain_active(map.application.session.data)
	if visible: queue_redraw()
func _draw() -> void:
	for i in 70:
		var x:=fmod(i*137.7+elapsed*90,map.size.x+80)-40
		var y:=fmod(i*83.3+elapsed*520,map.size.y+60)-30
		draw_line(Vector2(x,y),Vector2(x-5,y+18),Color(.65,.07,.13,.55),1.5,true)
