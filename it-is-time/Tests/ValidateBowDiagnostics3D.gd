extends SceneTree
const NPC = preload("res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Bow_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const TARGET = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn")
var failures: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value or failures.has(message): return
	failures[message] = true
	push_error(message)

func run() -> void:
	var console: Node = root.get_node("RuntimeConsole")
	console.auto_getlogs_enabled = false
	console.maximum_output_lines = 200
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,100)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var actor := NPC.instantiate() as Node3D
	actor.get_node("NPCStateMachine3D").enabled = false
	actor.get_node("InventoryController3D").attachment_debug_logging = false
	level.add_child(actor)
	for tick: int in 300: await physics_frame
	var controller: Node = actor.get_node("BowAttackController3D")
	check(controller._valid(),"The actual equipped Bow captures both arm chains")
	var bow: Node = controller._bow
	console.execute_command("trackbow on UnrelatedNPC")
	var output_count: int = console._output_lines.size()
	controller._log_bow_event(&"probe")
	check(console._output_lines.size()==output_count,"Event logging respects the selected character filter")
	console.execute_command("trackbow on "+str(actor.name))
	check(console.is_bow_tracking_enabled(controller),"The existing trackbow command enables matching phase events")
	var enemy := Node3D.new()
	enemy.set_script(CHARACTER)
	enemy.faction_id = actor.faction_id+1
	enemy.require_head_and_torso_connectivity = false
	var target := TARGET.instantiate() as PhysicalBodyPart3D
	target.name = "Torso"
	target.freeze = true
	target.max_hp = 10000.0
	target.current_hp = 10000.0
	target.armor = 0.0
	enemy.add_child(target)
	level.add_child(enemy)
	enemy.global_position = controller._arms[0].anchor_body.global_position+Vector3(35,0,0)
	await physics_frame
	check(controller.try_start_npc_attack(&"bow_shoot",target,0.8),"A real physical shot starts with detailed logging enabled")
	var saw_drive := false
	var saw_release := false
	var events: Dictionary = {}
	for tick: int in 480:
		await physics_frame
		var row: Dictionary = controller.get_attack_diagnostics()
		var string: Dictionary = row.string
		check(int(string.force_physics_frame)<=int(row.physics_frame),"Cached string forces carry their actual application frame")
		check(row.pose.has("desired_forward") and row.pose.has("relative_angular_velocity"),"Snapshots distinguish Bow aim and relative body motion")
		for spring: Dictionary in string.springs:
			if string.holder_reaction_enabled: check(Vector3(spring.force_on_center).is_equal_approx(-Vector3(spring.force_on_holder)),"Each real string reports equal and opposite applied forces")
		if string.applied_draw_distance<0.0:
			check(Vector3(string.draw_force_on_center).is_zero_approx(),"Released strings do not report a stale drawing force")
			if controller.shots_fired>0: saw_release = true
		elif Vector3(string.draw_force_on_center).length()>0.001: saw_drive = true
		var total: Vector3 = Vector3(string.spring_reaction_torque_on_holder)+Vector3(string.draw_reaction_torque_on_holder)+Vector3(string.held_gravity_compensation.applied_torque)
		check(total.is_equal_approx(string.total_script_torque_on_holder),"Holder torque decomposition accounts for strings, drawing and weight cancellation")
		for joint: Dictionary in row.arm_joints:
			var requested: Vector3 = Vector3(joint.carried_servo_torque)+Vector3(joint.gravity_torque)
			check(requested.is_equal_approx(joint.requested_torque),"Joint diagnostics distinguish carried pose drive from gravity compensation")
			check(requested.limit_length(controller.preset.maximum_pose_torque).is_equal_approx(joint.torque),"Logged joint torque is the torque actually sent after its cap")
			check(Vector3(joint.torque).is_finite() and is_finite(joint.command_degrees),"Live motor diagnostics remain finite during a shot")
		for line: String in console._output_lines:
			if not line.begins_with("[bow_event] "): continue
			var event: Dictionary = JSON.parse_string(line.trim_prefix("[bow_event] "))
			events[event.event] = true
		if controller.shots_fired>0 and controller.phase==controller.Phase.IDLE and controller.damaging_hits>0: break
	check(controller.shots_fired==1 and controller.damaging_hits==1,"Diagnostics preserve an actual damaging shot")
	check(saw_drive and saw_release,"The run covers both drawing actuation and released recovery")
	for event: String in ["attack_started","drawing_started","shot_fired","recovery_finished","pose_replanned"]:
		check(events.has(event),"The log includes the exact "+event+" event")
	while controller._cooldown>0.0: await physics_frame
	check(controller.try_start_npc_attack(&"bow_shoot",target,0.8),"A second attack can be diagnosed independently")
	controller.cancel_npc_attack(&"diagnostic_test_cancel")
	var cancellation: Dictionary = JSON.parse_string(String(console._output_lines[-1]).trim_prefix("[bow_event] "))
	check(cancellation.event=="attack_cancelled" and cancellation.details.cause=="diagnostic_test_cancel","Cancellation records its cause and previous phase separately from completed shots")
	console.execute_command("trackbow off")
	output_count = console._output_lines.size()
	controller._log_bow_event(&"probe")
	check(console._output_lines.size()==output_count,"trackbow off suppresses events as well as periodic snapshots")
	actor.get_node("InventoryController3D").select_slot(0)
	for tick: int in 3: await physics_frame
	var hidden: Dictionary = bow.get_string_diagnostics()
	check(not hidden.holder_reaction_enabled and Vector3(hidden.draw_force_on_center).is_zero_approx(),"Unequipping clears reported drawing and string reactions")
	check(Vector3(hidden.held_gravity_compensation.applied_force).is_zero_approx(),"Unequipping clears the applied weight-cancellation diagnostic")
	level.free()
	for arrow: Node in get_nodes_in_group(&"bow_projectiles"): arrow.free()
	await process_frame
	print("BOW_DIAGNOSTICS_PASSED" if failures.is_empty() else "BOW_DIAGNOSTICS_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
