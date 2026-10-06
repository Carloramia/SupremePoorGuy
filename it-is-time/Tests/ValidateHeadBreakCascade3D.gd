extends SceneTree

const CHARACTER = preload("res://Scenes/Creatures/Characters/Character_Test_2.tscn")

func _initialize() -> void:
	call_deferred("_validate")

func _make_character(extra_head: bool = false, no_head: bool = false) -> Node3D:
	var character := CHARACTER.instantiate() as Node3D
	# This test isolates the legacy Head/Torso cascades from the new connectivity rule.
	character.require_head_and_torso_connectivity = false
	var head := character.get_node("Head") as PhysicalBodyPart3D
	if extra_head:
		var second_head := head.duplicate() as PhysicalBodyPart3D
		second_head.name = "Head_Extra"
		character.add_child(second_head)
	if no_head:
		head.tags.clear()
	for node: Node in character.find_children("*", "PhysicalBodyPart3D", true, false):
		(node as PhysicalBodyPart3D).freeze = true
	root.add_child(character)
	return character

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _validate() -> void:
	var single := _make_character()
	(single.get_node("Head") as PhysicalBodyPart3D).break_part(null)
	await process_frame
	await process_frame
	var single_damage := single.get_node("CharacterDamageController3D") as CharacterDamageController3D
	for part: PhysicalBodyPart3D in single_damage.get_parts():
		if not _check(part.is_broken and is_zero_approx(part.current_hp), "Last Head must break every remaining part"):
			return
	if not _check(single_damage.is_character_disabled(), "Last Head must disable controllers"):
		return
	if not _check(not single.get_node("LegStepMovementController3D").is_physics_processing(), "Movement must stop"):
		return
	if not _check(single.find_children("*", "Joint3D", true, false).is_empty(), "Broken body joints must be removed"):
		return

	var multi := _make_character(true)
	var multi_damage := multi.get_node("CharacterDamageController3D") as CharacterDamageController3D
	(multi.get_node("Head") as PhysicalBodyPart3D).break_part(null)
	await process_frame
	await process_frame
	if not _check(not multi_damage.is_character_disabled() and not (multi.get_node("Torso") as PhysicalBodyPart3D).is_broken, "One surviving Head must prevent cascade"):
		return
	(multi.get_node("Torso") as PhysicalBodyPart3D).break_part(null)
	await process_frame
	await process_frame
	if not _check((multi.get_node("Arm_L") as PhysicalBodyPart3D).is_broken, "Torso must break directly connected non-Torso parts"):
		return
	if not _check(not multi_damage.is_character_disabled() and not (multi.get_node("Head_Extra") as PhysicalBodyPart3D).is_broken, "An unconnected surviving Head must prevent whole-body cascade"):
		return
	(multi.get_node("Head_Extra") as PhysicalBodyPart3D).break_part(null)
	await process_frame
	await process_frame
	for part: PhysicalBodyPart3D in multi_damage.get_parts():
		if not _check(part.is_broken, "Final Head in a multi-head character must trigger cascade"):
			return
	if not _check(multi_damage.is_character_disabled(), "Multi-head character must be disabled after final Head breaks"):
		return

	var headless := _make_character(false, true)
	(headless.get_node("Torso") as PhysicalBodyPart3D).break_part(null)
	await process_frame
	await process_frame
	var headless_damage := headless.get_node("CharacterDamageController3D") as CharacterDamageController3D
	if not _check(not headless_damage.is_character_disabled() and (headless.get_node("Arm_L") as PhysicalBodyPart3D).is_broken, "Headless character must retain Torso local cascade without disabling the entire character"):
		return
	print("HEAD_BREAK_CASCADE_VALIDATION_PASSED")
	single.queue_free()
	multi.queue_free()
	headless.queue_free()
	quit()
