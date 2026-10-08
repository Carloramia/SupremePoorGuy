class_name ScenarioOverlay
extends Node

# The integration layer owns both modules; neither controller changes scenes.
var world_map: WorldMapController
var overlay: CanvasLayer
var frame: PanelContainer
var viewport_container: SubViewportContainer
var viewport: SubViewport
var scenario: ScenarioController
var return_button: Button
var active_location_id: StringName = &""

func _ready() -> void:
	world_map = get_parent() as WorldMapController
	if not world_map:
		push_error("ScenarioOverlay requires a WorldMapController parent")
		return
	if not world_map.is_initialized:
		await world_map.initialized
	world_map.interaction.scenario_requested.connect(open_scenario)
	world_map.location_interaction_completed.connect(_interaction_completed)

func open_scenario(location_id: StringName, packed_scene: PackedScene) -> bool:
	if overlay or not world_map.paused or not world_map.interaction.active_location:
		return false
	if world_map.interaction.active_location.location_id != location_id or not packed_scene:
		return false
	var instance := packed_scene.instantiate()
	if not instance is ScenarioController:
		instance.free()
		world_map.ui.notify("无法进入：目标场景必须使用 ScenarioController")
		return false
	scenario = instance
	active_location_id = location_id
	scenario.scenario_exit_requested.connect(finish_scenario)
	overlay = CanvasLayer.new()
	overlay.name = "ScenarioWindow"
	overlay.layer = 30
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.04, 0.06, 0.35)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(backdrop)
	frame = PanelContainer.new()
	frame.name = "FloatingFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.anchor_left = 0.05
	frame.anchor_right = 0.95
	frame.anchor_top = 0.06
	frame.anchor_bottom = 0.94
	var style := StyleBoxFlat.new()
	style.bg_color = Color("142530")
	style.border_color = Color("526e70")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	frame.add_theme_stylebox_override("panel", style)
	overlay.add_child(frame)
	var content := VBoxContainer.new()
	frame.add_child(content)
	var title_bar := HBoxContainer.new()
	content.add_child(title_bar)
	var title := Label.new()
	title.text = world_map.interaction.active_location.definition.display_name + " / 2.5D"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)
	return_button = Button.new()
	return_button.text = "返回大地图 / Return"
	return_button.custom_minimum_size.y = 38
	return_button.pressed.connect(func() -> void: scenario.request_scenario_exit(&"return_to_map"))
	title_bar.add_child(return_button)
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "ScenarioView"
	viewport_container.stretch = true
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(viewport_container)
	viewport = SubViewport.new()
	viewport.name = "ScenarioViewport"
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)
	add_child(overlay)
	viewport.add_child(scenario)
	if not scenario.initialized:
		_close_overlay()
		world_map.ui.notify("场景初始化失败，请检查控制器配置")
		return false
	# Keep the modal's shade, but hide its actions while the scenario is active.
	world_map.interaction.panel.hide()
	return true

func finish_scenario(reason: StringName = &"return_to_map") -> void:
	if not overlay:
		return
	var location_id := active_location_id
	_close_overlay()
	# End exactly one visit. Returning does not consume a repeatable town.
	world_map.resolve_location_interaction(location_id, {
		"success": true, "action": "scenario_exit", "complete_location": false,
		"custom_data": {"scenario_exit_reason": String(reason)}
	})

func _interaction_completed(_id: StringName, _result: Dictionary) -> void:
	# Also clean up if an external system resolves the interaction while embedded.
	if overlay:
		_close_overlay()

func _close_overlay() -> void:
	if scenario and is_instance_valid(scenario):
		scenario.scenario_exit_requested.disconnect(finish_scenario)
	if overlay:
		remove_child(overlay)
		overlay.queue_free()
	overlay = null
	scenario = null
	viewport = null
	viewport_container = null
	frame = null
	return_button = null
	active_location_id = &""
