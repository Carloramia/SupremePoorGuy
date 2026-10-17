extends SceneTree

var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func freeze_parts(actor: Node3D) -> void:
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true

func item_count(inventory: Node) -> int:
	var count := 0
	for item: Variant in inventory.get_items():
		if is_instance_valid(item): count += 1
	return count

func verify_variant(record: Dictionary, npc: bool, body_set: int) -> void:
	var path: String = record.npc_scene if npc else record.character_scene
	var packed := load(path) as PackedScene
	check(packed != null and packed.get_state().get_base_scene_state() != null,"Variant must be an inherited scene: "+path)
	if packed == null: return
	var actor := packed.instantiate() as Node3D
	check(actor.initial_weapon_scene.resource_path == record.weapon_scene,"Variant must reference its assigned weapon")
	check(actor.get_node("HumanGenerator").human_set == body_set,"Weapon variants must inherit the parent's current body set")
	check(actor.has_node("NPCStateMachine3D") == npc,"Only the NPC variant must contain the AI")
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	if record.name == "Bow":
		# The independent string body needs a physics space even while the character is frozen.
		actor.process_mode = Node.PROCESS_MODE_INHERIT
		for component: Node in actor.get_children():
			component.set_process(false)
			component.set_physics_process(false)
	if npc:
		var ai := actor.get_node("NPCStateMachine3D")
		check(ai.enabled and ai.attack_execution_enabled == bool(record.get("npc_attacks_enabled",true)),"NPC must retain movement and the variant's attack availability")
		check(ai.get_script().resource_path == "res://Scripts/Creatures/HumanNPCStateMachine3D.gd","NPC must reuse the Human AI controller")
		check(ai.behavior.resource_path == ("res://Resources/AI/HumanBowAI.tres" if record.name=="Bow" else "res://Resources/AI/HumanMeleeAI.tres"),"NPC must use the matching weapon behavior")
		check(not actor.get_node("InventoryController3D").inventory_ui_enabled,"NPC must hide the inventory HUD")
		ai.enabled = false
	var generated: Array[bool] = []
	actor.creature_generation_finished.connect(func(success: bool) -> void:
		generated.append(success)
		freeze_parts(actor)
	)
	actor.get_node("InventoryController3D").inventory_ui_enabled = false
	actor.get_node("InventoryController3D").attachment_debug_logging = false
	root.add_child(actor)
	await process_frame
	await process_frame
	await physics_frame
	check(not generated.is_empty() and generated[0],"Runtime framework/physics generation must succeed")
	var inventory: Node = actor.get_node("InventoryController3D")
	var weapon := inventory.get_equipped_item() as SampleWeapon3D
	check(weapon != null,"Runtime initialization must equip the assigned weapon: "+path)
	if weapon == null:
		actor.queue_free()
		await process_frame
		return
	var hand := actor.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	check(weapon.scene_file_path == record.weapon_scene and weapon.rigid_attachment_holder == hand,"Assigned weapon must attach to the generated hand")
	check(hand.get_visual_state() == &"grip","The armed hand must use its gripping model")
	check(weapon.wielder_character == actor and weapon.wielder_team_id == actor.faction_id,"Weapon damage ownership must match its character")
	check(weapon.to_global(weapon.attachment_local_position).is_equal_approx(hand.get_node("ItemSocket3D").global_position),"Weapon grip must match the hand socket")
	if record.name == "Bow": verify_bow_grips(actor,weapon)
	check(actor.get_node("LimbSwingController3D").has_npc_attack(&"PrimaryArm") == (record.name!="Bow"),"Bow must not fall back to a melee swing; other weapons retain the shared action")
	actor._equip_initial_weapon()
	actor._equip_initial_weapon()
	check(item_count(inventory) == 1,"Repeated setup must not duplicate the weapon")
	check(actor.generate_creature(),"Armed variant regeneration must succeed")
	await process_frame
	if record.name == "Bow": await physics_frame
	check(inventory.get_equipped_item() == weapon and item_count(inventory) == 1,"Regeneration must retain the same stored weapon")
	check(weapon.rigid_attachment_holder == actor.get_node("GeneratedParts/Arm_R") and weapon.rigid_attachment_holder != hand,"Regeneration must rebind the weapon to the new hand")
	check(weapon.rigid_attachment_holder.get_visual_state() == &"grip","New hand must restore the gripping model")
	if record.name == "Bow": verify_bow_grips(actor,weapon)
	inventory.select_slot(inventory.get_selected_slot())
	actor._equip_initial_weapon()
	check(inventory.get_equipped_item() == null and item_count(inventory) == 1,"Initial equipment must not override the user's deselected slot")
	actor.queue_free()
	await process_frame
	print("HUMAN_ARMED_VARIANT_PASS ",path)

func verify_bow_grips(actor: Node3D, weapon: SampleWeapon3D) -> void:
	var inventory: Node = actor.get_node("InventoryController3D")
	inventory._multi_grips.update(1.0/60.0)
	var rows: Array = inventory.get_weapon_grip_diagnostics().grips
	check(rows.size()==2 and rows[0].role=="primary" and rows[0].holder.ends_with("Arm_R"),"Bow Holder uses Arm_R")
	# Frozen arms retain their generated rest pose, so a bound grip can start outside reach.
	check(rows[1].role=="auxiliary" and rows[1].holder.ends_with("Arm_L") and rows[1].state in ["tracking","unreachable"] and actor.get_node("GeneratedParts/Arm_L").get_meta(&"equipment_grip_driver",null)==inventory,"Bow string grip assigns Arm_L without losing its binding")
	check(rows[1].force_length<=weapon.get_grip_settings(1).maximum_force+0.001,"Bow auxiliary grip force remains bounded")
	var center := weapon.get_node("StringCenterBody") as RigidBody3D
	check(weapon.get_grip_reaction_body(1)==center and weapon.get_grip_target_pose(1).origin==center.global_position,"Bow keeps its moving string grip after initialization/regeneration")
	check(weapon.ammunition_scene.resource_path=="res://Scenes/Items/Weapons/Arrow.tscn","Armed Human retains Arrow ammunition reference")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var base := load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate() as Node3D
	var body_set: int = base.get_node("HumanGenerator").human_set
	base.generate_on_ready = false
	base.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(base)
	freeze_parts(base)
	await process_frame
	await process_frame
	check(base.initial_weapon_scene == null and base.get_node("InventoryController3D").get_equipped_item() == null,"The original Human must remain unarmed by default")
	base.queue_free()
	await process_frame
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Scenes/Creatures/Characters/Human/Armed/variants.json"))
	check(manifest.variants.size() == 7,"Seven weapon variants and seven corresponding NPCs are required")
	for record: Dictionary in manifest.variants:
		await verify_variant(record,false,body_set)
		await verify_variant(record,true,body_set)
	print("HUMAN_ARMED_VARIANTS_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
