extends SceneTree

const PLAYER_SCENE = preload("res://Scenes/Player/Controller.tscn")
const CHARACTER_SCENE = preload("res://Scenes/Creatures/Characters/Character_Test_2.tscn")
const NPC_SCENE = preload("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn")
const GENERATED_SCENE = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
const CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var world := Node3D.new()
	world.name = "ControllerTest"
	root.add_child(world)
	var camera := (load("res://Scenes/Camera/DragCamera3D.tscn") as PackedScene).instantiate() as Node3D
	world.add_child(camera)
	var cursor := (load("res://Scenes/Input/TerrainCursor3D.tscn") as PackedScene).instantiate() as TerrainCursor3D
	world.add_child(cursor)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(100, 1, 100)
	ground.add_child(shape)
	ground.position.y = -0.5
	world.add_child(ground)
	var character := CHARACTER_SCENE.instantiate() as Node3D
	world.add_child(character)
	var npc := NPC_SCENE.instantiate() as Node3D
	npc.position.x = 8
	world.add_child(npc)
	for body: Node in world.find_children("*", "RigidBody3D", true, false): body.freeze = true
	character.get_node("PhysicalFacingController3D").turning_enabled = false
	var player := PLAYER_SCENE.instantiate() as Node3D
	player.camera_rig = camera
	player.terrain_cursor = cursor
	character.add_child(player)
	await process_frame
	await physics_frame
	assert(player.get_controlled_character() == character and player.get_parent() == character)
	assert(camera.follow_target == player)
	assert(player.global_position.is_equal_approx(character.get_node("Torso").global_position))
	assert(cursor.controlled_character == character)
	var movement := character.get_node("LegStepMovementController3D")
	assert(movement.command_source == player)
	Input.action_press(&"Right")
	Input.action_press(&"Up")
	player._physics_process(1.0 / 60.0)
	assert(movement.get_input_movement_direction().is_equal_approx(Vector3(1, 0, -1).normalized()))
	Input.action_release(&"Right")
	Input.action_release(&"Up")
	Input.action_press(&"Shift")
	player._physics_process(1.0 / 60.0)
	assert(movement.is_fast_speed_active())
	Input.action_release(&"Shift")
	var swing := character.get_node("LimbSwingController3D")
	Input.action_press(&"MouseLeft")
	swing._physics_process(0.1)
	assert(int(swing._states[0].members[0].mode) == LimbSwingController3D.SwingState.CHARGING)
	camera._orbiting = true
	var wheel_press := InputEventAction.new()
	wheel_press.action = &"QPressed"
	wheel_press.pressed = true
	player._input(wheel_press)
	assert(not camera._orbiting)
	assert(player.wheel.visible and player.wheel.options[0].display_name == "弹出")
	assert(movement.get_input_movement_direction() == Vector3.ZERO)
	assert(int(swing._states[0].members[0].mode) == LimbSwingController3D.SwingState.IDLE)
	assert(player.wheel.pick_at(player.wheel.screen_center) == -1)
	assert(player.wheel.pick_at(player.wheel.screen_center + Vector2(0, -100)) == 0)
	player.wheel.hovered_index = 0
	player.close_wheel(true)
	assert(not player.is_attached() and player.get_parent() == world)
	assert(movement.command_source == null and movement.is_physics_processing())
	assert(cursor.controlled_character == null and not cursor.follow_anchor_translation)
	assert(camera.follow_target == player)
	assert(not CONTEXT.input_allowed(swing))
	character.get_node("InventoryController3D/InventoryBarUI")._process(0.0)
	assert(not character.get_node("InventoryController3D/InventoryBarUI").visible)
	assert(player.open_wheel())
	assert(player.wheel.options[0].display_name == "接入" and not player.wheel.options[0].enabled)
	player.close_wheel(false)
	# Snap selection is captured before the menu suspends the cursor and clears its visual selection.
	player.global_position = npc.get_node("Torso").global_position
	cursor.set_cursor_world_position(player.global_position)
	cursor._set_selected_character(npc)
	assert(player.open_wheel())
	assert(player.wheel.options[0].enabled)
	assert(cursor.get_selected_character() == null)
	player.wheel.hovered_index = 0
	player.close_wheel(true)
	assert(player.get_controlled_character() == npc and player.get_parent() == npc)
	assert(not npc.get_node("NPCStateMachine3D").is_physics_processing())
	assert(npc.get_node("NPCLegStepMovementController3D").command_source == player)
	assert(not player.is_gameplay_action_pressed(&"MouseLeft"), "Held attack must not transfer into a new character")
	Input.action_release(&"MouseLeft")
	player._physics_process(1.0 / 60.0)
	Input.action_press(&"MouseLeft")
	assert(player.is_gameplay_action_pressed(&"MouseLeft"))
	Input.action_release(&"MouseLeft")
	Input.action_press(&"Left")
	player._physics_process(1.0 / 60.0)
	assert(npc.get_node("NPCLegStepMovementController3D").get_input_movement_direction() == Vector3.LEFT)
	assert(movement.get_input_movement_direction() == Vector3.ZERO)
	Input.action_release(&"Left")
	assert(CONTEXT.controlled_character(world) == npc and CONTEXT.anchor(world) == npc.get_node("Torso"))
	player.detach_character()
	assert(npc.get_node("NPCStateMachine3D").is_physics_processing())
	assert(npc.get_node("NPCLegStepMovementController3D").command_source == null)
	# Any number of option resources are supported and the center always cancels.
	var options: Array[ControllerWheelOption] = []
	for index: int in range(12):
		var option := ControllerWheelOption.new()
		option.display_name = "Test %d" % index
		option.action = StringName("test_%d" % index)
		options.append(option)
	player.wheel.open_at(Vector2(400, 300), options)
	for index: int in range(12):
		var position: Vector2 = player.wheel.screen_center + Vector2.from_angle(-PI * 0.5 + TAU * index / 12) * 100
		assert(player.wheel.pick_at(position) == index)
	player.wheel.close_menu(false)
	# Console/workshop must block opening, input and queued operations.
	var console := root.get_node("RuntimeConsole")
	console.set_console_open(true)
	assert(not player.open_wheel())
	console.set_console_open(false)
	var interface := CanvasLayer.new()
	interface.add_to_group(&"ui_interface_2d")
	world.add_child(interface)
	assert(not player.open_wheel())
	interface.queue_free()
	await process_frame
	# Free cursor movement does not feed its snapped display back into the camera anchor.
	cursor.set_cursor_world_position(Vector3(20, 0, 0))
	player._physics_process(1.0 / 60.0)
	assert(is_equal_approx(player.global_position.x, 20))
	cursor.global_position = Vector3(40, 0, 0)
	player._physics_process(1.0 / 60.0)
	assert(is_equal_approx(player.global_position.x, 20))
	# The generated adapter accepts the same command source without enabling fast mode.
	var generated := GENERATED_SCENE.instantiate() as Node3D
	generated.generate_on_ready = false
	world.add_child(generated)
	assert(player.attach_character(generated))
	Input.action_press(&"Down")
	Input.action_press(&"Shift")
	player._physics_process(1.0 / 60.0)
	var generated_movement := generated.get_node("GeneratedLegStepMovementController3D")
	assert(generated_movement.get_input_movement_direction() == Vector3.BACK)
	assert(not generated_movement.is_fast_speed_active())
	Input.action_release(&"Down")
	Input.action_release(&"Shift")
	player.attach_character(character)
	character.get_node("CharacterDamageController3D")._disable_character_controllers()
	assert(not player.is_attached() and player.is_processing() and player.is_physics_processing())
	assert(not player.can_attach_character(character))
	world.queue_free()
	await process_frame
	print("PLAYER_CONTROLLER_VALIDATION_PASSED")
	quit()
