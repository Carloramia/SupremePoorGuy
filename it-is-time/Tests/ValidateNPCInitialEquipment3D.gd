extends SceneTree

const NPC = preload("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn")
const BUILDER = preload("res://Scripts/Items/WeaponCellBuilder.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make_weapon(holder: StringName = &"Arm_R") -> PackedScene:
	var layout := WeaponLayout.new()
	layout.cells = [Vector2i.ZERO, Vector2i(1,0), Vector2i(2,0)]
	layout.attachment_is_set = true
	layout.attachment = Vector2(0.25,0.1)
	layout.holder_name = holder
	var body := BUILDER.build_layout(layout)
	var scene := PackedScene.new()
	check(scene.pack(body) == OK,"Weapon fixture must pack successfully")
	body.free()
	return scene

func spawn(scene: PackedScene, at: Vector3) -> Node3D:
	var npc := NPC.instantiate() as Node3D
	npc.initial_weapon_scene = scene
	npc.position = at
	npc.get_node("NPCStateMachine3D").enabled = false
	for body: Node in npc.find_children("*","RigidBody3D",true,false):
		body.freeze = true
	root.add_child(npc)
	return npc

func run() -> void:
	var weapon_scene := make_weapon()
	var npc := spawn(weapon_scene,Vector3.ZERO)
	var second := spawn(weapon_scene,Vector3(20,0,0))
	await process_frame
	await physics_frame
	var inventory: Node = npc.get_node("InventoryController3D")
	var weapon := inventory.get_equipped_item() as SampleWeapon3D
	check(weapon != null,"Spawn must equip the assigned weapon")
	if weapon == null:
		quit(1)
		return
	var arm := npc.get_node("Arm_R") as PhysicalBodyPart3D
	check(inventory.get_selected_slot() == 0 and inventory.get_items()[0] == weapon,"Initial weapon must occupy and select the first free slot")
	check(weapon.rigid_attachment_holder == arm and weapon.get_parent() == arm,"Weapon must use the existing rigid Arm attachment")
	check(inventory._rigid_attachment_shapes.size() == 3,"All weapon collision cells must be attached")
	check(weapon.wielder_character == npc and weapon.wielder_team_id == npc.faction_id,"Damage ownership and faction must be assigned")
	check(weapon.to_global(weapon.attachment_local_position).distance_to(arm.get_node("ItemSocket3D").global_position) < 0.0001,"Weapon grip must coincide with the holder socket")
	check(not inventory.get_node("InventoryBarUI").visible,"NPC inventory must not draw a player HUD")
	check(second.get_node("InventoryController3D").get_equipped_item() != weapon,"Each spawned NPC must have an independent weapon")
	check(not inventory.equip_initial_weapon(weapon_scene),"Repeated setup must not replace or duplicate equipment")
	# Exercise actual AI selection, charge, release, and weapon damage-window callbacks.
	var enemy := spawn(null,Vector3(3,0,0))
	enemy.faction_id = 0
	var ai: Node = npc.get_node("NPCStateMachine3D")
	ai.behavior = ai.behavior.duplicate(true)
	ai.behavior.require_line_of_sight = false
	ai.enabled = true
	var swing_started := false
	for frame: int in range(160):
		await physics_frame
		if weapon.swing_damage_active: swing_started = true
	check(swing_started and weapon.swing_sequence > 0,"NPC state machine must swing the equipped weapon without player input")
	ai.enabled = false
	arm.break_part()
	await physics_frame
	check(inventory.get_items()[0] == null and inventory.get_equipped_item() == null,"Broken holder must remove the weapon from inventory")
	check(weapon.rigid_attachment_holder == null and weapon.can_be_picked_up and not weapon.freeze,"Broken holder must release a physical dropped weapon")
	# Fallback to a usable Arm when the preferred holder has no swing settings.
	var fallback := spawn(make_weapon(&"Arm_L"),Vector3(40,0,0))
	await process_frame
	check(fallback.get_node("InventoryController3D").get_equipped_item().rigid_attachment_holder == fallback.get_node("Arm_R"),"Initial equipment must fall back to an Arm with swing settings")
	var bare := spawn(null,Vector3(60,0,0))
	await process_frame
	var bare_inventory: Node = bare.get_node("InventoryController3D")
	check(bare_inventory.get_equipped_item() == null,"Unset weapon scene must keep the NPC unarmed")
	check(not bare_inventory.equip_initial_weapon(load("res://Scenes/Items/Weapon_Test.tscn")),"Empty weapon template must be rejected instead of silently equipping invisible geometry")
	for part: Node in bare.find_children("*","PhysicalBodyPart3D",true,false):
		if PhysicalBodyPart3D.BodyPartTag.Arm in part.tags: part.arm_swing_bindings.clear()
	check(not bare_inventory.equip_initial_weapon(weapon_scene),"An NPC without a usable Arm must reject initial equipment")
	print("NPC_INITIAL_EQUIPMENT_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
