extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var panel: Control = load("res://Scenes/Workshop/WorkshopRightpanel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	assert(not panel.is_expanded())
	assert(is_equal_approx(panel.offset_left, 0.0))
	assert(is_equal_approx(panel.offset_right, panel.panel_width))
	panel.set_expanded(true, false)
	assert(panel.is_expanded())
	assert(is_equal_approx(panel.offset_left, -panel.panel_width))
	assert(is_equal_approx(panel.offset_right, 0.0))
	panel.reset_to_default()
	assert(not panel.is_expanded())
	assert(panel.get_node("TabButton") is Button)
	var selected_materials: Array[StringName] = []
	panel.material_selected.connect(func(material_id: StringName) -> void: selected_materials.append(material_id))
	panel.select_test_material()
	assert(selected_materials == [&"TestMaterial"])
	assert(panel.is_test_material_selected())
	var material_button := panel.get_node("Panel/Margin/Content/testMaterial") as Button
	assert(material_button.text == "TestMaterial")
	assert(material_button.icon != null)
	print("WORKSHOP_RIGHT_PANEL_VALIDATION_PASSED")
	panel.queue_free()
	quit()
