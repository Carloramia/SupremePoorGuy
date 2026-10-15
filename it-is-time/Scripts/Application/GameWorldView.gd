@tool
extends "res://Modules/PaperUI/Scripts/UI/WorldView.gd"

func _layout() -> void:
	hide_location_hint()
	$Backdrop.hide()
	for marker: Button in markers: marker.hide()
	if is_instance_valid(summon_book): summon_book.hide()
	queue_redraw()

func _draw() -> void:
	if mode == "eruption": super._draw()
	else: draw_rect(Rect2(Vector2.ZERO,size),Style.PAPER)

