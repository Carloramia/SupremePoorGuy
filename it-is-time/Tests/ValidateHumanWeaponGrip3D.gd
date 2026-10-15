extends SceneTree

const BUILDER = preload("res://Scripts/Items/WeaponCellBuilder.gd")
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func spawn(file: String) -> Node3D:
	var actor := load("res://Scenes/Creatures/Characters/" + file).instantiate() as Node3D
	actor.generate_on_ready = false
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	for part: Node in actor.find_children("*", "RigidBody3D", true, false): part.freeze = true
	root.add_child(actor)
	actor.get_node("InventoryController3D").inventory_ui_enabled = false
	actor.get_node("InventoryController3D").attachment_debug_logging = false
	return actor

func make_weapon(holder: StringName) -> SampleWeapon3D:
	var layout := WeaponLayout.new()
	layout.cells = [Vector2i.ZERO]
	layout.attachment_is_set = true
	layout.holder_name = holder
	var weapon := BUILDER.build_layout(layout) as SampleWeapon3D
	root.add_child(weapon)
	return weapon

func run() -> void:
	var actor := spawn("Generate_Human.tscn")
	var inventory: Node = actor.get_node("InventoryController3D")
	var right := actor.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	var left := actor.get_node("GeneratedParts/Arm_L") as PhysicalBodyPart3D
	check(right.set_visual_state(&"open"), "Human hand must support open")
	var original_mass := right.mass
	var collision := right.get_node("CollisionShape3D") as CollisionShape3D
	var original_shape := collision.shape
	var collision_pose := collision.transform
	var socket := right.get_node("ItemSocket3D") as Marker3D
	var socket_pose := socket.transform
	var body_pose := right.transform
	var right_weapon := make_weapon(&"GeneratedParts/Arm_R")
	inventory._store_item(right_weapon, 0)
	check(right.get_visual_state() == &"grip" and left.get_visual_state() == &"", "Only the equipped hand must grip")
	check(right_weapon.rigid_attachment_holder == right, "Weapon must stay attached to the actual hand")
	check(collision.shape == original_shape and collision.transform == collision_pose and socket.transform == socket_pose and right.transform == body_pose, "Gripping must preserve the original collider, socket and body pose")
	check(is_equal_approx(right.mass, original_mass + right_weapon.mass), "Visual switching must preserve the existing combined weapon mass")
	var left_weapon := make_weapon(&"GeneratedParts/Arm_L")
	inventory._store_item(left_weapon, 1)
	inventory.select_slot(1)
	check(right.get_visual_state() == &"open" and left.get_visual_state() == &"grip", "Changing holder must restore the old hand and grip with the new hand")
	check(left_weapon.rigid_attachment_holder == left, "Left-hand equipment must use its own holder")
	inventory.select_slot(2)
	check(left.get_visual_state() == &"" and inventory.get_equipped_item() == null, "An empty slot must restore the authored appearance")
	inventory.select_slot(0)
	inventory.select_slot(0)
	check(right.get_visual_state() == &"open", "Deselecting the same slot must restore the previous open state")
	inventory.select_slot(0)
	check(right.set_visual_state(&""), "Other visual systems must still be able to override equipment appearance")
	inventory.select_slot(2)
	check(right.get_visual_state() == &"", "Unequip must not overwrite a newer visual override")
	check(right.set_visual_state(&"open"), "Restore the open fixture before testing deletion")
	inventory.select_slot(0)
	right_weapon.queue_free()
	await process_frame
	await physics_frame
	await process_frame
	check(right.get_visual_state() == &"open" and is_equal_approx(right.mass, original_mass), "Externally deleted weapons must restore hand appearance and mass")
	right_weapon = make_weapon(&"GeneratedParts/Arm_R")
	inventory._store_item(right_weapon, 0)
	check(actor.generate_creature(), "Human regeneration must succeed while holding a weapon")
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true
	await process_frame
	right = actor.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	check(right_weapon.rigid_attachment_holder == right and right.get_visual_state() == &"grip", "Regeneration must equip and grip with the new hand")
	right.break_part()
	await process_frame
	check(inventory.get_equipped_item() == null and right_weapon.rigid_attachment_holder == null and right_weapon.can_be_picked_up, "A broken holder must drop the weapon")
	check(right.get_visual_state() == &"", "A broken holder must release its grip visual")
	actor.queue_free()
	right_weapon.queue_free()
	await process_frame
	var npc := spawn("Generate_Human_NPC.tscn")
	await process_frame
	await process_frame
	var npc_inventory: Node = npc.get_node("InventoryController3D")
	var npc_hand := npc.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	check(npc_inventory.get_equipped_item() != null and npc_hand.get_visual_state() == &"grip", "NPC initial equipment must automatically grip")
	check(npc.get_node("GeneratedParts/Arm_L").get_visual_state() == &"", "NPC free hand must retain its authored appearance")
	npc_inventory.select_slot(1)
	check(npc_hand.get_visual_state() == &"", "NPC unequip must restore its authored hand appearance")
	npc.free()
	await process_frame
	print("HUMAN_WEAPON_GRIP_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
