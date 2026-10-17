extends SceneTree
const BOW = preload("res://Scenes/Items/Weapons/Bow.tscn")
const ARROW = preload("res://Scenes/Items/Weapons/Arrow.tscn")
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	await verify_string()
	await verify_equipment()
	print("BOW_FOUNDATION_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func verify_string() -> void:
	var bow := BOW.instantiate() as SampleWeapon3D
	bow.freeze = true
	bow.position = Vector3(3,5,2)
	root.add_child(bow)
	var arrow := ARROW.instantiate() as SampleWeapon3D
	arrow.freeze = true
	root.add_child(arrow)
	check(bow is SampleWeapon3D and arrow is SampleWeapon3D,"Bow and Arrow inherit the weapon base")
	check(SampleWeapon3D.WeaponTag.Shield==4 and SampleWeapon3D.WeaponTag.Bow==5 and SampleWeapon3D.WeaponTag.Arrow==6,"New tags preserve serialized legacy indices")
	check(bow.ammunition_scene==ARROW,"Bow references the separate Arrow ammunition scene")
	check(bow.get_arm_attack_preset()==null and arrow.get_arm_attack_preset()==null,"New ranged types do not select a spear attack preset")
	check(bow.get_grip_arm_path(0)==^"Arm_R" and bow.get_grip_arm_path(1)==^"Arm_L","Holder and string center use the specified hands")
	for name: String in ["Holder","BowArm_Upper","BowArm_Lower","String_Upper","String_Lower","StringCenter"]: check(bow.has_node(NodePath(name)),"Bow has component "+name)
	var center := bow.get_node("StringCenterBody") as RigidBody3D
	check(center.top_level and center.collision_layer==0 and center.collision_mask==0,"String mass moves independently without terrain/owner collisions")
	var rest := center.global_position
	var upper: Vector3 = bow.get_node("BowArm_Upper/Tip").global_position
	var lower: Vector3 = bow.get_node("BowArm_Lower/Tip").global_position
	check(is_equal_approx(upper.distance_to(lower),9.3661742),"Longer bow arms produce the calibrated tip span")
	check(is_equal_approx(bow.get_rest_grip_distance(),1.5),"Longer bow arms preserve the original hand separation")
	check(is_equal_approx((arrow.get_node("CollisionShape3D").shape as CapsuleShape3D).height,arrow.HALF_LENGTH*2.0),"Arrow collider and swept tip use the same resized length")
	for label: String in ["Upper","Lower"]:
		var model := bow.get_node("BowArm_"+label+"/Model") as MeshInstance3D
		var collision := bow.get_node(label+"ArmCollision") as CollisionShape3D
		check(model.global_transform.is_equal_approx(collision.global_transform) and model.get_aabb().size.is_equal_approx((collision.shape as BoxShape3D).size),"Resized bow arm visuals and colliders coincide")
		var direction := 1.0 if label=="Upper" else -1.0
		var half_length := model.get_aabb().size.y*0.5
		check((model.global_transform*Vector3(0,-direction*half_length,0)).distance_to(model.get_parent().global_position)<0.0001,"Lengthened arm base stays attached to the Holder")
		check((model.global_transform*Vector3(0,direction*half_length,0)).distance_to(bow.get_node("BowArm_"+label+"/Tip").global_position)<0.0001,"String endpoint stays at the lengthened arm tip")
	check((upper-rest).cross(lower-rest).length()<0.0001,"Rest strings form a straight line")
	for tick: int in 120: await physics_frame
	check(center.global_position.distance_to(rest)<0.002,"Preloaded strings remain balanced at rest")
	center.apply_central_impulse(bow.global_basis*Vector3(-0.06,0.01,0.015))
	var peak := 0.0
	for tick: int in 360:
		await physics_frame
		peak = maxf(peak,center.global_position.distance_to(rest))
		for force: Vector3 in bow.string_forces: check(force.is_finite() and force.length()<=bow.string_maximum_force+0.001,"Spring forces remain finite and bounded")
	var error := center.global_position.distance_to(rest)
	check(peak>0.03 and error<0.04,"Strings physically return a displaced string center with damping")
	check(bow._spring_force(upper,Vector3.ZERO,100.0,bow,1.0/60.0)==Vector3.ZERO,"Slack string never pushes the center")
	center.global_position = rest+Vector3(-0.25,0.1,0.08)
	bow._update_string_visuals()
	for label: String in ["Upper","Lower"]:
		var visual := bow.get_node("String_"+label) as MeshInstance3D
		var tip: Vector3 = bow.get_node("BowArm_"+label+"/Tip").global_position
		check((visual.global_transform*Vector3(0,-0.5,0)).distance_to(center.global_position)<0.0001 and (visual.global_transform*Vector3(0,0.5,0)).distance_to(tip)<0.0001,"Visible string endpoints match actual spring endpoints")
	bow.rotation.y = 0.8
	bow.position += Vector3(10,2,-3)
	bow.reset_string()
	check(center.global_position.distance_to(bow.to_global(bow.get_node("StringCenter").position))<0.0001,"Reset follows a translated and rotated bow")
	bow._sync_attachment()
	center.global_position += Vector3(-0.1,0,0)
	check(bow.get_grip_target_pose(1).origin==center.global_position,"Auxiliary target follows the moving string mass")
	check(bow.get_grip_reaction_body(1)==center,"Auxiliary hand reaction is applied to the string mass")
	print("BOW_STRING_PHYSICS peak_displacement=",peak," residual=",error)
	bow.free()
	check(not is_instance_valid(center),"Deleting Bow also deletes its independent string mass")
	arrow.free()
	await process_frame

func verify_equipment() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate()
	actor.generate_on_ready = false
	actor.initial_weapon_scene = null
	root.add_child(actor)
	for component: Node in actor.get_children():
		if component.name != &"GeneratedParts": component.set_physics_process(false)
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false): body.freeze = true
	var inventory = actor.get_node("InventoryController3D")
	inventory.inventory_ui_enabled = false
	inventory.attachment_debug_logging = false
	var right := actor.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	var left := actor.get_node("GeneratedParts/Arm_L") as PhysicalBodyPart3D
	var original_mass := right.mass
	check(inventory.equip_initial_weapon(BOW),"Existing inventory can equip Bow")
	await physics_frame
	var bow = inventory.get_equipped_item()
	var center := bow.get_node("StringCenterBody") as RigidBody3D
	check(bow.global_basis.get_scale().is_equal_approx(Vector3.ONE),"Bow keeps independent dimensions on a scaled Human hand")
	check(bow.rigid_attachment_holder==right and is_equal_approx(right.mass,original_mass+bow.mass),"Holder attaches rigidly to Arm_R exactly once")
	var rows: Array = inventory.get_weapon_grip_diagnostics().grips
	check(rows[0].state=="rigid_bound" and rows[1].state=="tracking" and rows[1].holder.ends_with("Arm_L"),"Arm_L is assigned to the movable auxiliary grip")
	bow._sync_attachment()
	center.global_position += Vector3(-0.2,0.1,0.0)
	var point := center.global_position
	inventory._multi_grips.update(1.0/60.0)
	rows = inventory.get_weapon_grip_diagnostics().grips
	check(Vector3(rows[1].target_world).distance_to(point)<0.00001 and rows[1].reaction_body=="StringCenterBody","Equipment driver reads the dynamic target and correct spring reaction body")
	check(rows[1].force_length<=bow.get_grip_settings(1).maximum_force+0.001,"Hand tracking remains force bounded")
	check(not bow.select_grip_point(1) and bow.active_grip_point==0,"String center cannot replace Holder or mutate the selected primary grip")
	inventory.select_slot(0)
	bow._sync_attachment()
	check(center.freeze and not left.has_meta(&"equipment_grip_driver") and is_equal_approx(right.mass,original_mass),"Storing Bow freezes its spring mass, releases the left hand and restores mass")
	inventory.select_slot(0)
	bow._sync_attachment()
	check(not center.freeze and bow.rigid_attachment_holder==right,"Re-equipping restores the string mass without stale world anchors")
	check(bow.global_basis.get_scale().is_equal_approx(Vector3.ONE),"Re-equipping preserves Bow dimensions")
	inventory._unequip_current_item()
	actor.free()
	await process_frame
