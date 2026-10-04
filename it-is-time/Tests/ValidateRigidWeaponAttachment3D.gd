extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	root.add_child(character)
	for node: Node in character.find_children("*", "RigidBody3D", true, false):
		(node as RigidBody3D).freeze = true
	for node: Node in character.get_children():
		if not node is RigidBody3D:
			node.set_physics_process(false)
	var inventory: Node = character.get_node("InventoryController3D")
	var arm := character.get_node("Arm_R") as PhysicalBodyPart3D
	var original_mass := arm.mass
	var weapon := load("res://Scenes/Items/Weapon_Test.tscn").instantiate() as SampleWeapon3D
	root.add_child(weapon)
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(3, 0)]
	weapon.build_from_material_cells(cells, Vector2.ZERO, Vector2.ZERO, 0.0, &"Arm_R", true)
	inventory._store_item(weapon, 0)
	weapon.begin_damage_swing()
	var target := load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Arm.tscn").instantiate() as PhysicalBodyPart3D
	target.left_distance = 0.1
	target.right_distance = 0.1
	target.top_distance = 0.1
	target.bottom_distance = 0.1
	target.armor = 0.0
	target.max_hp = 1000.0
	target.gravity_scale = 0.0
	target.axis_lock_angular_x = true
	target.axis_lock_angular_y = true
	target.axis_lock_angular_z = true
	target.position = weapon.to_global(Vector3(0.96, 0.0, 0.0)) + Vector3(0.0, 0.0, 2.0)
	root.add_child(target)
	var hits: Array = []
	target.damaged.connect(func(amount: float, _hp: float, source: Node): hits.append({"amount": amount, "source": source}))
	target.linear_velocity = Vector3(0.0, 0.0, -10.0)
	for frame in range(35):
		await physics_frame
	if hits.is_empty() or hits[0].source != weapon:
		push_error("Merged weapon collision did not register weapon damage")
		quit(1)
		return
	assert(hits.size() == 1, "A swing must hit each part only once")
	print("MERGED_WEAPON_COLLISION_DAMAGE amount=%.3f source=%s" % [hits[0].amount, hits[0].source.name])
	weapon.end_damage_swing()
	hits.clear()
	# A contact with the original Arm shape must not count as a weapon hit.
	target.position = arm.global_position + Vector3(-0.5, -0.4, 2.0)
	target.linear_velocity = Vector3(0.0, 0.0, -10.0)
	for frame in range(35):
		await physics_frame
	assert(hits.is_empty(), "Bare Arm contact was incorrectly registered as weapon damage")
	# Follow real physics rotation without any item-to-socket displacement.
	var local_transform := weapon.transform
	arm.freeze = false
	arm.gravity_scale = 0.0
	arm.angular_velocity = Vector3(0.0, 8.0, 2.0)
	for frame in range(15):
		await physics_frame
	assert(weapon.transform.is_equal_approx(local_transform))
	var socket := arm.get_node("ItemSocket3D") as Marker3D
	assert((weapon.to_global(weapon.attachment_local_position) - socket.global_position).length() < 0.0001)
	inventory.handle_part_broken(arm)
	assert(weapon.get_parent() == root and weapon.rigid_attachment_holder == null)
	assert(not weapon.freeze and weapon.can_be_picked_up)
	assert(is_equal_approx(arm.mass, original_mass))
	assert(inventory._rigid_attachment_shapes.is_empty())
	print("RIGID_WEAPON_ATTACHMENT_3D_VALIDATION_PASSED")
	quit()
