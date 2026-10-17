extends SceneTree
const NPC = preload("res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Bow_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const TORSO = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn")
const ARROW = preload("res://Scripts/Items/ArrowWeapon3D.gd")
var failed := false
var results: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func target(faction: int, point: Vector3) -> Node3D:
	var actor := Node3D.new()
	actor.set_script(CHARACTER)
	actor.faction_id = faction
	actor.require_head_and_torso_connectivity = false
	var body := TORSO.instantiate() as PhysicalBodyPart3D
	body.name = "Torso"
	body.freeze = true
	body.max_hp = 10000.0
	body.current_hp = 10000.0
	body.armor = 0.0
	actor.add_child(body)
	root.add_child(actor)
	actor.global_position = point
	return actor

func verify_shot(side: float, moving: bool = false, distance: float = 25.0) -> void:
	var actor := NPC.instantiate() as Node3D
	actor.generate_on_ready = false
	actor.get_node("NPCStateMachine3D").enabled = false
	actor.get_node("BowAttackController3D").enabled = false
	actor.get_node("InventoryController3D").inventory_ui_enabled = false
	actor.get_node("InventoryController3D").attachment_debug_logging = false
	if side<0.0: actor.rotation.y = PI
	root.add_child(actor)
	await process_frame
	await process_frame
	for component: Node in actor.get_children(): component.set_physics_process(false)
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false):
		body.freeze = true
		body.gravity_scale = 0.0
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	var bow_controller: Node = actor.get_node("BowAttackController3D")
	bow_controller.enabled = true
	bow_controller.set_physics_process(true)
	for label: String in ["Arm_R","Arm_L","Arm_R_Limb_1","Arm_R_Limb_2","Arm_L_Limb_1","Arm_L_Limb_2"]:
		actor.get_node("GeneratedParts/"+label).freeze = false
	var torso: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Torso")
	var enemy := target(actor.faction_id+1,torso.global_position+Vector3(side*distance,0,0))
	var body: PhysicalBodyPart3D = enemy.get_node("Torso")
	await physics_frame
	await physics_frame
	check(bow_controller.has_npc_attack(&"bow_shoot"),"Bow controller captures two intact arm chains")
	check(not actor.get_node("LimbSwingController3D").has_npc_attack(&"PrimaryArm"),"Bow cannot use melee fallback")
	if distance>200.0:
		for offset: Vector3 in [Vector3(20000,400,0),Vector3(-20000,-400,0),Vector3(1000,1000,0)]:
			var solution: Dictionary = bow_controller._shot_solution(Vector3.ZERO,offset,42.0)
			check(not solution.is_empty(),"Adaptive ballistics have no fixed distance or height ceiling")
			if not solution.is_empty():
				var arrival: Vector3 = Vector3(solution.velocity)*solution.time+ARROW.gravity_vector()*solution.time*solution.time*0.5
				check(arrival.distance_to(offset)<0.02,"Adaptive ballistic solutions arrive at their distant mathematical targets")
	var ai: Node = actor.get_node("NPCStateMachine3D")
	ai._enemy = enemy
	ai._target = body
	var target_start := enemy.position
	enemy.position = torso.global_position+Vector3(side*2.0,0,0)
	check(not bow_controller.is_npc_target_in_attack_range(&"bow_shoot",body),"Targets inside the minimum Bow range are rejected")
	enemy.position = torso.global_position+Vector3(side*1000.0,0,0)
	check(bow_controller.is_npc_target_in_attack_range(&"bow_shoot",body),"Distant targets have no maximum Bow range")
	check(bow_controller.has_unlimited_npc_attack_range(&"bow_shoot") and is_inf(ai._attack_maximum_range(ai.behavior.attacks[0],body)),"The normal NPC selector also sees unlimited Bow range")
	enemy.position = target_start
	# Real arm/weapon physics, with the Torso frozen to isolate aiming from gait.
	for tick: int in 240: await physics_frame
	if side>0.0 and not moving:
		var wall := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.1,30,30)
		collision.shape = box
		wall.add_child(collision)
		root.add_child(wall)
		wall.position = torso.global_position+Vector3(12,0,0)
		await physics_frame
		await physics_frame
		check(bow_controller.predict_npc_attack(&"bow_shoot",body,0.8).get("reason")==&"ballistic_path_blocked","An obstacle blocks attack selection before drawing")
		wall.free()
		await physics_frame
	if moving:
		body.freeze = false
		body.gravity_scale = 0.0
		body.mass = 10000.0
		body.linear_damp = 0.0
		body.lock_rotation = true
		body.linear_velocity = Vector3(side*-2.0,0,0)
	var prediction: Dictionary = bow_controller.predict_npc_attack(&"bow_shoot",body,0.8)
	check(prediction.hit,"A clear ballistic path is predicted")
	var started: bool = ai._try_attack(distance)
	check(started,"Human NPC selects the Bow receiver through its normal attack gate")
	var locked: Vector3 = bow_controller.locked_point
	for tick: int in 1200:
		await physics_frame
		if tick%60==59: print("BOW_POSE ",side," ",bow_controller.get_attack_diagnostics())
		if bow_controller.shots_fired>0 and not bow_controller.is_npc_attack_active() and bow_controller.hits>0: break
	check(bow_controller.locked_point==locked,"Aim point stays fixed throughout the attack")
	var row: Dictionary = bow_controller.get_attack_diagnostics()
	row.side = side
	row.moving = moving
	row.distance = distance
	row.hp_damage = body.max_hp-body.current_hp
	results.append(row)
	check(bow_controller.shots_fired==1,"One selected attack fires exactly one Arrow")
	check(row.hp_damage>0.0,"Swept projectile contact deals real global-service damage")
	check(bow_controller.phase==bow_controller.Phase.IDLE,"The Bow recovers after firing")
	if distance>200.0:
		check(row.last_shot.speed>bow_controller.preset.maximum_arrow_speed,"A distant shot raises speed above the reference full-draw speed")
		check(row.last_shot.lifetime>bow_controller.preset.arrow_lifetime and row.last_shot.lifetime>row.last_shot.flight_time,"Distant arrows survive for the predicted flight instead of expiring early")
	var console: Node = root.get_node("RuntimeConsole")
	check(console.execute_command("trackbow on GenerateHumanBowNPC").contains("matched=1"),"Bow logging finds its matching character")
	check(console.execute_command("trackbow off").contains("disabled"),"Bow logging can be disabled")
	# Regeneration during a second draw must discard the nocked arrow and stale joints.
	bow_controller._cooldown = 0.0
	check(bow_controller.try_start_npc_attack(&"bow_shoot",body,0.8),"A recovered Bow can prepare another shot")
	var resume_point := enemy.position
	enemy.position = torso.global_position+Vector3(side*2.0,0,0)
	await physics_frame
	await physics_frame
	check(not bow_controller.is_npc_attack_active() and bow_controller.last_reason==&"target_too_close" and bow_controller.shots_fired==1,"A target entering the minimum range cancels drawing before another shot")
	enemy.position = resume_point
	await physics_frame
	check(bow_controller.try_start_npc_attack(&"bow_shoot",body,0.8),"The Bow can resume preparing after the target leaves its minimum range")
	for tick: int in ceili(bow_controller.preset.maximum_prepare_time*60.0):
		await physics_frame
		if bow_controller.phase==bow_controller.Phase.DRAWING: break
	check(is_instance_valid(bow_controller._nocked),"Drawing creates a harmless nocked arrow")
	if is_instance_valid(bow_controller._nocked):
		check(not bow_controller._nocked.swing_damage_active and bow_controller._nocked.collision_layer==0,"A nocked arrow cannot damage its owner or nearby parts")
	var old_nocked: Object = bow_controller._nocked
	var old_hand_id: int = actor.get_node("GeneratedParts/Arm_R").get_instance_id()
	check(actor.generate_creature(),"Armed Bow actor can regenerate during a draw")
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true
	await process_frame
	await physics_frame
	await physics_frame
	check(not is_instance_valid(old_nocked) and not bow_controller.is_npc_attack_active(),"Regeneration cancels the unfinished shot and frees its nocked arrow")
	check(bow_controller._valid() and bow_controller._arms[0].hand.get_instance_id()!=old_hand_id,"Regeneration captures only the newly generated arms")
	if side>0.0 and not moving:
		bow_controller.set_character_control_enabled(false)
		check(bow_controller._arms.is_empty(),"Disabling character controls restores the Bow pose override")
		bow_controller.set_character_control_enabled(true)
		await physics_frame
		await physics_frame
		check(bow_controller._valid(),"Restoring character controls reacquires the equipped Bow")
		actor.get_node("GeneratedParts/Arm_L").break_part()
		await physics_frame
		await physics_frame
		check(not bow_controller.has_npc_attack(&"bow_shoot") and bow_controller._arms.is_empty(),"Breaking the string hand prevents further shots and releases both pose chains")
	var inventory: Node = actor.get_node("InventoryController3D")
	inventory.select_slot(inventory.get_selected_slot())
	await physics_frame
	check(bow_controller._arms.is_empty() and not actor.get_node("GeneratedParts/Arm_R").has_meta(&"equipment_bow_pose_driver"),"Unequip releases arm ownership and restores constraints")
	actor.free()
	enemy.free()
	for arrow: Node in get_nodes_in_group(&"bow_projectiles"): arrow.free()
	await process_frame

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	await verify_scene_perception()
	await verify_shot(1.0)
	await verify_shot(-1.0)
	await verify_shot(1.0,true)
	await verify_shot(1.0,false,500.0)
	print("HUMAN_BOW_RESULTS ",JSON.stringify(results))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file := FileAccess.open(argument.trim_prefix("--report="),FileAccess.WRITE)
			if file!=null: file.store_string(JSON.stringify(results,"\t"))
	print("HUMAN_BOW_ATTACK_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func verify_scene_perception() -> void:
	var actor := NPC.instantiate() as Node3D
	actor.generate_on_ready = false
	actor.initial_weapon_scene = null
	actor.get_node("NPCStateMachine3D").enabled = false
	root.add_child(actor)
	for component: Node in actor.get_children(): component.set_physics_process(false)
	for part: RigidBody3D in actor.find_children("*","RigidBody3D",true,false): part.freeze = true
	var ai: Node = actor.get_node("NPCStateMachine3D")
	ai.enabled = true
	ai.attack_execution_enabled = false
	var origin: Vector3 = actor.get_node("GeneratedParts/Torso").global_position
	var friendly := target(actor.faction_id,origin+Vector3(20,0,0))
	var distant := target(actor.faction_id+1,origin+Vector3(20000,400,0))
	var other_world := SubViewport.new()
	other_world.own_world_3d = true
	root.add_child(other_world)
	var unrelated := target(actor.faction_id+1,origin+Vector3(10,0,0))
	unrelated.reparent(other_world)
	await physics_frame
	ai._update_combat(0.5)
	check(ai._enemy==distant,"Scene-wide Bow perception finds a distant elevated hostile while ignoring allies and another World3D")
	check(is_inf(ai.behavior.maximum_vertical_difference),"Bow has no independent height-distance ceiling")
	var closer := target(actor.faction_id+1,origin+Vector3(1000,0,0))
	ai._target_switch_remaining = 0.0
	ai._scan_elapsed = 0.0
	ai._update_combat(0.5)
	check(ai._enemy==closer,"All distant enemies participate in normal nearest-target selection")
	actor.free()
	friendly.free()
	distant.free()
	closer.free()
	other_world.free()
	await process_frame
