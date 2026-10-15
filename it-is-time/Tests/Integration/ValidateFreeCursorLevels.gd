extends SceneTree
const CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed=true; push_error(message)
func run() -> void:
	for scene: String in ["TestLevel","HumanTestLevel"]:
		var level: Node3D = load("res://Scenes/Levels/"+scene+".tscn").instantiate()
		root.add_child(level)
		for tick: int in 30: await physics_frame
		var cursor: TerrainCursor3D = level.get_node("TerrainCursor3D")
		check(get_nodes_in_group(&"player_controller_3d").is_empty(),scene+" contains no player controller")
		check(cursor.free_cursor_mode and cursor.movement_anchor==null and cursor.has_valid_ground_position(),scene+" initializes an unbound grounded cursor")
		check(cursor.free_camera_rig==level.get_node("DragCamera3D"),scene+" camera binds directly to the free cursor")
		check(CONTEXT.controlled_character(level)==null and CONTEXT.anchor(level)==null,scene+" does not treat an AI navigation target as the player")
		var workshop := root.get_node("WorkshopUIController")
		var press := InputEventAction.new()
		press.action = &"BPressed"; press.pressed = true
		root.push_input(press,true)
		await process_frame
		check(not is_instance_valid(workshop._workshop),scene+" ignores the former workshop shortcut")
		if scene=="HumanTestLevel":
			Input.action_press(&"Right")
			var movement := level.get_node("GenerateHuman/GeneratedLegStepMovementController3D")
			check(movement.get_input_movement_direction()==Vector3.ZERO,"Uncontrolled Human cannot read raw movement keys")
			Input.action_release(&"Right")
		level.queue_free()
		await process_frame; await process_frame
	print("FREE_CURSOR_LEVELS_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
