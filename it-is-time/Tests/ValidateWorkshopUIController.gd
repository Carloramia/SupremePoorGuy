extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var controller: Node = root.get_node("WorkshopUIController")
	controller.transition_duration = 0.01
	var player_target := Node3D.new()
	player_target.name = "TestPlayerTorso"
	player_target.position = Vector3(2.0, 3.0, 4.0)
	player_target.add_to_group(&"npc_navigation_target")
	root.add_child(player_target)
	controller.toggle_workshop()
	await create_timer(0.15).timeout

	var workshops := get_nodes_in_group(&"player_workshop")
	var masks := get_nodes_in_group(&"blur_mask")
	assert(workshops.size() == 1)
	assert(masks.size() == 1)
	var workshop := workshops[0] as CanvasLayer
	var mask := masks[0] as CanvasLayer
	assert(workshop.offset.is_equal_approx(Vector2.ZERO))
	assert(mask.layer == workshop.layer - 1)
	assert(paused)

	workshop.get_node("WorkshopRightpanel").select_test_material()
	assert(workshop.place_selected_material_at_screen_position(Vector2(64.0, 64.0)))
	workshop.get_node("WorkshopRightpanel").select_holder()
	assert(workshop.place_attachment_at_screen_position(Vector2(64.0, 64.0)))
	var build_button := workshop.get_node("WorkshopBuildButton") as Button
	build_button.pressed.emit()
	await create_timer(0.15).timeout
	await process_frame
	assert(get_nodes_in_group(&"player_workshop").is_empty())
	assert(get_nodes_in_group(&"blur_mask").is_empty())
	assert(not paused)
	var weapon := root.get_node_or_null("WeaponTest") as RigidBody3D
	assert(weapon != null)
	assert(weapon.get_material_cells().size() == 1)
	assert(weapon.get_generated_collision_count() == 1)
	assert(weapon.has_attachment_point)
	assert(weapon.preferred_holder_name == &"Arm_R")
	assert(is_equal_approx(weapon.global_position.x, player_target.global_position.x))
	assert(is_equal_approx(weapon.global_position.z, player_target.global_position.z))
	assert(weapon.global_position.y > player_target.global_position.y)
	print("WORKSHOP_UI_CONTROLLER_VALIDATION_PASSED")
	weapon.queue_free()
	player_target.queue_free()
	quit()
