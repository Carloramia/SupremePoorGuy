extends SceneTree

var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Human/Metadata/weapon_manifest.json"))
	check(manifest.weapons.size() == 6,"Six Human weapon scenes are required")
	var npc := load("res://Scenes/Creatures/Characters/Generate_Human_NPC.tscn").instantiate() as Node3D
	npc.generate_on_ready = false
	npc.initial_weapon_scene = null
	npc.process_mode = Node.PROCESS_MODE_DISABLED
	for body: Node in npc.find_children("*","RigidBody3D",true,false): body.freeze = true
	root.add_child(npc)
	var inventory: Node = npc.get_node("InventoryController3D")
	inventory.inventory_ui_enabled = false
	inventory.attachment_debug_logging = false
	var hand := npc.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	var original_mass := hand.mass
	var target := load("res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn").instantiate() as PhysicalBodyPart3D
	target.freeze = true
	target.max_hp = 10000.0
	target.mass_based_health = false
	target.armor = 0.0
	root.add_child(target)
	for record: Dictionary in manifest.weapons:
		var packed := load(record.weapon_scene) as PackedScene
		check(packed != null,"Weapon scene must load: "+str(record.name))
		if packed == null: continue
		check(packed.get_state().get_base_scene_state() != null,"Weapon must use scene inheritance")
		var item := packed.instantiate() as SampleWeapon3D
		check(item != null,"Weapon must inherit SampleWeapon3D")
		if item == null: continue
		item.freeze = true
		root.add_child(item)
		check(item.is_pickable() and item.has_attachment_point,"Weapon must be pickable and have a grip point")
		check(item.get_item_image() != null and item.get_item_image().resource_path == record.source_texture,"Inventory icon must use the actual separated weapon texture")
		check(await item.create_item_image() == item.item_image,"Assigned weapon icon must survive icon generation")
		var model := item.get_node("Model/PaperVolume") as MeshInstance3D
		check(model.mesh.resource_path == record.volume_mesh and model.mesh.get_surface_count() == 3,"Weapon must use the baked front/back/side model")
		check(is_equal_approx(model.scale.z,record.thickness),"Model must retain source thickness")
		var shape := item.get_node("CollisionShape3D").shape as ConvexPolygonShape3D
		check(shape != null and shape.points.size() >= 8,"Weapon requires an active convex collider")
		var min_z := INF
		var max_z := -INF
		for point: Vector3 in shape.points:
			min_z = minf(min_z,point.z)
			max_z = maxf(max_z,point.z)
		check(is_equal_approx(max_z-min_z,record.thickness),"Collision and model thickness must match")
		item.mesh_visible = false
		item.sprite_visible = true
		check(not model.visible and item.get_node("Sprite3D").visible,"Inherited visual switches must support the sprite alternative")
		item.mesh_visible = true
		item.sprite_visible = false
		check(SampleWeapon3D.from_contact(item,0) == item,"Loose weapon contacts must resolve as weapon hits")
		item.begin_damage_swing()
		var hp := target.current_hp
		check(item.apply_contact_damage(target,10.0) > 0.0 and target.current_hp < hp,"Weapon must use the global impulse damage settlement")
		check(item.apply_contact_damage(target,10.0) == 0.0,"One swing must not hit the same Part twice")
		item.end_damage_swing()
		item.queue_free()
		await process_frame
		check(inventory.equip_initial_weapon(packed),"NPC initial equipment must accept "+str(record.name))
		var equipped := inventory.get_equipped_item() as SampleWeapon3D
		check(equipped != null and equipped.rigid_attachment_holder == hand,"Weapon must use the existing hand attachment")
		if equipped != null:
			check(equipped.to_global(equipped.attachment_local_position).is_equal_approx(hand.get_node("ItemSocket3D").global_position),"Weapon grip must coincide with the actual holder socket")
			check(hand.get_visual_state() == &"grip","Equipping must apply the Human gripping hand model")
			check(inventory._rigid_attachment_shapes.size() == 1,"Weapon collider must merge into the hand")
			var merged: CollisionShape3D = inventory._rigid_attachment_shapes[0]
			var shape_index := -1
			for owner_id: int in hand.get_shape_owners():
				if hand.shape_owner_get_owner(owner_id) == merged: shape_index = hand.shape_owner_get_shape_index(owner_id,0)
			check(SampleWeapon3D.from_contact(hand,shape_index) == equipped,"Merged weapon contacts must resolve to the equipped weapon")
		inventory.select_slot(inventory.get_selected_slot())
		check(hand.get_visual_state() == &"" and is_equal_approx(hand.mass,original_mass),"Unequip must restore the hand appearance and mass")
		# Release the stored fixture before testing the next weapon in slot zero.
		if is_instance_valid(equipped): equipped.queue_free()
		await process_frame
		print("HUMAN_WEAPON_PASS ",record.name)
	npc.queue_free()
	target.queue_free()
	await process_frame
	print("HUMAN_WEAPONS_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
