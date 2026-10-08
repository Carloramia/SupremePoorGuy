class_name FakeBattleAdapter
extends Node

@export var world_map_path: NodePath = NodePath("..")
var world_map: WorldMapController
var overlay: CanvasLayer
var request: Dictionary = {}

func _ready() -> void:
	world_map = get_node(world_map_path) as WorldMapController
	world_map.battle_requested.connect(_on_battle_requested)

func _on_battle_requested(data: Dictionary) -> void:
	request = data
	overlay = CanvasLayer.new()
	overlay.layer = 30
	add_child(overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.04, 0.06, 0.08, 0.98)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)
	var title := Label.new()
	title.text = "EXTERNAL BATTLE / DEMO ADAPTER"
	title.add_theme_font_size_override("font_size", 27)
	box.add_child(title)
	var detail := Label.new()
	detail.text = "Encounter: %s\nWorldMap is paused. Choose an external result." % data.location_id
	box.add_child(detail)
	for result_type: String in ["victory", "defeat", "error"]:
		var button := Button.new()
		button.text = result_type.capitalize()
		button.custom_minimum_size.y = 48
		button.pressed.connect(func() -> void: return_result(result_type))
		box.add_child(button)

func return_result(result_type: String) -> void:
	world_map.resolve_location_interaction(StringName(request.location_id), {"success": result_type == "victory", "result_type": result_type, "complete_location": result_type == "victory", "rewards": {}, "custom_data": {"adapter": "fake"}})
	if overlay:
		overlay.queue_free()
		overlay = null
	request = {}
