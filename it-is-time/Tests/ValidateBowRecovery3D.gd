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
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
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
	actor.get_node("InventoryController3D").inventory_ui_enabled = false
	actor.get_node("InventoryController3D").attachment_debug_logging = false
	level.add_child(actor)
	var controller: Node = actor.get_node("BowAttackController3D")
	for tick: int in ceili(controller.preset.maximum_prepare_time*60.0): await physics_frame
	check(controller._valid(),"Recovery regression captures the actual equipped bow")
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
	enemy.position.z += 4.0
	check(controller.predict_npc_attack(&"bow_shoot",target,0.8).get("hit",false),"Tighter firing stability does not shrink the existing target plane allowance")
	enemy.position.z -= 4.0
	var maximum_recovery_error := 0.0
	var maximum_target_change := 0.0
	var maximum_fire_error := 0.0
	var maximum_fire_speed := 0.0
	var recoveries := 0
	var shots := 0
	var locked := Vector3.ZERO
	var pre_draw: float = controller._pre_draw
	var previous_angles: Array = []
	var was_recovering := false
	for tick: int in 1500:
		await physics_frame
		if controller.is_npc_attack_active():
			check(controller.locked_point==locked,"A shot keeps its original static target point through recovery")
			check(is_equal_approx(controller._pre_draw,pre_draw),"The selected posture draw does not jump between IK searches")
		var angles: Array = []
		for arm: Dictionary in controller._arms: angles.append_array(arm.angles)
		if not previous_angles.is_empty():
			for index: int in angles.size(): maximum_target_change = maxf(maximum_target_change,rad_to_deg(absf(angles[index]-previous_angles[index])))
		previous_angles = angles.duplicate()
		if controller.shots_fired>shots:
			shots = controller.shots_fired
			maximum_fire_error = maxf(maximum_fire_error,controller.last_shot.aim_error_degrees)
			maximum_fire_speed = maxf(maximum_fire_speed,controller.last_shot.relative_angular_speed_degrees)
			check(controller.last_shot.aim_error_degrees<=controller.preset.aim_tolerance_degrees,"An arrow is released only inside the configured aim tolerance")
			check(controller.last_shot.relative_angular_speed_degrees<=controller.preset.settled_angular_speed_degrees,"An arrow is released only after bow motion settles")
		if controller.phase==controller.Phase.RECOVERING:
			maximum_recovery_error = maxf(maximum_recovery_error,rad_to_deg(controller._aim_error))
		elif was_recovering:
			check(controller.last_reason==&"recovered","Recovery reaches its stable pose before the safety timeout")
			check(controller._stable_elapsed>=controller.preset.settle_time,"Recovery requires a sustained stable pose")
			check(controller._aim_error<=deg_to_rad(controller.preset.aim_tolerance_degrees),"Recovery cannot finish while the bow is still far from its holding direction")
			recoveries += 1
		was_recovering = controller.phase==controller.Phase.RECOVERING
		if recoveries==3 and controller.damaging_hits==3: break
		if controller.phase==controller.Phase.IDLE and controller.shots_fired<3 and controller._cooldown<=0.0:
			check(controller.try_start_npc_attack(&"bow_shoot",target,0.8),"A recovered bow can start its next shot")
			locked = controller.locked_point
			pre_draw = controller._pre_draw
	check(shots==3 and controller.damaging_hits==3 and recoveries==3,"Three consecutive attacks fire, damage and recover without stalling")
	check(controller.cancelled_attacks==0,"Stable continuous shooting does not cancel preparation")
	check(maximum_recovery_error<15.0,"Recovery no longer swings fifty degrees past the holding direction")
	check(maximum_target_change<15.0,"IK joint targets remain continuous across drawing and recovery")
	print("BOW_RECOVERY_METRICS ",JSON.stringify({"shots":shots,"hits":controller.damaging_hits,"recoveries":recoveries,"maximum_recovery_error_degrees":maximum_recovery_error,"maximum_ik_target_change_degrees":maximum_target_change,"maximum_fire_error_degrees":maximum_fire_error,"maximum_fire_speed_degrees":maximum_fire_speed}))
	level.free()
	for arrow: Node in get_nodes_in_group(&"bow_projectiles"): arrow.free()
	await process_frame
	print("BOW_RECOVERY_PASSED" if failures.is_empty() else "BOW_RECOVERY_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
