extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for index: int in range(count): await physics_frame
func run() -> void:
	var bird := BIRD.instantiate()
	bird.generate_on_ready = false
	bird.mass_limits_enabled = false
	bird.position.y = 20.0
	root.add_child(bird)
	bird.get_node("NPCStateMachine3D").enabled = false
	var generator := bird.get_node("BirdGenerator")
	generator.overall_scale = 1.5
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scale="): generator.overall_scale = float(argument.trim_prefix("--scale="))
	generator.unsymmetrie = 0.0
	generator.inhomogeneity = 0.0
	generator._random.seed = 43
	check(bird.generate_creature(),"Dive fixture must generate")
	await frames(120)
	var dive := bird.get_node("BirdDiveAttackController3D")
	dive.diagnostic_logging = true
	dive.data = dive.data.duplicate()
	var enemy := Node3D.new()
	enemy.set_script(CHARACTER)
	enemy.faction_id = bird.faction_id+1
	enemy.require_head_and_torso_connectivity = false
	root.add_child(enemy)
	var target_x := -5.0 if "--left" in OS.get_cmdline_user_args() else 5.0
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso])
	target.max_hp = 10000.0
	target.armor = 0.0
	target.freeze = true
	target.left_distance = 1.5
	target.right_distance = 1.5
	target.top_distance = 1.5
	target.bottom_distance = 1.5
	target.collision_thickness = 3.0
	enemy.add_child(target)
	target.global_position = dive._heads[0].global_position+Vector3(target_x,-8.0,1.5)
	await frames(3)
	check(dive.predict_npc_attack(&"bird_dive",target,0.0).hit,"Eligible lower enemy must pass prediction")
	var head_position: Vector3 = dive._heads[0].global_position
	var saved_target: Vector3 = target.global_position
	target.global_position = head_position+Vector3(5.0,-1.5,0.0)
	check(dive.predict_npc_attack(&"bird_dive",target,0.0).hit,"Valid shallow dive must not require an absolute three-unit height difference")
	target.global_position = head_position+Vector3(10.0,-8.0,3.0)
	check(dive.predict_npc_attack(&"bird_dive",target,0.0).hit,"Valid horizontal angle must not require an absolute Z lane width")
	target.global_position = head_position+Vector3(0.0,-8.0,0.0)
	check(bird.get_node("NPCStateMachine3D")._attack_in_range(preload("res://Resources/AI/BirdDiveAttack.tres"),target,0.0),"NPC must accept a vertical dive even when horizontal distance is zero")
	target.global_position = saved_target

	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0,2.0,2.0)
	collision.shape = box
	obstacle.add_child(collision)
	root.add_child(obstacle)
	obstacle.global_position = (target.global_position+dive._heads[0].global_position)*0.5
	await frames(2)
	check(not dive.predict_npc_attack(&"bird_dive",target,0.0).hit,"Terrain blocking the dive must reject prediction")
	obstacle.queue_free()
	await frames(2)
	var z := target.position.z
	target.position.z += 10.0
	check(not dive.predict_npc_attack(&"bird_dive",target,0.0).hit,"Excessive horizontal angle must reject dive")
	target.position.z = z
	enemy.faction_id = bird.faction_id
	check(not dive.try_start_action(&"bird_dive",target),"Friendly target must reject dive")
	enemy.faction_id = bird.faction_id+1
	var hp := target.current_hp
	var player := preload("res://Scenes/Player/Controller.tscn").instantiate()
	player.initial_character = bird
	root.add_child(player)
	await frames(2)
	check(player.get_controlled_character()==bird,"Player must attach to the generated bird")
	var click := InputEventAction.new()
	click.action = &"MouseLeft"
	click.pressed = true
	var aim_start_center: Vector3 = dive._flight._flight_structure().center
	player._unhandled_input(click)
	check(dive.is_active(),"Player MouseLeft must route to the dive action")
	var folded := false
	check(dive.is_aiming(),"Accepted attack must start in aiming, not diving")
	var aim_rise := 0.0
	var previous_phase: int = dive.phase
	var launch_checked := false
	var pulled_up := false
	for frame: int in range(600):
		await physics_frame
		if dive.is_aiming():
			check(is_equal_approx(target.current_hp,hp),"Aiming must not deal attack damage")
			aim_rise = maxf(aim_rise,Vector3(dive._flight._flight_structure().center).y-aim_start_center.y)
		if dive.phase == dive.Phase.DIVING and previous_phase == dive.Phase.AIMING:
			check(not dive._temporary_weapons.is_empty(), "Diving must create an independent weapon identity")
			var head: PhysicalBodyPart3D = dive._heads[0]
			var cone := head.get_node_or_null("DiveWeaponCone") as CollisionShape3D
			check(cone != null and cone.shape is ConvexPolygonShape3D, "Head must receive a cone-shaped compound collider")
			check(SampleWeapon3D.from_contact(head, 0) == null, "Ordinary Head geometry must not become weapon geometry")
			var ready: Dictionary = dive._get_aiming_readiness(bird.get_node("WingPoseController3D"))
			check(ready.head_ready and ready.wings_ready,"Dive must launch only after actual Head and Wing poses are ready")
			launch_checked = true
		previous_phase = dive.phase
		folded = folded or bird.get_node("WingPoseController3D").unfold_ratio<0.1
		pulled_up = pulled_up or dive.phase == dive.Phase.PULLING_UP
		if not dive.is_active(): break
	print("[bird_dive_test] impact=",dive._last_impact," hp_before=",hp," hp_after=",target.current_hp," folded=",folded," pulled_up=",pulled_up)
	check(aim_rise>0.1,"Aiming must slowly raise the whole creature")
	check(launch_checked,"Aiming must finish with a validated launch")
	check(folded,"Dive must fold wings before impact")
	check(target.current_hp<hp,"Actual cone contact must cause impulse damage")
	check(dive._temporary_weapons.is_empty(), "Completed dive must remove temporary weapons")
	check(pulled_up and not dive.is_active(),"Dive must pull up and restore ordinary flight")
	check(not dive._heads[0].continuous_cd,"Temporary CCD must restore after action")
	check(not dive.try_start_action(&"bird_dive",target),"Cooldown must prevent immediate repeat")
	player.detach_character()
	player.queue_free()
	await frames(2)
	await frames(180)
	target.global_position = dive._heads[0].global_position+Vector3(target_x,-8.0,1.5)
	await frames(2)
	check(dive.predict_npc_attack(&"bird_dive",target,0.0).hit,"NPC fixture must have an eligible target after the prior dive")
	var sequence: int = dive._sequence
	bird.get_node("NPCStateMachine3D").enabled = true
	for frame: int in range(300):
		await physics_frame
		if dive._sequence>sequence: break
	check(dive._sequence>sequence and dive.is_npc_attack_active(),"NPC must select the dive through its configured attack receiver")
	bird.get_node("NPCStateMachine3D").enabled = false
	dive.cancel_action(&"test_cancel")
	check(not dive.is_active() and not dive._heads[0].continuous_cd,"Cancellation must release overrides and restore CCD")
	print("[bird_dive_test] npc_sequence=",dive._sequence)
	dive._cooldown = 0.0
	target.global_position = dive._heads[0].global_position+Vector3(target_x,-8.0,1.5)
	var wing := bird.get_node("WingPoseController3D")
	wing.enabled = false
	dive.data.maximum_aiming_time = 1.2
	check(dive.try_start_action(&"bird_dive",target),"Timeout fixture must enter aiming")
	await frames(90)
	check(not dive.is_active() and not dive._heads[0].continuous_cd,"Unready wings must cancel on timeout and restore CCD")
	check(dive._cooldown>0.0,"Aim timeout must apply cooldown")
	wing.enabled = true
	dive.data.maximum_aiming_time = 6.0

	dive._cooldown = 0.0
	target.global_position = dive._heads[0].global_position+Vector3(target_x,-8.0,1.5)
	await frames(2)
	check(dive.try_start_action(&"bird_dive",target),"Target-loss fixture must start")
	target.queue_free()
	await frames(2)
	check(dive.phase == dive.Phase.PULLING_UP,"A disappearing target must trigger safe pull-up")
	dive.set_character_control_enabled(false)
	check(not dive.is_active(),"Broken/disabled characters must stop dive immediately")
	bird.queue_free(); enemy.queue_free()
	print("BIRD_DIVE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
