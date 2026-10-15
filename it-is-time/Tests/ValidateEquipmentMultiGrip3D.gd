extends SceneTree

const EDIT = preload("res://addons/weapon_workshop/grip_edit.gd")
const HUMAN = preload("res://Scenes/Creatures/Characters/Generate_Human.tscn")
const SPEAR = preload("res://Scenes/Items/Weapons/Human/Human1Spear.tscn")
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func actor_fixture() -> Node3D:
	var actor := HUMAN.instantiate() as Node3D
	actor.generate_on_ready = false
	actor.initial_weapon_scene = null
	# The isolated third-hand fixture intentionally has no Head/Torso joint chain.
	actor.require_head_and_torso_connectivity = false
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(actor)
	for body: RigidBody3D in actor.find_children("*", "RigidBody3D", true, false): body.freeze = true
	var inventory := actor.get_node("InventoryController3D")
	inventory.inventory_ui_enabled = false
	inventory.attachment_debug_logging = false
	return actor

func verify_generic() -> void:
	var actor := actor_fixture()
	var inventory := actor.get_node("InventoryController3D")
	var right := actor.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	var left := actor.get_node("GeneratedParts/Arm_L") as PhysicalBodyPart3D
	var third := left.duplicate() as PhysicalBodyPart3D
	third.name = "Arm_Third"
	actor.get_node("GeneratedParts").add_child(third)
	var item := SampleItem3D.new()
	item.name = "GenericMultiGripItem"
	item.mass = 0.5
	item.freeze = true
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	item.add_child(collision)
	collision.owner = item
	root.add_child(item)
	check(EDIT.is_weapon(item), "Common item base exposes the same grip editor")
	EDIT.apply(item, EDIT.prepare(item,&"count",6).after, item)
	check(item.grip_point_settings.size() == 6 and item.grip_point_settings[0] != item.grip_point_settings[1], "Each grip receives independent settings")
	item.grip_point_arm_paths = [^"Arm_R", ^"Arm_L", ^"Arm_Third", ^"Arm_L", ^"MissingArm", ^""]
	item.grip_point_settings[2].enabled = false
	var right_mass := right.mass
	var left_mass := left.mass
	var original_third_exception := third in right.get_collision_exceptions()
	var packed := PackedScene.new()
	check(packed.pack(item) == OK, "Serialize common item grip points and independent settings")
	item.free()
	check(inventory.equip_initial_item(packed), "Common equipment API accepts non-weapon items")
	item = inventory.get_equipped_item()
	var rows: Array = inventory.get_weapon_grip_diagnostics().grips
	check(rows.size() == 6 and rows[0].state == "rigid_bound" and rows[1].state == "tracking", "Generic item binds primary and auxiliary Arm simultaneously")
	check(rows[2].state == "disabled" and rows[3].state == "duplicate_arm" and rows[4].state == "arm_unavailable" and rows[5].state == "unassigned", "Disabled, duplicate, missing and blank auxiliary points are explicit")
	check(is_equal_approx(right.mass,right_mass+item.mass) and is_equal_approx(left.mass,left_mass), "Only primary Arm receives item mass")
	check(third in right.get_collision_exceptions() and right in third.get_collision_exceptions(), "Merged item geometry must not collide with dynamically added owner parts")
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	check(swing.is_body_driven(left) and swing.is_body_driven(actor.get_node("GeneratedParts/Arm_L_Limb_2")), "Holding claims the whole auxiliary chain against posture control")
	var original_spring: bool = inventory._multi_grips._bindings[0].springs[0].value
	var claimed_joint: Generic6DOFJoint3D = inventory._multi_grips._bindings[0].springs[0].joint
	item.grip_point_settings[2].enabled = true
	item.grip_point_settings[2].follow_rotation = true
	check(inventory.refresh_equipped_item_attachment(item), "Rebind common item after changing settings")
	check(inventory.get_weapon_grip_diagnostics().grips[2].state == "tracking", "Three Arms can hold the same item")
	var saved_pose := item.grip_point_poses[1]
	item.grip_point_poses[1].origin += Vector3(100,0,0)
	inventory._multi_grips.update(1.0/60.0)
	var unreachable: Dictionary = inventory.get_weapon_grip_diagnostics().grips[1]
	check(unreachable.state == "unreachable" and unreachable.force_length <= item.grip_point_settings[1].maximum_force, "Unreachable auxiliary targets report bounded physical force instead of stretching the chain")
	item.grip_point_poses[1] = saved_pose
	third.get_node("ItemSocket3D").position = Vector3.ZERO
	third.freeze = false
	third.gravity_scale = 0.0
	third.rotate_z(0.4)
	for frame: int in 120: await physics_frame
	var desired_rotation := (item.global_basis*item.grip_point_poses[2].basis.inverse()).get_rotation_quaternion()
	print("MULTI_GRIP_ROTATION error=",desired_rotation.angle_to(third.global_basis.get_rotation_quaternion())," broken=",third.is_broken," state=",inventory.get_weapon_grip_diagnostics().grips[2])
	check(desired_rotation.angle_to(third.global_basis.get_rotation_quaternion()) < 0.1, "Optional rotation tracking physically aligns an auxiliary hand")
	third.freeze = true
	check(item.select_grip_point(1) and item.rigid_attachment_holder == left, "Common items can switch the primary Arm")
	check(is_equal_approx(right.mass,right_mass) and is_equal_approx(left.mass,left_mass+item.mass), "Switch transfers mass once and rebuilds support roles")
	inventory.cancel_player_actions()
	check(not third.has_meta(&"equipment_grip_driver"), "Ragdoll cancellation releases auxiliary control")
	inventory._physics_process(1.0/60.0)
	check(third.has_meta(&"equipment_grip_driver"), "Normal physics resumes auxiliary control")
	third.is_broken = true
	inventory.handle_part_broken(third)
	check(inventory.get_equipped_item() == item and not third.has_meta(&"equipment_grip_driver"), "Broken auxiliary releases only itself")
	inventory.select_slot(0)
	check(not right.has_meta(&"equipment_grip_driver") and not left.has_meta(&"equipment_grip_driver"), "Unequip releases every Arm")
	check((third in right.get_collision_exceptions()) == original_third_exception, "Unequip restores the primary body's original internal collision exceptions")
	check(is_equal_approx(left.mass,left_mass) and claimed_joint.get("angular_spring_x/enabled") == original_spring, "Unequip restores mass and joint spring settings")
	inventory.select_slot(0)
	left.is_broken = true
	inventory.handle_part_broken(left)
	check(inventory.get_equipped_item() == null and item.can_be_picked_up and not right.has_meta(&"equipment_grip_driver"), "Broken primary drops the item and releases all support grips")
	item.queue_free()
	left.is_broken = false
	check(inventory.equip_initial_item(packed), "Re-equip a fresh multi-grip item for deletion cleanup")
	var deleted := inventory.get_equipped_item() as SampleItem3D
	check(left.has_meta(&"equipment_grip_driver"), "Deletion fixture has an active auxiliary Arm")
	deleted.free()
	inventory._physics_process(1.0/60.0)
	check(not left.has_meta(&"equipment_grip_driver") and is_equal_approx(right.mass,right_mass), "Deleting an equipped item restores auxiliary control and primary mass")
	actor.queue_free()
	await process_frame

