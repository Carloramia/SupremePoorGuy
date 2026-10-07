extends "res://Tests/ValidateNPCCombat3D.gd"

const TORSO = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn")
class RangeProbe extends AttackProbe:
	var available := true
	func has_npc_attack(_id: StringName) -> bool: return available

func run() -> void:
	var npc := actor(1,Vector3.ZERO)
	var enemy := actor(2,Vector3(20,0,0))
	var far := TORSO.instantiate() as RigidBody3D
	far.name = "FarTorso"
	far.freeze = true
	enemy.add_child(far)
	far.global_position = Vector3(9,0,0)
	var near := TORSO.instantiate() as RigidBody3D
	near.name = "NearTorso"
	near.freeze = true
	enemy.add_child(near)
	near.global_position = Vector3(3,0,0)
	var receiver := RangeProbe.new()
	receiver.name = "AttackProbe"
	npc.add_child(receiver)
	var data = BEHAVIOR.new()
	data.require_line_of_sight = false
	data.detection_radius = 5.0
	var attack = ATTACK.new()
	attack.receiver_path = ^"AttackProbe"
	attack.minimum_range = 2.0
	attack.maximum_range = 4.0
	attack.preferred_distance = 3.0
	attack.cooldown = 100.0
	data.attacks.append(attack)
	var ai := FSM.instantiate()
	ai.behavior = data
	ai.navigation_origin_path = ^""
	npc.add_child(ai)
	ai.set_physics_process(false)
	await physics_frame
	ai._update_combat(0.1)
	check(ai._enemy == enemy and ai._target == near and receiver.target == near,"Acquisition and attack aim must use the nearest living Torso rather than root or largest Torso")
	check(ai.current_state == ai.State.ATTACK,"An enemy in an available attack interval must trigger an attack")
	ai._cancel_attack()
	ai.change_state(ai.State.WAITING)
	ai._update_combat(0.1)
	check(ai.current_state == ai.State.WAITING,"Cooldown must retain the preferred distance without chasing")
	near.global_position.x = 1.0
	ai._update_combat(0.1)
	check(ai.current_state == ai.State.MOVE_TO_TARGET and ai._requested_target_position.x < 0.0,"An enemy inside minimum range must cause retreat")
	check(receiver.starts == 1,"Minimum range must prevent another attack")
	near.global_position.x = 10.0
	far.global_position.x = 12.0
	ai._update_combat(0.1)
	check(ai._target == near and is_equal_approx(ai._requested_target_position.x,7.0),"Approach must target a stand-off point, not the enemy center")
	check(ai.get_attack_range_diagnostics().ranges.size() == 1,"Available attacks must generate detection intervals")
	receiver.available = false
	ai._update_combat(0.1)
	check(ai.get_attack_range_diagnostics().ranges.is_empty() and ai.current_state == ai.State.WAITING,"Lost attack limbs must remove attack range and stop range-based pursuit")
	receiver.available = true
	near.is_broken = true
	check(enemy.get_nearest_combat_torso(Vector3.ZERO) == far,"Broken Torso must be excluded from aim selection")
	near.is_broken = false
	near.global_position.x = 6.0
	ai._enemy = null
	ai._scan_elapsed = 0.0
	ai._update_combat(0.1)
	check(ai._enemy == enemy,"Scene-wide perception must ignore the legacy detection radius")
	data.detection_radius = 7.0
	ai._scan_elapsed = 0.0
	ai._update_combat(0.1)
	check(ai._enemy == enemy,"Legacy radius edits must not change scene-wide perception")
	var ranged = ATTACK.new()
	ranged.receiver_path = ^"AttackProbe"
	ranged.action_id = &"ranged"
	ranged.minimum_range = 8.0
	ranged.maximum_range = 10.0
	ranged.preferred_distance = 9.0
	data.attacks.append(ranged)
	near.global_position.x = 7.0
	ai._update_combat(0.1)
	check(ai._distance_attack == ranged and is_equal_approx(ai._requested_target_position.x,-2.0),"A ready long-range attack must retreat to its own preferred range while the short attack cools down")
	near.global_position.x = 9.0
	ai._update_combat(0.5)
	check(receiver.target == near and ai._active_attack == ranged,"Each attack interval must independently trigger its configured action")
	ai._cancel_attack()
	ai.change_state(ai.State.WAITING)
	# Prefer a new enemy already in attack range over a distant pursuit target.
	ai._cooldowns.clear()
	var close_enemy := actor(3,Vector3(3,0,0))
	ai._scan_elapsed = 0.0
	ai._update_combat(0.5)
	check(ai._enemy == close_enemy and receiver.target == close_enemy,"A nearby attackable enemy must take priority over a distant chase target")
	check(is_equal_approx(attack.preferred_distance,3.0),"Distance planning must not mutate shared presets")
	print("NPC_ATTACK_DISTANCE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
