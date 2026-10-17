extends SceneTree
const HUMAN = preload("res://Scenes/Creatures/Characters/Generate_Human.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Bow_NPC.tscn")
const BOW = preload("res://Scenes/Items/Weapons/Bow.tscn")
const PLANAR = preload("res://Scripts/Combat/BowArmPose3D.gd")
var failed := false
var measurements: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func verify_fall(enabled: bool, gravity_scale: float) -> void:
	var actor := HUMAN.instantiate() as Node3D
	actor.generate_on_ready = false
	actor.initial_weapon_scene = null
	root.add_child(actor)
	for node: Node in actor.get_children(): node.set_physics_process(false)
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false): body.freeze = true
	var inventory: Node = actor.get_node("InventoryController3D")
	inventory.attachment_debug_logging = false
	inventory.inventory_ui_enabled = false
	var holder: RigidBody3D = actor.get_node("GeneratedParts/Arm_R")
	var hand_mass := holder.mass
	check(inventory.equip_initial_weapon(BOW),"Bow equips through the actual rigid inventory attachment")
	var bow: Node = inventory.get_equipped_item()
	bow.held_gravity_compensation_enabled = enabled
	check(is_equal_approx(holder.mass,hand_mass+bow.mass),"Weight cancellation preserves the combined mass")
	check(is_equal_approx(bow.rigid_attachment_load.mass,bow.mass),"Equipment records only the actual merged Bow mass")
	check(bow.get_held_gravity_compensation().is_empty(),"Frozen holders receive no compensation force")
	for joint: Joint3D in actor.get_node("GeneratedParts/Joints").get_children(): PhysicsServer3D.joint_clear(joint.get_rid())
	inventory._multi_grips.release()
	holder.gravity_scale = gravity_scale
	holder.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	holder.linear_damp = 0.0
	holder.lock_rotation = true
	holder.freeze = false
	var center: RigidBody3D = bow.get_string_center()
	center.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	center.linear_damp = 0.0
	for tick: int in 3: await physics_frame
	var compensation: Dictionary = bow.get_held_gravity_compensation()
	var gravity: Vector3 = PhysicsServer3D.body_get_direct_state(holder.get_rid()).total_gravity
	check(not compensation.is_empty() if enabled else compensation.is_empty(),"Compensation follows the Inspector switch")
	if enabled:
		check(Vector3(compensation.force).is_equal_approx(-gravity*bow.mass),"Compensation uses the holder's actual gravity, including Gravity Scale exactly once")
		var original_center: Vector3 = inventory._rigid_attachment_snapshot.resolved_center
		var merged_center: Vector3 = (original_center*hand_mass+Vector3(bow.rigid_attachment_load.center)*bow.mass)/holder.mass
		check(merged_center.is_equal_approx(holder.center_of_mass),"The applied force uses the same Bow center as the compound mass calculation")
	var before := holder.linear_velocity*holder.mass+center.linear_velocity*center.mass
	for tick: int in 15: await physics_frame
	var after := holder.linear_velocity*holder.mass+center.linear_velocity*center.mass
	var expected := gravity*(hand_mass if enabled else holder.mass)*0.25
	check((after-before).distance_to(expected)<maxf(expected.length()*0.08,0.005),"Free-fall momentum loses only Bow weight; hand weight remains and no upward drift is introduced")
	measurements.append({"enabled":enabled,"gravity_scale":gravity_scale,"momentum_change":after-before,"expected":expected})
	if enabled and is_equal_approx(gravity_scale,1.0):
		inventory.select_slot(0)
		check(bow.rigid_attachment_load.is_empty() and bow.get_held_gravity_compensation().is_empty() and is_equal_approx(holder.mass,hand_mass),"Unequip stops cancellation and restores the holder's original mass")
		inventory.select_slot(0)
		for tick: int in 2: await physics_frame
		check(not bow.get_held_gravity_compensation().is_empty() and is_equal_approx(holder.mass,hand_mass+bow.mass),"Re-equipping restores one compensation load without accumulating mass")
		inventory._drop_equipped_item()
		check(bow.rigid_attachment_holder==null and bow.rigid_attachment_load.is_empty() and bow.get_held_gravity_compensation().is_empty(),"Dropping clears all held-weight compensation data")
		check(not bow.freeze and is_equal_approx(bow.gravity_scale,1.0),"Dropped Bow retains normal gravity")
		bow.position += Vector3(0,30,0)
		bow.linear_velocity = Vector3.ZERO
		bow.angular_velocity = Vector3.ZERO
		for tick: int in 12: await physics_frame
		check(bow.linear_velocity.y< -0.5,"Released Bow actually falls under gravity")
		bow.free()
	actor.free()
	await process_frame

func verify_servo_loads() -> void:
	var actor := NPC.instantiate() as Node3D
	actor.get_node("NPCStateMachine3D").enabled = false
	actor.get_node("InventoryController3D").attachment_debug_logging = false
	root.add_child(actor)
	for tick: int in 3: await physics_frame
	var controller: Node = actor.get_node("BowAttackController3D")
	check(controller._valid(),"Bow captures the actual equipped arm chains")
	var bow: Node = controller._bow
	var arm: Dictionary = controller._arms[0]
	bow.held_gravity_compensation_enabled = false
	PLANAR.apply(arm,controller._motor,1.0/60.0,0.0)
	var previous: Array[Vector3] = []
	for link: Dictionary in arm.pose_chain: previous.append(link.gravity_torque)
	bow.held_gravity_compensation_enabled = true
	var compensation: Dictionary = bow.get_held_gravity_compensation()
	check(not compensation.is_empty(),"Equipped moving arms provide an explicit compensation load")
	PLANAR.apply(arm,controller._motor,1.0/60.0,0.0)
	var parent: RigidBody3D = arm.anchor_body
	for index: int in arm.pose_chain.size():
		var link: Dictionary = arm.pose_chain[index]
		var pivot := parent.to_global(Transform3D(link.parent_frame).origin)
		var expected := -(Vector3(compensation.point)-pivot).cross(compensation.force)
		check((Vector3(link.gravity_torque)-previous[index]).distance_to(expected)<0.0001,"Every proximal arm joint subtracts the already-cancelled Bow weight exactly once")
		parent = link.body
	actor.free()
	await process_frame

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	await verify_fall(false,1.0)
	await verify_fall(true,1.0)
	await verify_fall(true,2.0)
	await verify_fall(true,0.0)
	await verify_servo_loads()
	var bow := BOW.instantiate() as RigidBody3D
	bow.freeze = true
	root.add_child(bow)
	var holder := RigidBody3D.new()
	root.add_child(holder)
	bow.rigid_attachment_holder = holder
	holder.free()
	check(bow.get_held_gravity_compensation().is_empty(),"A freed holder safely stops compensation before inventory cleanup")
	bow.free()
	print("BOW_HELD_GRAVITY_RESULTS ",JSON.stringify(measurements))
	print("BOW_HELD_GRAVITY_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
