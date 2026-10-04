extends SceneTree

const FLOATING_TEXT_SCRIPT: Script = preload("res://Scripts/VFX/SampleFloatingText3D.gd")
const DAMAGE_NUMBER_SCRIPT: Script = preload("res://Scripts/VFX/DamageNumber3D.gd")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var base_popup: Node = load("res://Scenes/VFX/_SampleFloatingText3D.tscn").instantiate()
	assert(base_popup.get_script() == FLOATING_TEXT_SCRIPT)
	root.add_child(base_popup)
	base_popup.setup_text("Base", Color.WHITE)
	assert(base_popup.get_display_text() == "Base")
	base_popup.queue_free()

	var damage_popup: Node = load("res://Scenes/VFX/DamageNumber3D.tscn").instantiate()
	assert(damage_popup.get_script() == DAMAGE_NUMBER_SCRIPT)
	assert(DAMAGE_NUMBER_SCRIPT.get_base_script() == FLOATING_TEXT_SCRIPT)
	root.add_child(damage_popup)
	damage_popup.setup_damage(12.5)
	assert(damage_popup.get_display_text() == "12.5")
	damage_popup.queue_free()
	await process_frame

	var character: Node3D = load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate()
	root.add_child(character)
	var arm := character.get_node("Arm_R") as PhysicalBodyPart3D
	for body_name: StringName in [&"Torso", &"Leg_R", &"Leg_L", &"Arm_R", &"Arm_L", &"Head"]:
		(character.get_node(NodePath(body_name)) as RigidBody3D).freeze = true
	var hp_before := arm.current_hp
	var expected_popup_origin := arm.global_position + arm.damage_number_offset
	var applied := arm.apply_damage(7.25)
	assert(is_equal_approx(applied, 7.25))
	assert(is_equal_approx(arm.current_hp, hp_before - 7.25))
	await process_frame
	await process_frame
	var spawned_popups: Array[Node] = []
	for popup: Node in get_nodes_in_group(&"floating_text_3d"):
		if not popup.is_queued_for_deletion():
			spawned_popups.append(popup)
	assert(spawned_popups.size() == 1, "Expected one damage popup, got %d" % spawned_popups.size())
	var spawned: Node3D = spawned_popups[0] as Node3D
	assert(spawned != null)
	assert(is_equal_approx(spawned.damage_amount, 7.25))
	assert(not spawned.get_display_text().is_empty())
	assert(is_equal_approx(spawned.global_position.x, expected_popup_origin.x))
	assert(is_equal_approx(spawned.global_position.z, expected_popup_origin.z))
	assert(spawned.global_position.y >= expected_popup_origin.y)
	print("DAMAGE_NUMBER_3D_VALIDATION_PASSED")
	character.queue_free()
	spawned.queue_free()
	quit()
