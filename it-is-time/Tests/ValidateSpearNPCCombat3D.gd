extends SceneTree

const HUMAN = preload("res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Spear1_NPC.tscn")
const ENEMY = preload("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn")
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func verify(side: float) -> void:
	var actor := HUMAN.instantiate() as Node3D
	actor.generate_on_ready = false
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	if side < 0.0: actor.rotation.y = PI
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false): body.freeze = true
	root.add_child(actor)
	var enemy := ENEMY.instantiate() as Node3D
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.faction_id = 1-actor.faction_id
	for body: RigidBody3D in enemy.find_children("*","RigidBody3D",true,false): body.freeze = true
	root.add_child(enemy)
	await process_frame
	await physics_frame
	# Generated characters activate their parts in _ready, so freeze after activation.
	for fixture: Node3D in [actor,enemy]:
		for body: RigidBody3D in fixture.find_children("*","RigidBody3D",true,false):
			body.freeze = true
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
	var torso := actor.get_node("GeneratedParts/Torso") as PhysicalBodyPart3D
	var target := enemy.get_node("Torso") as PhysicalBodyPart3D
	var ai := actor.get_node("NPCStateMachine3D")
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	var inventory := actor.get_node("InventoryController3D")
	var weapon := inventory.get_equipped_item() as SampleWeapon3D
	for part: RigidBody3D in enemy.find_children("*","RigidBody3D",true,false):
		if not part is PhysicalBodyPart3D: continue
		part.max_hp = 1000000.0
		part.current_hp = part.max_hp
		part.armor = 0.0
	check(weapon != null and weapon.idle_grip_pose.use_line_angle, "NPC initial Spear1 loads the 30 degree idle preset")
	ai._enemy = enemy
	ai._target = target
	var attack: NPCAttackData = ai.behavior.attacks[0]
	# Keep the enemy's authored standing height: it is shorter than the generated Human.
	enemy.position.x = side*16.0
	enemy.position.z += torso.global_position.z-target.global_position.z
	for iteration: int in 8:
		await physics_frame
		var preferred: float = ai._preferred_attack_distance(attack)
		enemy.position.x += torso.global_position.x+side*preferred-target.global_position.x
	await physics_frame
	await physics_frame
	var profile := swing.get_npc_attack_range_diagnostics(&"PrimaryArm",target)
	var prediction := swing.predict_npc_attack(&"PrimaryArm",target,attack.charge_time,attack.prediction_samples,attack.prediction_margin)
	print("SPEAR_NPC_RANGE side=",side," torso=",torso.global_position," target=",target.global_position," profile=",profile," preferred=",ai._preferred_attack_distance(attack)," collision_envelope=",ai._minimum_character_standoff()," prediction=",prediction)
	check(swing.uses_dynamic_npc_attack_range(&"PrimaryArm"), "Spear uses actual thrust geometry instead of the authored generic radius")
	check(ai._preferred_attack_distance(attack)>=ai._minimum_body_standoff(), "Spear spacing still preserves Torso clearance")
	check(prediction.hit, "Spear must predict a hit against the shorter target at its own preferred distance")
	check(ai._try_attack(absf(target.global_position.x-torso.global_position.x)), "Human AI must enter the Spear attack through prediction and facing gates")
	var state: Dictionary = swing._states[0].members[0]
	for link: Dictionary in state.pose_chain:
		link.body.freeze = false
		link.body.gravity_scale = 0.0
	for body: RigidBody3D in inventory._multi_grips._bindings[0].chain.bodies:
		body.freeze = false
		body.gravity_scale = 0.0
	# Damage is read by the victim's integration callback, which frozen bodies do not run.
	target.freeze = false
	target.process_mode = Node.PROCESS_MODE_ALWAYS
	target.gravity_scale = 0.0
	target.mass = 1000.0
	target.sleeping = false
	var saw_damage_window := false
	var actual_hit := false
	var weapon_contact := false
	var contact_sources := {}
	for tick: int in 240:
		swing._physics_process(1.0/60.0)
		await physics_frame
		saw_damage_window = saw_damage_window or weapon.swing_damage_active
		var direct := PhysicsServer3D.body_get_direct_state(target.get_rid())
		if direct != null:
			for index: int in direct.get_contact_count():
				var collider := direct.get_contact_collider_object(index)
				var source := SampleWeapon3D.from_contact(collider,direct.get_contact_collider_shape(index))
				weapon_contact = weapon_contact or source == weapon
				var label := str(collider.name) if is_instance_valid(collider) else "none"
				label += ":"+(str(source.name) if source != null else "unarmed")
				contact_sources[label] = maxf(float(contact_sources.get(label,0.0)),direct.get_contact_impulse(index).length())
		for collision: CollisionShape3D in swing.HIT_PREDICTION.shapes(state.effector):
			if not collision.has_meta(&"equipped_item") or collision.get_meta(&"equipped_item") != weapon: continue
			if weapon.swing_damage_active:
				actual_hit = actual_hit or swing.HIT_PREDICTION.target_hit(actor.get_world_3d().direct_space_state,collision.shape,collision.global_transform,target,0.0,0.0)
		if saw_damage_window and not swing.is_npc_attack_active(): break
	var damage := 0.0
	for part: RigidBody3D in enemy.find_children("*","RigidBody3D",true,false):
		if part is PhysicalBodyPart3D: damage += part.max_hp-part.current_hp
	print("SPEAR_NPC_EXECUTION side=",side," sequence=",weapon.swing_sequence," damage_window_seen=",saw_damage_window," any_part_damage=",damage," actual_hit=",actual_hit," contacts=",contact_sources," release_reason=",swing._npc_aim_release_reason)
	check(saw_damage_window and weapon.swing_sequence>0, "NPC must complete charge and open a real weapon damage window")
	# HP also depends on solver impulse and global armor rules; this checks actual attack geometry.
	check(actual_hit, "The physically driven Spear must overlap the shorter target Torso during its damage window")
	check(weapon_contact,"The target must also receive solver contact reports sourced from this Spear")
	swing.cancel_npc_attack()
	actor.queue_free()
	enemy.queue_free()
	await process_frame

func run() -> void:
	await verify(1.0)
	await verify(-1.0)
	print("SPEAR_NPC_COMBAT_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
