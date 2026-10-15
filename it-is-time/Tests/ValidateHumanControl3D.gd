extends SceneTree
class Commands extends Node:
	var direction := Vector3.ZERO
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing
	func is_jump_requested() -> bool: return false
	func is_fast_requested() -> bool: return false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100,1,100)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	var requested_set := 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--human-set="): requested_set = int(argument.trim_prefix("--human-set="))
	for set_index: int in [1,2,3,4,5]:
		if requested_set != 0 and set_index != requested_set: continue
		var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		var generator := actor.get_node("HumanGenerator")
		if generator.human_set != set_index: generator.use_manual_layout = false
		generator.human_set = set_index
		assert(actor.generate_creature())
		var commands := Commands.new()
		actor.add_child(commands)
		var movement := actor.get_node("GeneratedLegStepMovementController3D")
		movement.command_source = commands
		var torso := actor.get_node("GeneratedParts/Torso") as PhysicalBodyPart3D
		var initial_y := torso.position.y
		for tick: int in 180: await physics_frame
		assert(torso.position.y > initial_y * 0.75 and torso.global_basis.y.dot(Vector3.UP) > 0.8)
		var start := torso.position
		commands.direction = Vector3.BACK
		for tick: int in 180: await physics_frame
		commands.direction = Vector3.ZERO
		print("HUMAN_SIDEWAYS set=",set_index," displacement=",torso.position-start)
		assert(torso.position.z > start.z + 0.3)
		commands.facing = Vector3.LEFT
		for tick: int in 600:
			await physics_frame
			if absf(wrapf(PI-movement._get_physical_heading_yaw(),-PI,PI)) < deg_to_rad(10.0): break
		print("HUMAN_TURN set=",set_index," heading=",rad_to_deg(movement._get_physical_heading_yaw())," status=",movement._layout_turn_status," up=",torso.global_basis.y.dot(Vector3.UP))
		assert(absf(wrapf(PI-movement._get_physical_heading_yaw(),-PI,PI)) < deg_to_rad(15.0))
		actor.free()
		await process_frame
	# Equipment remains on the hand while the shoulder drives the attack.
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor.generate_creature())
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true
	var inventory := actor.get_node("InventoryController3D")
	inventory.inventory_ui_enabled = false
	var item := load("res://Scenes/Items/Weapon_Test.tscn").instantiate() as SampleItem3D
	root.add_child(item)
	item.build_from_material_cells([Vector2i.ZERO] as Array[Vector2i], Vector2.ZERO, Vector2.ZERO, 0.0, &"", true)
	inventory._store_item(item, 0)
	assert(inventory.get_equipped_item() == item)
	assert(item.rigid_attachment_holder == actor.get_node("GeneratedParts/Arm_R"))
	var old_holder: Node = item.rigid_attachment_holder
	assert(actor.generate_creature())
	assert(inventory.get_equipped_item() == item and item.rigid_attachment_holder != old_holder)
	assert(item.rigid_attachment_holder == actor.get_node("GeneratedParts/Arm_R"))
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	assert(swing.begin_charge(0))
	swing.add_charge_time(0, 0.5)
	assert(swing.release_charge(0))
	assert(item.swing_damage_active)
	# Losing an intermediate joint invalidates the complete commanded chain.
	var state: Dictionary = swing._states[0].members[0]
	state.followers[0].joint.queue_free()
	swing._process_member(0,state,true,1.0/60.0)
	assert(int(state.mode) == LimbSwingController3D.SwingState.IDLE)
	actor.free()
	floor_body.free()
	await process_frame
	print("PASS: Requested Human variants stand, move sideways and turn; equipment survives regeneration; broken chains cancel swing.")
	quit()
