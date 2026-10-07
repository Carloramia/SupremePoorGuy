extends "res://Tests/ValidateNPCCombat3D.gd"

func run() -> void:
	var npc := actor(1, Vector3.ZERO)
	var ally := actor(1, Vector3(1,0,0))
	var enemy := actor(2, Vector3(10000,500,0))
	var receiver := AttackProbe.new()
	receiver.name = "AttackProbe"
	npc.add_child(receiver)
	var data = BEHAVIOR.new()
	data.detection_radius = 1.0
	data.disengage_radius = 2.0
	data.maximum_vertical_difference = 1.0
	data.require_line_of_sight = true
	var attack = ATTACK.new()
	attack.receiver_path = ^"AttackProbe"
	attack.maximum_range = 4.0
	data.attacks.append(attack)
	var ai := FSM.instantiate()
	ai.behavior = data
	ai.navigation_origin_path = ^""
	npc.add_child(ai)
	ai.set_physics_process(false)
	await physics_frame
	ai._update_combat(0.1)
	check(ai._enemy == enemy, "A distant high-altitude enemy must be perceived despite a closer ally")
	check(receiver.starts == 0, "Awareness must not bypass the attack's range or height limits")
	enemy.position.x = 20000
	ai._update_combat(0.1)
	check(ai._enemy == enemy, "Moving beyond the old disengage radius must not lose the enemy")
	# Independent 3D worlds must not share perception despite using the same groups.
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var external := Node3D.new()
	external.set_script(CHARACTER)
	external.faction_id = 3
	viewport.add_child(external)
	check(not ai._is_enemy(external), "NPCs in an independent world must not become targets")
	enemy.faction_id = 1
	ai._update_combat(0.1)
	check(ai._enemy == null and not receiver.active, "Faction rules must still exclude allies")
	enemy.faction_id = 2
	ai._scan_elapsed = 0.0
	ai._update_combat(0.1)
	check(ai._enemy == enemy, "The enemy must be reacquired at arbitrary distance")
	enemy.queue_free()
	await process_frame
	ai._update_combat(0.1)
	check(ai._enemy == null, "Deleted targets must be released")
	check(ai._enemy != ally, "Allies must never be attack targets")
	print("NPC_SCENE_AWARENESS_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
