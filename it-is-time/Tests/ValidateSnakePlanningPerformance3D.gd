extends "res://Tests/ValidateSnakeAttacks3D.gd"

class CountedMovement extends "res://Scripts/Creatures/SnakeMovementController3D.gd":
	var anchor_rebuilds := 0
	func _update_anchor() -> Dictionary:
		anchor_rebuilds += 1
		return super._update_anchor()

class MoveCommand extends Node:
	func get_movement_direction() -> Vector3: return Vector3.RIGHT
	func get_generated_facing_direction(_delta: float) -> Vector3: return Vector3.RIGHT

func run() -> void:
	# Authoring TestLevel no longer contains this matchup; keep the regression independent.
	var level := Node3D.new()
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000,1,2000)
	collider.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(collider)
	level.add_child(floor_body)
	var npc := NPC.instantiate()
	enable_attacks(npc)
	npc.generate_on_ready = false
	var movement: Node3D = npc.get_node("SnakeMovementController3D")
	movement.set_script(CountedMovement)
	level.add_child(npc)
	root.add_child(level)
	current_scene = level
	var ai: Node = npc.get_node("NPCStateMachine3D")
	ai.set_physics_process(false)
	var command := MoveCommand.new()
	level.add_child(command)
	movement.command_source = command
	for tick: int in 150: await physics_frame
	movement.command_source = null
	var attack: Node3D = npc.get_node("SnakeBiteAttackController3D")
	var victim := CHARACTER.instantiate()
	victim.faction_id = 2
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso,PhysicalBodyPart3D.BodyPartTag.Head])
	target.freeze = true
	target.position = Vector3(200,2,0)
	victim.add_child(target)
	level.add_child(victim)
	await physics_frame
	check(movement._path_ready,"Regression measures planning during actual S-route locomotion")
	attack.set_control_performance_tracking_enabled(true)
	attack.consume_control_performance_stats()
	var maximum: float = attack.get_npc_attack_maximum_range(attack.ACTION,target)
	check(target.global_position.distance_to(movement.get_control_anchor().global_position)>maximum,"Fixture starts beyond the conservative attack envelope")
	var distance: float = attack.get_npc_attack_preferred_distance(attack.ACTION,target)
	check(distance>0.0 and distance<maximum,"Coarse stand-off approaches inside the envelope instead of stopping outside it")
	check(not attack.predict_npc_attack(attack.ACTION,target,0.0).hit,"Distant prediction is rejected before IK")
	var coarse: Dictionary = attack.consume_control_performance_stats()
	check(coarse.counters.get("coarse_range_estimates",0)==1 and coarse.counters.get("plan_builds",0)==0 and coarse.counters.get("fk_evaluations",0)==0,"Far targets reserve no full-chain solve or collision sweep")
	# Force an exact plan to exercise the expensive path even though the victim is still distant.
	attack._cached_plan = {}
	movement.anchor_rebuilds = 0
	var started := Time.get_ticks_usec()
	var plan: Dictionary = attack._make_plan(target,true)
	var elapsed_ms := (Time.get_ticks_usec()-started)/1000.0
	var anchor_reads: int = movement.anchor_rebuilds
	var exact: Dictionary = attack.consume_control_performance_stats()
	check(anchor_reads<=12,"A complete plan reads the live body frame a bounded number of times")
	check(exact.counters.get("fk_evaluations",1000)<32,"IK updates affected suffixes instead of rebuilding hundreds of full chains")
	check(exact.timings.has("ik_solve") and exact.timings.has("attack_planning"),"Performance tracing separates IK from complete planning")
	check(plan.root_pose.is_equal_approx(movement.get_attack_root_pose(attack._root_rest)),"The plan uses the current physical root, not a stale authored root")
	for i: int in attack._links.size():
		check(plan.strike[i]>=attack._links[i].lower-0.0001 and plan.strike[i]<=attack._links[i].upper+0.0001,"Optimized IK preserves every bend limit")
	attack._make_plan(target,true)
	var reuse: Dictionary = attack.consume_control_performance_stats()
	check(reuse.counters.get("plan_cache_hits",0)==1 and reuse.counters.get("plan_builds",0)==0,"Valid plans retain the existing cache")
	var root_body: RigidBody3D = movement._belly[-1].body
	root_body.global_position += Vector3.RIGHT*attack._chain_length*0.1
	attack._make_plan(target,true)
	var changed: Dictionary = attack.consume_control_performance_stats()
	check(changed.counters.get("plan_builds",0)==1,"A significant physical root shift invalidates the cached plan")
	print("SNAKE_PLANNING_PERF_RESULT plan_ms=",elapsed_ms," anchor_rebuilds=",anchor_reads," fk_evaluations=",exact.counters.get("fk_evaluations")," coarse=",coarse.counters)
	check(npc.generate_creature(),"Regeneration refreshes chain caches")
	ai.set_physics_process(false)
	check(attack._cached_plan.is_empty(),"Regeneration drops the previous plan snapshot")
	level.free()
	await process_frame
	if not failed: print("SNAKE_PLANNING_PERFORMANCE_VALIDATION_PASSED")
	quit(1 if failed else 0)
