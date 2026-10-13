extends SceneTree
const HITBOX = preload("res://Scripts/Items/WolfAttackHitbox3D.gd")
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func run() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	var enemy = load("res://Scenes/Creatures/Characters/Generate_Wolf.tscn").instantiate()
	enemy.generate_on_ready = false
	enemy.faction_id = 2
	root.add_child(enemy)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	for character: Node in [actor,enemy]:
		for part: RigidBody3D in character._get_physical_body_parts():
			part.freeze = true
			part.max_hp = 100000.0
			part.current_hp = 100000.0
	for part: RigidBody3D in enemy._get_physical_body_parts(): part.mass = 0.01
	var target: PhysicalBodyPart3D = enemy.get_node("GeneratedParts/Torso")
	target.armor = 0.0
	var movement = enemy.get_node("GeneratedLegStepMovementController3D")
	var attacks = enemy.get_node("WolfAttackController3D")
	var original_mode: int = movement.process_mode
	var weapon := HITBOX.new()
	weapon.setup(actor.get_node("GeneratedParts/ForeLeg_1"),actor,Vector3.ONE,Vector3.ZERO,1.0,0.15)
	root.add_child(weapon)
	check(weapon.apply_contact_damage(target,0.0) == 0.0 and not enemy.is_temporarily_ragdolled(),"Zero damage cannot ragdoll")
	target.armor = 1000000000.0
	check(weapon.apply_contact_damage(target,10.0) == 0.0 and not enemy.is_temporarily_ragdolled(),"Armor absorbing damage cannot ragdoll")
	target.armor = 0.0
	check(weapon.apply_contact_damage(target,100.0) > 0.0,"Claw deals effective damage")
	check(enemy.is_temporarily_ragdolled() and movement.process_mode == Node.PROCESS_MODE_DISABLED and attacks.process_mode == Node.PROCESS_MODE_DISABLED,"Lighter enemy loses movement and attack control")
	var time_left: float = enemy._hit_ragdoll_timer.time_left
	check(weapon.apply_contact_damage(target,100.0) == 0.0 and enemy._hit_ragdoll_timer.time_left == time_left,"Duplicate Part hit cannot refresh ragdoll")
	weapon.dispose()
	await create_timer(0.25).timeout
	check(not enemy.is_temporarily_ragdolled() and movement.process_mode == original_mode,"Timer restores control after the hitbox is deleted")
	for key: String in ["ForeLeg_2","LowerJaw"]:
		weapon = HITBOX.new()
		weapon.setup(actor.get_node("GeneratedParts/"+key),actor,Vector3.ONE,Vector3.ZERO,1.0,0.15)
		root.add_child(weapon)
		check(weapon.apply_contact_damage(target,100.0) > 0.0 and enemy.is_temporarily_ragdolled(),"Both other claw and bite use shared ragdoll settlement")
		weapon.dispose()
		await create_timer(0.25).timeout
	var other_source := Node.new()
	root.add_child(other_source)
	enemy.apply_timed_hit_ragdoll(0.1)
	enemy.set_temporary_ragdoll(other_source,true)
	enemy.apply_timed_hit_ragdoll(0.3)
	await create_timer(0.18).timeout
	check(enemy._hit_ragdoll_timer.time_left > 0.0,"Repeated valid effects extend the timeout")
	await create_timer(0.2).timeout
	check(enemy.is_temporarily_ragdolled(),"Expiration cannot cancel another ragdoll source")
	enemy.set_temporary_ragdoll(other_source,false)
	check(not enemy.is_temporarily_ragdolled() and movement.process_mode == original_mode,"Last source restores original mode")
	other_source.free()
	for part: RigidBody3D in enemy._get_physical_body_parts(): part.mass = 100.0
	weapon = HITBOX.new()
	weapon.setup(actor.get_node("GeneratedParts/LowerJaw"),actor,Vector3.ONE,Vector3.ZERO,1.0,0.1)
	root.add_child(weapon)
	check(weapon.apply_contact_damage(target,100.0) > 0.0 and not enemy.is_temporarily_ragdolled(),"Heavier enemy takes damage without ragdoll")
	weapon.end_damage_swing(); weapon.begin_damage_swing()
	enemy.faction_id = actor.faction_id
	check(weapon.apply_contact_damage(target,100.0) == 0.0 and not enemy.is_temporarily_ragdolled(),"Friendly contacts cannot ragdoll")
	weapon.dispose()
	enemy.apply_timed_hit_ragdoll(0.1)
	enemy.get_node("CharacterDamageController3D")._character_disabled = true
	await create_timer(0.2).timeout
	check(not enemy.is_temporarily_ragdolled() and movement.process_mode == Node.PROCESS_MODE_DISABLED,"Expiry cannot revive a dead character")
	var bite = actor.get_node("WolfAttackController3D/Bite")
	check(not bite.has_method("_begin_hold") and not bite.has_method("_on_hit"),"Bite no longer creates target binding constraints")
	actor.free(); enemy.free()
	print("WOLF_HIT_RAGDOLL ","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
