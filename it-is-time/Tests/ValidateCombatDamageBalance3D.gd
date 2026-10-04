extends SceneTree
func _initialize() -> void:
	call_deferred("_validate")
func _validate() -> void:
	var service: Node = root.get_node("DamageService")
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	root.add_child(character)
	for body: Node in character.find_children("*", "RigidBody3D", true, false):
		(body as RigidBody3D).freeze = true
	var controller := character.get_node("LimbSwingController3D") as LimbSwingController3D
	for node: Node in character.get_children():
		if not node is RigidBody3D and node != controller:
			node.set_physics_process(false)
	var arm := character.get_node("Arm_R") as PhysicalBodyPart3D
	var start_transform := arm.global_transform
	var inventory: Node = character.get_node("InventoryController3D")
	inventory.attachment_debug_logging = false
	var weapon := load("res://Scenes/Items/Weapon_Test.tscn").instantiate() as SampleWeapon3D
	root.add_child(weapon)
	var cells: Array[Vector2i] = []
	for x in range(6):
		cells.append(Vector2i(x, 0))
	weapon.build_from_material_cells(cells, Vector2.ZERO, Vector2.ZERO, 0.0, &"Arm_R", true)
	inventory._store_item(weapon, 0)
	for part_name: String in ["Torso", "Arm", "Leg", "Head"]:
		var part := load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_" + part_name + ".tscn").instantiate() as PhysicalBodyPart3D
		part.name = "BalanceTarget" + part_name
		part.gravity_scale = 0.0
		root.add_child(part)
		part.freeze = true
		# Check the complete useful impact band, including weak registered hits.
		for impulse: float in [1.1, 3.1, 5.0, 10.0, 20.0, 100.0]:
			var damage: float = service.calculate_weapon_damage(impulse, part.armor, true)
			var hits := ceili(part.max_hp / damage)
			assert(hits <= (3 if part_name == "Torso" else 1))
			assert(service.calculate_weapon_damage(impulse, part.armor, false) <= 2.0)
		controller._cancel_all_members()
		arm.freeze = true
		arm.global_transform = start_transform
		part.global_position = arm.to_global(Vector3(2.56, 0.032, 0.0)) + Vector3(0, 0, 3)
		part.freeze = false
		part.linear_velocity = Vector3(0, 0, -20)
		var passive_hp := part.current_hp
		for frame in range(30):
			await physics_frame
		var passive_damage := passive_hp - part.current_hp
		print("PASSIVE_BALANCE_PHYSICS part=%s damage=%.3f" % [part_name, passive_damage])
		assert(passive_damage <= 4.0, "Normal contact inflicted excessive damage")
		part.current_hp = part.max_hp
		var hit_count := 0
		while not part.is_broken and hit_count < 3:
			controller._cancel_all_members()
			arm.freeze = true
			arm.global_transform = start_transform
			arm.linear_velocity = Vector3.ZERO
			arm.angular_velocity = Vector3.ZERO
			part.freeze = true
			part.position = Vector3(50, 50, 50)
			part.linear_velocity = Vector3.ZERO
			part.angular_velocity = Vector3.ZERO
			arm.freeze = false
			Input.action_press("MouseLeft")
			controller.begin_charge(0)
			for frame in range(30):
				await physics_frame
			var state: Dictionary = controller._states[0].members[0]
			var pivot: Vector3 = (state.anchor_body as Node3D).to_global(state.anchor_local_position)
			part.global_position = pivot + Vector3(3.7, 0, 0)
			part.freeze = false
			var hp_before := part.current_hp
			Input.action_release("MouseLeft")
			controller.release_charge(0)
			for frame in range(40):
				await physics_frame
			var damage := hp_before - part.current_hp
			print("COMBAT_BALANCE_PHYSICS part=%s attempt=%d damage=%.3f hp=%.3f" % [part_name, hit_count + 1, damage, part.current_hp])
			if damage <= 0.0:
				push_error("Reference swing did not damage " + part_name)
				quit(1)
				return
			hit_count += 1
		if not part.is_broken or (part_name != "Torso" and hit_count != 1):
			push_error("Reference swing balance failed for " + part_name)
			quit(1)
			return
		part.queue_free()
		await process_frame
	controller._cancel_all_members()
	print("COMBAT_DAMAGE_BALANCE_3D_VALIDATION_PASSED")
	quit()
