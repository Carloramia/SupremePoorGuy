extends SceneTree

const CHARACTER = preload("res://Scenes/Creatures/Characters/Character_Test_2.tscn")
const WEAPON = preload("res://Scenes/Items/Weapons/Human/Human5Spear.tscn")
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func spawn(actor_name: String) -> Node3D:
	var actor := CHARACTER.instantiate() as Node3D
	actor.name = actor_name
	root.add_child(actor)
	for body: RigidBody3D in actor.find_children("*", "RigidBody3D", true, false): body.freeze = true
	for component: Node in actor.get_children(): component.set_physics_process(false)
	var inventory := actor.get_node("InventoryController3D")
	inventory.inventory_ui_enabled = false
	inventory.attachment_debug_logging = false
	return actor

func contains_event(console: Node, event: String) -> bool:
	for line: String in console._output_lines:
		if "[weapon_grip]" in line and "event=" + event + " " in line: return true
	return false

func run() -> void:
	var console := root.get_node("RuntimeConsole")
	console.set_process(false)
	var first := spawn("GripActor")
	var second := spawn("GripActor2")
	var inventory := first.get_node("InventoryController3D")
	check(not console._grip_tracking_enabled, "Grip tracking defaults off")
	check(console.execute_command("help").contains("trackgrip") and console.execute_command("help").contains("gripstates"), "Help lists both grip commands")
	check(console.execute_command("trackgrip invalid").begins_with("Usage:"), "Reject invalid command without enabling tracking")
	check(console.execute_command("gripstates").ends_with("2"), "One-shot query includes empty inventories")
	check(not console._grip_tracking_enabled, "One-shot query must not enable tracking")
	check(console.execute_command("trackgrip on GripActor").contains("matched=1"), "Exact name filter excludes similarly named actors")
	var template := WEAPON.instantiate() as SampleWeapon3D
	template.grip_point_count = 2
	template.active_grip_point = 0
	template.grip_point_poses = [Transform3D(Basis(Vector3.BACK, 0.2), Vector3(0.1, 0.3, 0)), Transform3D(Basis(Vector3.BACK, -0.4), Vector3(0.2, 1.3, 0.1))]
	var scene := PackedScene.new()
	check(scene.pack(template) == OK, "Build multi-grip fixture")
	template.free()
	check(inventory.equip_initial_weapon(scene), "Equip real multi-grip weapon")
	check(contains_event(console, "equipped"), "Equipment changes log immediately while enabled")
	var weapon := inventory.get_equipped_item() as SampleWeapon3D
	var row: Dictionary = inventory.get_weapon_grip_diagnostics()
	check(row.equipped and row.rigid_bound and row.grip_point == 1 and row.grip_count == 2 and row.grip_data_matches, "Report equipped state and one-based grip selection")
	check(row.error_length < 0.0001 and row.rotation_error_degrees < 0.01 and absf(row.mass_error) < 0.0001 and row.merged_shapes > 0, "Report correct alignment and compound mass/shapes")
	weapon.rigid_attachment_holder.position += Vector3(1, 0.2, 0)
	weapon.rigid_attachment_holder.rotate_z(0.1)
	await physics_frame
	await physics_frame
	row = inventory.get_weapon_grip_diagnostics()
	check(row.rigid_bound and row.error_length < 0.0001 and row.rotation_error_degrees < 0.01, "Grip remains aligned as the holder moves through physics frames")
	check(weapon.select_grip_point(1), "Switch equipped grip")
	row = inventory.get_weapon_grip_diagnostics()
	check(row.grip_point == 2 and row.error_length < 0.0001 and contains_event(console, "unequip_begin") and contains_event(console, "unequipped"), "Switch logs rebind and current alignment")
	var original := weapon.transform
	weapon.position.x += 0.5
	weapon.rotate_z(0.2)
	row = inventory.get_weapon_grip_diagnostics()
	check(row.error_length > 0.1 and row.rotation_error_degrees > 10.0, "Observe actual position and rotation drift")
	check(not weapon.transform.is_equal_approx(original), "Diagnostics must not correct or rebind equipment")
	weapon.transform = original
	weapon.attachment_local_position += Vector3(0.01, 0, 0)
	check(not inventory.get_weapon_grip_diagnostics().grip_data_matches, "Detect uncommitted/changed active grip data")
	weapon.apply_selected_grip_point()
	var socket := weapon.rigid_attachment_holder.get_node("ItemSocket3D")
	var parent := socket.get_parent()
	parent.remove_child(socket)
	check(not inventory.get_weapon_grip_diagnostics().socket_valid, "Missing socket must be observable without recreating it")
	check(not parent.has_node("ItemSocket3D"), "Query must never create sockets")
	parent.add_child(socket)
	var lines_before: int = console._output_lines.size()
	console._process(0.099)
	check(console._output_lines.size() == lines_before, "Do not sample before interval")
	console._process(0.002)
	check(console._output_lines.size() == lines_before + 1, "Sample every 0.1 seconds")
	check(console.execute_command("gripstates /root/GripActor2").ends_with("1"), "Path filtering")
	check(console.execute_command("gripstates " + str(first.get_instance_id())).ends_with("1"), "Instance ID filtering")
	check(console.execute_command("gripstates missing").ends_with("0"), "Missing match reports zero")
	console.execute_command("trackgrip off")
	lines_before = console._output_lines.size()
	inventory.select_slot(0)
	console._process(1.0)
	check(console._output_lines.size() == lines_before, "Off stops events and periodic logs")
	check(inventory.get_weapon_grip_diagnostics().state == "empty", "Deselected inventory is empty")
	inventory.select_slot(0)
	weapon.grip_point_count = 0
	check(inventory.get_weapon_grip_diagnostics().grip_mode == "legacy", "Old single-point weapons remain diagnosable")
	console.execute_command("trackgrip on")
	var late := spawn("LateGripActor")
	check(console._emit_weapon_grip_snapshot("") == 3, "Include inventories spawned after enabling")
	var late_inventory := late.get_node("InventoryController3D")
	check(late_inventory.equip_initial_weapon(WEAPON), "Late actor can equip legacy weapon")
	var dropped: SampleWeapon3D = late_inventory.get_equipped_item()
	late_inventory.handle_part_broken(dropped.rigid_attachment_holder)
	check(contains_event(console, "holder_broken_drop") and dropped.can_be_picked_up and late_inventory.get_equipped_item() == null, "Observe broken-holder drop without preventing it")
	dropped.queue_free()
	second.queue_free()
	check(console._emit_weapon_grip_snapshot("") == 2, "Skip actors pending deletion")
	weapon.free()
	check(inventory.get_weapon_grip_diagnostics().state == "item_missing", "Deleted equipped weapon is observable without dereferencing it")
	inventory._physics_process(0.016)
	check(contains_event(console, "item_deleted"), "Deleted equipment emits a diagnostic event")
	check(inventory.get_weapon_grip_diagnostics().state == "empty", "Cleanup returns to empty state")
	check(console.execute_command("trackgrip").contains("disabled"), "Bare command toggles off")
	first.queue_free()
	late.queue_free()
	await process_frame
	print("WEAPON_GRIP_TRACKING_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
