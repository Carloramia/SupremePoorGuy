extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var workshop: CanvasLayer = load("res://Scenes/Workshop/Playerworkshop.tscn").instantiate()
	root.add_child(workshop)
	await process_frame
	assert(workshop.is_in_group(&"ui_interface_2d"))
	var grid: TileMapLayer = workshop.get_node("WorkspaceContent/GridBackground")
	var material_grid: TileMapLayer = workshop.get_node("WorkspaceContent/MaterialGrid")
	var grid_input: Control = workshop.get_node("GridInput")
	var right_panel: Control = workshop.get_node("WorkshopRightpanel")
	var build_button := workshop.get_node("WorkshopBuildButton") as Button
	assert(grid.tile_set != null)
	assert(grid.tile_set.get_source_count() == 1)
	assert(not grid.get_used_cells().is_empty())
	assert(grid.z_index < 0)
	assert(material_grid.tile_set != null)
	assert(material_grid.get_used_cells().is_empty())
	assert(grid_input.mouse_filter == Control.MOUSE_FILTER_STOP)
	assert(not right_panel.is_expanded())
	assert(build_button.anchor_left == 0.5 and build_button.anchor_top == 1.0)
	assert(build_button.disabled)
	right_panel.select_test_material()
	assert(workshop.get_selected_material() == &"TestMaterial")
	var placement_position := Vector2(96.0, 160.0)
	var placement_cell := material_grid.local_to_map(material_grid.to_local(placement_position))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = placement_position
	grid_input.gui_input.emit(click)
	assert(workshop.has_material_at_cell(placement_cell))
	assert(not build_button.disabled)
	assert(workshop.get_placed_material_cells() == [placement_cell])
	var initial_zoom: float = workshop.get_canvas_zoom()
	var zoom_event := InputEventMouseButton.new()
	zoom_event.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom_event.pressed = true
	zoom_event.position = Vector2(320.0, 240.0)
	grid_input.gui_input.emit(zoom_event)
	assert(workshop.get_canvas_zoom() > initial_zoom)
	var offset_before_drag: Vector2 = workshop.get_canvas_offset()
	var middle_press := InputEventMouseButton.new()
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.pressed = true
	grid_input.gui_input.emit(middle_press)
	var drag_event := InputEventMouseMotion.new()
	drag_event.relative = Vector2(25.0, -15.0)
	grid_input.gui_input.emit(drag_event)
	assert(workshop.get_canvas_offset().is_equal_approx(offset_before_drag + Vector2(25.0, -15.0)))
	var middle_release := InputEventMouseButton.new()
	middle_release.button_index = MOUSE_BUTTON_MIDDLE
	middle_release.pressed = false
	grid_input.gui_input.emit(middle_release)
	print("PLAYER_WORKSHOP_VALIDATION_PASSED")
	workshop.queue_free()
	quit()
