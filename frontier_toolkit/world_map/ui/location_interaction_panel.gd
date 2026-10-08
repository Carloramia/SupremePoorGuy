class_name LocationInteractionPanel
extends PanelContainer

signal interaction_completed(result: Dictionary)
signal battle_start_requested
signal scenario_start_requested
var content: VBoxContainer
var location: WorldMapLocation

func setup(selected_location: WorldMapLocation) -> void:
	location = selected_location
	custom_minimum_size = Vector2(440, 240)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)
	var heading := Label.new()
	heading.text = location.definition.display_name
	heading.add_theme_font_size_override("font_size", 26)
	content.add_child(heading)
	var description := Label.new()
	description.text = location.definition.short_description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 380
	content.add_child(description)
	build_actions()

func build_actions() -> void:
	pass

func add_action(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.pressed.connect(action)
	content.add_child(button)
	return button

func complete(action: String, complete_location: bool, custom_data: Dictionary = {}) -> void:
	interaction_completed.emit({"success": true, "action": action, "complete_location": complete_location, "custom_data": custom_data})
