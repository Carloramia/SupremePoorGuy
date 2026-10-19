extends "res://Tests/ValidateSpearNPCCombat3D.gd"
## Frozen bodies isolate AI range/phase decisions; the existing Spear combat test checks physical thrusts.
const RAT = preload("res://Scenes/Creatures/Characters/Generate_Rat_1_NPC.tscn")
var low_target := false

func verify(side: float) -> void:
	var actor := HUMAN.instantiate() as Node3D
	actor.generate_on_ready = false
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	if side < 0.0: actor.rotation.y = PI
	root.add_child(actor)
	var enemy := (RAT if low_target else ENEMY).instantiate() as Node3D
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.faction_id = 1-actor.faction_id
	root.add_child(enemy)
	await process_frame
	await physics_frame
	for fixture: Node3D in [actor,enemy]:
		for body: RigidBody3D in fixture.find_children("*","RigidBody3D",true,false):
			body.freeze = true
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
	var torso := actor.get_combat_anchor() as PhysicalBodyPart3D
	var target := enemy.get_node("GeneratedParts/Torso" if low_target else "Torso") as PhysicalBodyPart3D
	var ai := actor.get_node("NPCStateMachine3D")
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	var weapon := actor.get_node("InventoryController3D").get_equipped_item() as SampleWeapon3D
	ai.behavior = ai.behavior.duplicate(true)
	ai.behavior.auto_find_enemies = false
	ai._performance_mode = ai._performance_mode.duplicate()
	ai._enemy = enemy
	ai._target = target
	var attack: NPCAttackData = ai.behavior.attacks[0]
	for part: RigidBody3D in enemy.find_children("*","RigidBody3D",true,false):
		if part is PhysicalBodyPart3D:
			part.max_hp = 1000000.0
			part.current_hp = part.max_hp
			part.armor = 0.0
	enemy.position.x = side*24.0
	enemy.position.z += torso.global_position.z-target.global_position.z
	for iteration: int in 8:
		await physics_frame
		var reach := swing.get_npc_attack_range_diagnostics(&"PrimaryArm",target)
		enemy.position.x += torso.global_position.x+side*float(reach.maximum)*1.15-target.global_position.x
	await physics_frame
	await physics_frame
	var profile := swing.get_npc_attack_range_diagnostics(&"PrimaryArm",target)
	var distance := absf(target.global_position.x-torso.global_position.x)
	var prediction := swing.predict_npc_attack(&"PrimaryArm",target,attack.charge_time)
	print("SPEAR_EARLY_RANGE side=",side," low_target=",low_target," distance=",distance," profile=",profile," prediction=",prediction)
	check(distance > profile.maximum and distance < profile.charge_maximum,"Charge begins outside physical strike reach")
	check(is_equal_approx(float(profile.charge_maximum)/float(profile.maximum),1.35),"Spear charge envelope scales with actual weapon geometry")
	check(prediction.hit and prediction.reason == &"predicted_charge_approach_contact","Predict a valid thrust after approaching, not an enlarged hitbox")
	target.linear_velocity = Vector3(-side*5.0,0,0)
	check(swing.predict_npc_attack(&"PrimaryArm",target,attack.charge_time).hit,"An approaching target can also trigger early charge")
	target.linear_velocity = Vector3.ZERO
	var wall := StaticBody3D.new()
	var obstacle := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,100,10)
	obstacle.shape = box
	wall.add_child(obstacle)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	var blocked := swing.predict_npc_attack(&"PrimaryArm",target,attack.charge_time)
	check(not blocked.hit and blocked.reason == &"terrain_blocks_thrust","Earlier charging still respects terrain collision prediction")
	wall.queue_free()
	await process_frame
	await physics_frame
	check(ai._try_attack(distance),"The real Human AI selector starts an early charge")
	check(swing.allows_npc_attack_movement() and ai._attack_allows_movement(),"Only preparation opts into attack movement")
	for optimized: bool in [false,true]:
		ai._performance_mode.enabled = optimized
		ai._combat_decision_elapsed = 1.0
		ai._update_combat(1.0/60.0)
		await physics_frame
		await physics_frame
		var movement: Vector3 = ai.get_movement_direction()
		check(movement.x*side > 0.0,"Approach continues during early charge, including performance mode")
		check(ai.get_npc_movement_speed_scale(5.0) > 0.0,"The movement controller also receives a nonzero speed while charging")
	var hp := target.current_hp
	for tick: int in 40:
		swing._physics_process(1.0/60.0)
		await physics_frame
	check(swing.get_group_state(0) == swing.SwingState.CHARGING and not weapon.swing_damage_active,"A finished charge waits outside real strike reach")
	check(weapon.apply_contact_damage(target,100.0) == 0.0 and target.current_hp == hp,"Charging contact never damages or cancels the charge")
	check(swing.is_npc_attack_active(),"Contact does not cancel the active charge")
	# A stationary target is reached by walking; do not require the enemy to approach us.
	for iteration: int in 8:
		await physics_frame
		var preferred: float = ai._preferred_attack_distance(attack)
		actor.position.x += target.global_position.x-side*preferred-torso.global_position.x
	await physics_frame
	await physics_frame
	swing.npc_wait_for_aim = false
	swing._physics_process(1.0/60.0)
	check(weapon.swing_damage_active and swing.get_group_state(0) == swing.SwingState.SWINGING,"Release only after entering real strike reach")
	check(not swing.allows_npc_attack_movement() and ai.get_movement_direction().is_zero_approx(),"Released thrust stops charge approach movement")
	check(ai.get_npc_movement_speed_scale(5.0) == 0.0,"Released thrust also clears the humanoid movement speed")
	ai._cancel_attack()
	check(not weapon.swing_damage_active and not swing.allows_npc_attack_movement(),"Cancellation restores movement and damage ownership")
	# A target that stays out of reach cannot leave the actor charging forever or trigger a distant empty strike.
	for iteration: int in 8:
		await physics_frame
		var reach := swing.get_npc_attack_range_diagnostics(&"PrimaryArm",target)
		enemy.position.x += torso.global_position.x+side*float(reach.maximum)*1.15-target.global_position.x
	await physics_frame
	check(swing.try_start_npc_attack(&"PrimaryArm",target,attack.charge_time),"A second charge can start cleanly")
	var released := false
	for tick: int in ceili((attack.charge_time+swing.npc_maximum_charge_approach_wait+0.1)*60.0):
		swing._physics_process(1.0/60.0)
		released = released or weapon.swing_damage_active
		await physics_frame
	check(not released and not swing.is_npc_attack_active() and swing._npc_aim_release_reason == &"approach_timeout","Blocked approach cancels safely instead of firing out of range")
	check(swing._npc_range_wait_elapsed == 0.0,"Cancellation clears the approach timer")
	# An unlimited perception radius must not bypass this attack's finite charge-start range.
	enemy.position.x += side*100.0
	await physics_frame
	await physics_frame
	check(not ai._attack_in_range(attack,target,absf(target.global_position.x-torso.global_position.x)),"Outside the extended envelope remains out of range")
	actor.queue_free()
	enemy.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var audio := root.get_node("CombatAudio")
	audio.settings = audio.settings.duplicate()
	audio.settings.enabled = false
	check(WeaponArmAttackPreset.new().npc_charge_range_multiplier == 1.0,"Other weapon presets keep their existing charge-start range")
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-200,0,-100),Vector3(200,0,-100),Vector3(200,0,100),Vector3(-200,0,100)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	root.add_child(region)
	await physics_frame
	await physics_frame
	await verify(1.0)
	await verify(-1.0)
	low_target = true
	await verify(1.0)
	await verify(-1.0)
	region.queue_free()
	await process_frame
	print("SPEAR_EARLY_CHARGE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
