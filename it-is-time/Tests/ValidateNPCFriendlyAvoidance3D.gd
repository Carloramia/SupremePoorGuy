extends "res://Tests/ValidateNPCCombat3D.gd"

func brain_for(node: Node3D) -> Node:
	var brain := FSM.instantiate()
	brain.auto_find_target_by_group = false
	brain.navigation_origin_path = ^".."
	node.add_child(brain)
	brain.set_physics_process(false)
	brain.humanoid_xz_positioning = true
	return brain

func run() -> void:
	var own := actor(1,Vector3.ZERO)
	var ally := actor(1,Vector3(1,0,0))
	var enemy := actor(2,Vector3(10,0,0))
	var brain := brain_for(own)
	var peer := brain_for(ally)
	brain._enemy = enemy
	peer._enemy = enemy
	brain._target = enemy
	peer._target = enemy
	brain.current_state = brain.State.MOVE_TO_TARGET
	peer.current_state = peer.State.MOVE_TO_TARGET
	brain._update_friendly_neighbors(0.2)
	peer._update_friendly_neighbors(0.2)
	check(brain._friendly_neighbors.size() == 1,"Enemy must never be treated as a friendly obstacle")
	check(brain._is_enemy(enemy) and not brain._is_enemy(ally),"Avoidance must preserve faction perception")
	var steered: Vector3 = brain._apply_friendly_avoidance(Vector3.RIGHT)
	check(steered.x > 0.0 and absf(steered.z) > 0.1 and is_equal_approx(steered.length(),1.0),"A friend ahead must cause a bounded sidestep while preserving progress")
	var lane: float = peer._friendly_approach_offset
	check(not is_equal_approx(brain._friendly_approach_offset,lane),"Same-side allies targeting the same enemy must have different approach lanes")
	peer._update_friendly_neighbors(0.2)
	check(is_equal_approx(peer._friendly_approach_offset,lane),"Unchanged allies must retain their lane")
	var attack := ATTACK.new()
	attack.prediction_enabled = true
	attack.preferred_distance = 4.0
	var attacks: Array[ATTACK] = [attack]
	peer._plan_attack_distance(9.0,attacks)
	check(is_equal_approx(peer._requested_target_position.z,lane),"Lane selection must participate in combat destination planning")
	check(peer.get_npc_body_facing_direction() == Vector3.RIGHT,"Lateral avoidance must not change left/right facing")
	brain.current_state = brain.State.ATTACK
	brain._friendly_approach_offset = 0.8
	brain._update_friendly_neighbors(0.2)
	check(is_equal_approx(brain._friendly_approach_offset,0.8),"Approach lane must remain frozen during an attack")
	check(brain._apply_friendly_avoidance(Vector3.RIGHT) == Vector3.RIGHT,"Charging and follow-through must not receive crowd steering")
	check(brain._friendly_steering == Vector3.ZERO,"Suppressed steering must be cleared in diagnostics")
	brain.current_state = brain.State.MOVE_TO_TARGET
	brain.friendly_avoidance_enabled = false
	brain._update_friendly_neighbors(0.2)
	check(brain._friendly_neighbors.is_empty() and brain._apply_friendly_avoidance(Vector3.RIGHT) == Vector3.RIGHT,"Disabling avoidance must restore ordinary navigation")
	brain.friendly_avoidance_enabled = true
	ally.position.y = 30.0
	brain._update_friendly_neighbors(0.2)
	check(brain._friendly_neighbors.is_empty(),"Airborne allies far above must not obstruct ground walking")
	ally.position = Vector3(1,0,0)
	ally.faction_id = 2
	brain._update_friendly_neighbors(0.2)
	check(brain._friendly_neighbors.is_empty(),"Changing faction must remove a cached friendly obstacle")
	print("NPC_FRIENDLY_AVOIDANCE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
