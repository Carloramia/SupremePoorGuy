extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	root.add_child(character)
	for body_name: StringName in [&"Torso", &"Leg_R", &"Leg_L", &"Arm_R", &"Arm_L", &"Head"]:
		(character.get_node(NodePath(body_name)) as RigidBody3D).freeze = true
	var inventory := character.get_node("InventoryController3D")
	var arm := character.get_node("Arm_R") as RigidBody3D
	var original_arm_mass: float = arm.mass
	var original_arm_inertia: Vector3 = arm.inertia
	var original_center_mode: int = arm.center_of_mass_mode
	var external_body := StaticBody3D.new()
	external_body.name = "ExternalTerrainOrCharacterBody"
	root.add_child(external_body)
	assert(inventory.capacity == 4)
	assert(is_equal_approx(inventory.pickup_radius, 6.0))
	var pickup_sphere := (
		inventory.get_node("PickupArea3D/CollisionShape3D") as CollisionShape3D
	).shape as SphereShape3D
	assert(is_equal_approx(pickup_sphere.radius, 6.0))
	assert(inventory.get_selected_slot() == 0)
	assert(character.has_node("Arm_R/ItemSocket3D"))
	var item := load("res://Scenes/Items/Weapon_Test.tscn").instantiate() as SampleItem3D
	root.add_child(item)
	item.freeze = true
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	item.build_from_material_cells(
		cells,
		Vector2(48.0, 19.2),
		Vector2(0.25, -0.2),
		PI * 0.5,
		&"Arm_R",
		true
	)
	var icon_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	icon_image.fill(Color.WHITE)
	item.item_image = ImageTexture.create_from_image(icon_image)
	assert(item.can_be_picked_up)
	item.global_position = (character.get_node("Torso") as RigidBody3D).global_position
	await physics_frame
	await physics_frame
	assert(inventory.try_pick_up_nearest_item())
	assert(inventory.get_items()[0] == item)
	assert(inventory.get_equipped_item() == item)
	assert(not character.has_node("EquippedItemJoint3D"))
	assert(item.rigid_attachment_holder == arm and item.get_parent() == arm)
	assert(item.freeze and item.collision_layer == 0 and item.collision_mask == 0)
	assert(is_equal_approx(arm.mass, original_arm_mass + item.mass))
	assert(inventory._rigid_attachment_shapes.size() == 1)
	var merged_shape: CollisionShape3D = inventory._rigid_attachment_shapes[0]
	var owner_id: int = arm.get_shape_owners()[-1]
	var shape_index: int = arm.shape_owner_get_shape_index(owner_id, 0)
	assert(SampleWeapon3D.from_contact(arm, shape_index) == item)
	var own_shape_index: int = arm.shape_owner_get_shape_index(arm.get_shape_owners()[0], 0)
	assert(SampleWeapon3D.from_contact(arm, own_shape_index) == null)
	var original_local_transform: Transform3D = item.transform
	arm.rotation = Vector3(0.5, 0.8, -0.4)
	arm.position += Vector3(1.0, 0.5, -0.2)
	assert(item.transform.is_equal_approx(original_local_transform))
	for body_name: StringName in [&"Torso", &"Leg_R", &"Leg_L", &"Arm_R", &"Arm_L", &"Head"]:
		var character_body := character.get_node(NodePath(body_name)) as PhysicsBody3D
		assert(item in character_body.get_collision_exceptions())
		assert(character_body in item.get_collision_exceptions())
	assert(item not in external_body.get_collision_exceptions())
	assert(external_body not in item.get_collision_exceptions())
	var socket := character.get_node("Arm_R/ItemSocket3D") as Marker3D
	assert(
		(item.global_transform * item.attachment_local_position).is_equal_approx(socket.global_position),
		"The authored item attachment point must align with the holder socket"
	)
	await physics_frame
	await physics_frame
	var attachment_error := (
		item.global_transform * item.attachment_local_position
		- socket.global_position
	).length()
	assert(attachment_error < 0.01, "The rigid attachment must preserve a non-zero attachment point")
	inventory.select_slot(0)
	assert(inventory.get_selected_slot() == -1)
	assert(inventory.get_equipped_item() == null)
	await process_frame
	assert(not character.has_node("EquippedItemJoint3D"))
	assert(item.rigid_attachment_holder == null)
	assert(inventory._rigid_attachment_shapes.is_empty())
	assert(is_equal_approx(arm.mass, original_arm_mass))
	assert(arm.inertia == original_arm_inertia and arm.center_of_mass_mode == original_center_mode)
	for body_name: StringName in [&"Torso", &"Leg_R", &"Leg_L", &"Arm_R", &"Arm_L", &"Head"]:
		var character_body := character.get_node(NodePath(body_name)) as PhysicsBody3D
		assert(item not in character_body.get_collision_exceptions())
		assert(character_body not in item.get_collision_exceptions())
	item.preferred_holder_name = &"Arm_L"
	inventory.select_slot(0)
	var arm_l := character.get_node("Arm_L") as RigidBody3D
	assert(character.has_node("Arm_L/ItemSocket3D"))
	assert(item in arm_l.get_collision_exceptions())
	inventory.select_slot(1)
	assert(inventory.get_selected_slot() == 1)
	assert(inventory.get_equipped_item() == null)
	var ui := inventory.get_node("InventoryBarUI") as CanvasLayer
	var blocking_interface := CanvasLayer.new()
	blocking_interface.add_to_group(&"ui_interface_2d")
	root.add_child(blocking_interface)
	ui._process(0.0)
	assert(not ui.visible)
	blocking_interface.queue_free()
	await process_frame
	ui._process(0.0)
	assert(ui.visible)
	var console := root.get_node("RuntimeConsole")
	console.set_console_open(true)
	ui._process(0.0)
	assert(not ui.visible)
	console.set_console_open(false)
	ui._process(0.0)
	assert(ui.visible)
	print("INVENTORY_CONTROLLER_3D_VALIDATION_PASSED")
	external_body.queue_free()
	character.queue_free()
	quit()
