extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character := load(
		"res://Scenes/Creatures/Characters/Character_Test_2.tscn"
	).instantiate() as Node3D
	root.add_child(character)
	for body_name: StringName in [&"Torso", &"Leg_R", &"Leg_L", &"Arm_R", &"Arm_L", &"Head"]:
		(character.get_node(NodePath(body_name)) as RigidBody3D).freeze = true
	var torso := character.get_node("Torso") as PhysicalBodyPart3D
	var arm_r := character.get_node("Arm_R") as PhysicalBodyPart3D
	var leg_r := character.get_node("Leg_R") as PhysicalBodyPart3D
	var head := character.get_node("Head") as PhysicalBodyPart3D
	var damage_controller := character.get_node("CharacterDamageController3D") as CharacterDamageController3D
	var damage_service := root.get_node("DamageService")
	assert(is_equal_approx(torso.max_hp, 200.0) and is_equal_approx(torso.armor, 15.0))
	assert(is_equal_approx(arm_r.max_hp, 80.0) and is_equal_approx(arm_r.armor, 8.0))
	assert(is_equal_approx(leg_r.max_hp, 100.0) and is_equal_approx(leg_r.armor, 10.0))
	assert(is_equal_approx(head.max_hp, 100.0) and is_equal_approx(head.armor, 5.0))

	var weapon := load("res://Scenes/Items/Weapon_Test.tscn").instantiate() as SampleWeapon3D
	root.add_child(weapon)
	weapon.freeze = true
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	weapon.build_from_material_cells(cells)
	weapon.set_wielder(character, damage_controller.team_id)
	assert(arm_r._is_friendly_weapon(weapon))
	var friendly_character := load(
		"res://Scenes/Creatures/Characters/Character_Test_2.tscn"
	).instantiate() as Node3D
	root.add_child(friendly_character)
	var friendly_arm := friendly_character.get_node("Arm_R") as PhysicalBodyPart3D
	assert(friendly_arm._is_friendly_weapon(weapon))
	var enemy_character := load(
		"res://Scenes/Creatures/Characters/Character_Test_NPC.tscn"
	).instantiate() as Node3D
	root.add_child(enemy_character)
	var enemy_arm := enemy_character.get_node("Arm_R") as PhysicalBodyPart3D
	assert(not enemy_arm._is_friendly_weapon(weapon))
	assert(is_equal_approx(damage_service.calculate_raw_damage(20.0), 30.0))
	assert(is_equal_approx(damage_service.calculate_damage(20.0, arm_r.armor), 22.0))
	assert(weapon.try_register_hit(arm_r))
	weapon.begin_damage_swing()
	assert(weapon.try_register_hit(arm_r))
	assert(not weapon.try_register_hit(arm_r))
	assert(weapon.try_register_hit(leg_r))
	weapon.end_damage_swing()

	var inventory := character.get_node("InventoryController3D")
	weapon.global_position = torso.global_position
	await physics_frame
	await physics_frame
	assert(inventory.try_pick_up_nearest_item())
	assert(inventory.get_equipped_item() == weapon)
	arm_r.apply_damage(arm_r.current_hp, weapon)
	await process_frame
	await process_frame
	assert(arm_r.is_broken)
	assert(not character.has_node("ShoulderJoint_R"))
	assert(inventory.get_equipped_item() == null)
	assert(weapon.get_parent() == root)
	assert(weapon.can_be_picked_up and not weapon.freeze and weapon.visible)

	leg_r.apply_damage(leg_r.current_hp, weapon)
	await process_frame
	await process_frame
	assert(leg_r.is_broken)
	assert(not character.has_node("HipJoint_R"))
	var movement := character.get_node("LegStepMovementController3D")
	assert(leg_r not in movement.get_leg_parts())

	torso.apply_damage(torso.current_hp, weapon)
	await process_frame
	await process_frame
	assert(torso.is_broken)
	assert(head.is_broken)
	for part: PhysicalBodyPart3D in damage_controller.get_parts():
		assert(part.is_broken and is_zero_approx(part.current_hp))
	assert(damage_controller.is_character_disabled())
	print("DAMAGE_SYSTEM_VALIDATION_PASSED")
	weapon.queue_free()
	friendly_character.queue_free()
	enemy_character.queue_free()
	character.queue_free()
	quit()
