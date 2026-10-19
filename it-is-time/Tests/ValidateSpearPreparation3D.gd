extends SceneTree

const HUMAN = preload("res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Spear1_NPC.tscn")
var failed := false
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	print("SPEAR_PREPARATION_CHECK ",value," ",message)
	if not value: failed = true; push_error(message)

func sample(side: float, gentle: bool) -> Dictionary:
	var actor := HUMAN.instantiate() as Node3D
	actor.generate_on_ready = false
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	if side < 0.0: actor.rotation.y = PI
	root.add_child(actor)
	await process_frame
	await physics_frame
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false):
		body.freeze = true
		body.gravity_scale = 0.0
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	var inventory := actor.get_node("InventoryController3D")
	inventory.suspend_idle_grip_pose()
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	var weapon := inventory.get_equipped_item() as SampleWeapon3D
	var preset := weapon.get_arm_attack_preset().duplicate() as WeaponArmAttackPreset
	weapon.arm_attack_preset_override = preset
	if not gentle:
		preset.preparation_speed_ratio = 1.0
		preset.preparation_force_ratio = 1.0
	swing.refresh_weapon_presets()
	var state: Dictionary = swing._states[0].members[0]
	for link: Dictionary in state.pose_chain: link.body.freeze = false
	for binding: Dictionary in inventory._multi_grips._bindings:
		for body: RigidBody3D in binding.chain.bodies: body.freeze = false
	var victim := PhysicalBodyPart3D.new()
	victim.name = "DamageWindowVictim"
	victim.freeze = true
	victim.position = Vector3(200,200,200)
	victim.damage_number_scene = null
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	victim.add_child(sprite)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	victim.add_child(collision)
	root.add_child(victim)
	victim.max_hp = 100000.0
	victim.current_hp = victim.max_hp
	victim.armor = 0.0
	var hp := victim.current_hp
	check(weapon.apply_contact_damage(victim,100.0) == 0.0 and victim.current_hp == hp,"Idle Spear has no passive damage")
	check(swing.begin_charge(0),"Charge begins")
	var maximum_speed := 0.0
	var maximum_force := 0.0
	var maximum_torque := 0.0
	var protected := true
	for tick: int in 18:
		swing._process_member(0,state,true,1.0/60.0)
		inventory._multi_grips.update(1.0/60.0)
		var data: Dictionary = state.hand_drive_diagnostics
		maximum_force = maxf(maximum_force,data.force_length)
		maximum_torque = maxf(maximum_torque,data.torque_length)
		protected = protected and not weapon.swing_damage_active and weapon.apply_contact_damage(victim,100.0) == 0.0
		await physics_frame
		maximum_speed = maxf(maximum_speed,swing.WEAPON_POSE._point_velocity(state.effector,state.effector.to_global(state.pose_chain[-1].proximal)).length())
	check(protected and victim.current_hp == hp,"Every charging contact is harmless, even at high impulse")
	check(maximum_force <= preset.hand_maximum_force*preset.preparation_force_ratio+0.001,"Charge force cap applies after mass scaling")
	check(maximum_torque <= preset.maximum_pose_torque*preset.preparation_force_ratio+0.001,"Charge torque cap applies after inertia scaling")
	check(state.hand_drive_diagnostics.preparing and is_equal_approx(state.hand_drive_diagnostics.speed_ratio,preset.preparation_speed_ratio),"Controller selects preparation response settings")
	check(swing.release_charge(0) and weapon.swing_damage_active,"Completing charge opens the attack damage window")
	check(weapon.apply_contact_damage(victim,100.0) > 0.0 and victim.current_hp < hp,"Released attack can damage the previously protected target")
	check(weapon.apply_contact_damage(victim,100.0) == 0.0,"Released attack still deduplicates each Part")
	swing._process_member(0,state,false,1.0/60.0)
	check(not state.hand_drive_diagnostics.preparing and state.hand_drive_diagnostics.force_ratio == 1.0 and state.hand_drive_diagnostics.speed_ratio == 1.0,"Thrust restores its original drive settings")
	swing.cancel_player_actions()
	hp = victim.current_hp
	check(not weapon.swing_damage_active and weapon.apply_contact_damage(victim,100.0) == 0.0 and victim.current_hp == hp,"Cancellation closes all Spear damage")
	check(swing.begin_charge(0) and swing.release_charge(0) and not weapon.swing_damage_active,"Too-short charge never opens damage")
	var merged := false
	for shape: CollisionShape3D in swing.HIT_PREDICTION.shapes(state.effector):
		if shape.has_meta(&"equipped_item") and shape.get_meta(&"equipped_item") == weapon: merged = merged or not shape.disabled
	check(merged,"Damage gating preserves the weapon's physical collision shape")
	var result := {"side":side,"gentle":gentle,"peak_wrist_speed":maximum_speed,"peak_force":maximum_force,"peak_torque":maximum_torque}
	print("SPEAR_PREPARATION_SAMPLE ",JSON.stringify(result))
	actor.queue_free()
	victim.queue_free()
	await process_frame
	await process_frame
	return result

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var audio := root.get_node("CombatAudio")
	audio.settings = audio.settings.duplicate()
	audio.settings.enabled = false
	for side: float in [1.0,-1.0]:
		var original := await sample(side,false)
		var gentle := await sample(side,true)
		check(gentle.peak_wrist_speed < original.peak_wrist_speed,"Gentle preparation lowers measured physical wrist speed")
		check(gentle.peak_force < original.peak_force and gentle.peak_torque < original.peak_torque,"Gentle preparation lowers measured force and torque")
	var ordinary := SampleWeapon3D.new()
	ordinary.weapon_tags = [SampleWeapon3D.WeaponTag.Sword]
	ordinary.primary_attack_tag = SampleWeapon3D.WeaponTag.Sword
	check(not (ordinary.get_arm_attack_preset() as WeaponArmAttackPreset).damage_only_during_swing,"Other weapon presets retain their passive damage policy")
	ordinary.free()
	print("SPEAR_PREPARATION_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