func verify_spear_physics() -> void:
	var actor := actor_fixture()
	var inventory := actor.get_node("InventoryController3D")
	check(inventory.equip_initial_weapon(SPEAR), "Human can equip the authored two-grip Spear1")
	var item := inventory.get_equipped_item() as SampleWeapon3D
	var left := actor.get_node("GeneratedParts/Arm_L") as PhysicalBodyPart3D
	var rows: Array = inventory.get_weapon_grip_diagnostics().grips
	check(rows.size() == 2 and rows[0].holder.ends_with("Arm_L") and rows[1].holder.ends_with("Arm_R"), "Spear1 uses both saved Arm mappings")
	# Isolate auxiliary tracking with a reachable target; the authored idle pose needs both arms free.
	item.grip_point_poses[0].origin = item.to_local(left.get_node("ItemSocket3D").global_position+Vector3(0.2,0.2,0.0))
	check(inventory.refresh_equipped_item_attachment(item), "Rebind the isolated auxiliary tracking fixture")
	var support: Dictionary = inventory._multi_grips._bindings[0]
	for body: RigidBody3D in support.chain.bodies:
		body.freeze = false
		body.linear_damp = 2.0
		body.angular_damp = 2.0
	var socket: Marker3D = support.socket
	var target := item.to_global(item.grip_point_poses[0].origin)
	var initial_error := socket.global_position.distance_to(target)
	var best_error := initial_error
	var maximum_force := 0.0
	for frame: int in 240:
		await physics_frame
		rows = inventory.get_weapon_grip_diagnostics().grips
		if rows[0].has("error_length"): best_error = minf(best_error,rows[0].error_length)
		if rows[0].has("force_length"): maximum_force = maxf(maximum_force,rows[0].force_length)
	var final_error := socket.global_position.distance_to(item.to_global(item.grip_point_poses[0].origin))
	print("MULTI_GRIP_PHYSICS initial_error=",initial_error," final_error=",final_error," best_error=",best_error," max_force=",maximum_force," state=",rows[0])
	check(left.global_position.is_finite() and maximum_force <= support.settings.maximum_force+0.001, "Auxiliary tracking remains finite and force bounded")
	check(final_error < 0.08, "Human auxiliary hand must physically converge to Spear1 grip")
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	var primary_state: Dictionary = swing._states[0].members[0]
	var left_binding := primary_state.binding.duplicate() as ArmSwingBinding
	left_binding.drive_body_path = ^"../Arm_L_Limb_2"
	left_binding.follower_paths = [^"../Arm_L_Limb_1", ^"."]
	left_binding.joint_path = left.get_path_to(support.chain.joints[-1])
	left.arm_swing_bindings.append(left_binding)
	swing.refresh_arm_bindings(true)
	check(swing.begin_charge(0), "Primary Arm still controls weapon attacks")
	for state: Dictionary in swing._states[0].members:
		if state.effector == left: check(state.mode == swing.SwingState.IDLE, "Auxiliary Arm cannot independently attack while holding")
	primary_state = swing._states[0].members[0]
	for link: Dictionary in primary_state.pose_chain:
		link.body.freeze = false
		link.body.gravity_scale = 0.0
	for tick: int in 45:
		swing._process_member(0, primary_state, true, 1.0/60.0)
		await physics_frame
	swing.add_charge_time(0,0.3)
	swing.release_charge(0)
	check(item.swing_damage_active and swing.is_body_driven(left), "One damage action coexists with auxiliary holding")
	var attack_peak_error := 0.0
	for tick: int in 100:
		swing._process_member(0, primary_state, false, 1.0/60.0)
		await physics_frame
		var current: Dictionary = inventory.get_weapon_grip_diagnostics().grips[0]
		attack_peak_error = maxf(attack_peak_error, current.error_length)
		check(current.force_length <= support.settings.maximum_force+0.001 and left.global_position.is_finite(), "Auxiliary force stays bounded through a moving physical attack")
	print("MULTI_GRIP_ATTACK peak_error=",attack_peak_error," final=",inventory.get_weapon_grip_diagnostics().grips[0])
	inventory._unequip_current_item()
	check(not item.swing_damage_active and not left.has_meta(&"equipment_grip_driver"), "Unequip cancels the attack and auxiliary control")
	actor.queue_free()
	await process_frame

func run() -> void:
	await verify_generic()
	await verify_spear_physics()
	print("EQUIPMENT_MULTI_GRIP_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
