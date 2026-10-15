extends SceneTree

const WEAPON = preload("res://Scenes/Items/Weapons/Human/Human5Spear.tscn")
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func weapon_scene(paths: Array[NodePath]) -> PackedScene:
	var item := WEAPON.instantiate() as SampleWeapon3D
	item.grip_point_count = paths.size()
	item.grip_point_arm_paths = paths
	for index: int in paths.size(): item.grip_point_poses.append(Transform3D(Basis(Vector3.BACK, index*0.2), Vector3(0.1, 0.2+index, 0)))
	var scene := PackedScene.new()
	check(scene.pack(item) == OK, "Pack independent per-grip Arm settings")
	item.free()
	return scene

func verify_actor(path: String, generated: bool) -> void:
	var actor := load(path).instantiate() as Node3D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	if generated:
		actor.generate_on_ready = false
		actor.initial_weapon_scene = null
	root.add_child(actor)
	for body: RigidBody3D in actor.find_children("*", "RigidBody3D", true, false): body.freeze = true
	var inventory := actor.get_node("InventoryController3D")
	inventory.inventory_ui_enabled = false
	inventory.attachment_debug_logging = false
	var prefix := "GeneratedParts/" if generated else ""
	var right := actor.get_node(prefix+"Arm_R") as PhysicalBodyPart3D
	var left := actor.get_node(prefix+"Arm_L") as PhysicalBodyPart3D
	var right_mass := right.mass
	var left_mass := left.mass
	var missing := weapon_scene([^"MissingArm"])
	check(not inventory.equip_initial_weapon(missing) and inventory.get_items().filter(func(item): return is_instance_valid(item)).is_empty(), "Explicit missing target must reject initial equipment without fallback or filling a slot")
	var scene := weapon_scene([^"Arm_L", NodePath(prefix+"Arm_R"), ^"Head", ^"MissingArm", ^""])
	check(inventory.equip_initial_weapon(scene), "Initial equipment supports an explicitly selected living Arm")
	var weapon := inventory.get_equipped_item() as SampleWeapon3D
	check(weapon != null, "Configured equipment exists")
	if weapon == null:
		actor.queue_free()
		await process_frame
		return
	check(weapon.rigid_attachment_holder == left, "Bare name finds the selected Arm, including nested generated parts")
	var row: Dictionary = inventory.get_weapon_grip_diagnostics()
	check(row.requested_arm == "Arm_L" and row.error_length < 0.0001 and row.rigid_bound, "Logs identify requested and actual Arm with correct alignment")
	inventory.refresh_physics_query_cache()
	check(weapon.rigid_attachment_holder == left and not inventory._rigid_attachment_snapshot.is_empty(), "Refreshing the default Arm cache must not detach another configured Arm")
	check(not weapon.select_grip_point(2) and not weapon.select_grip_point(3), "Reject non-Arm and missing targets")
	check(weapon.active_grip_point == 0 and weapon.rigid_attachment_holder == left and is_equal_approx(left.mass,left_mass+weapon.mass), "Rejected switch preserves the old point, binding and mass")
	var old_pose := weapon.global_transform
	check(not inventory.can_equip_weapon_grip(weapon,2) and weapon.global_transform == old_pose, "Validation must not move equipment onto a Head")
	check(weapon.select_grip_point(1) and weapon.rigid_attachment_holder == right, "Switch targets the Arm specified by a full character-relative path")
	check(is_equal_approx(left.mass,left_mass) and is_equal_approx(right.mass,right_mass+weapon.mass), "Transfer restores old Arm mass and merges once into new Arm")
	row = inventory.get_weapon_grip_diagnostics()
	check(row.error_length < 0.0001 and row.rotation_error_degrees < 0.01 and row.requested_arm == prefix+"Arm_R", "New target uses the matching grip pose and socket")
	check(weapon.select_grip_point(4) and weapon.rigid_attachment_holder == right, "Empty mapping preserves the legacy default holder")
	weapon.grip_point_arm_paths[3] = NodePath("../"+str(actor.name)+"/"+prefix+"Head")
	check(not weapon.select_grip_point(3), "Reject non-Arm even when a relative path resolves")
	var foreign := left.duplicate() as PhysicalBodyPart3D
	foreign.name = "ForeignArm"
	foreign.tags = [PhysicalBodyPart3D.BodyPartTag.Arm]
	root.add_child(foreign)
	weapon.grip_point_arm_paths[3] = NodePath("../ForeignArm")
	check(not weapon.select_grip_point(3), "Never bind to another character's external Arm")
	foreign.queue_free()
	left.is_broken = true
	check(not weapon.select_grip_point(0) and weapon.rigid_attachment_holder == right, "Broken target Arm must not replace a valid current grip")
	if generated:
		var old_left_id := left.get_instance_id()
		check(actor.generate_creature(), "Generated character can regenerate with per-grip Arm mappings")
		await process_frame
		for body: RigidBody3D in actor.find_children("*", "RigidBody3D", true, false): body.freeze = true
		left = actor.get_node(prefix+"Arm_L") as PhysicalBodyPart3D
		check(left.get_instance_id() != old_left_id and weapon.select_grip_point(0) and weapon.rigid_attachment_holder == left, "Regeneration resolves a new Arm by saved name, never by stale object reference")
	actor.queue_free()
	await process_frame

func run() -> void:
	await verify_actor("res://Scenes/Creatures/Characters/Character_Test_2.tscn",false)
	await verify_actor("res://Scenes/Creatures/Characters/Generate_Human.tscn",true)
	print("WEAPON_GRIP_ARM_BINDING_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
