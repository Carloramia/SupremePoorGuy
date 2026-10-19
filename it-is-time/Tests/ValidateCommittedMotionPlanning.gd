extends SceneTree

const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const BEHAVIOR = preload("res://Scripts/Creatures/NPCBehaviorData.gd")
const ATTACK = preload("res://Scripts/Creatures/NPCAttackData.gd")
var mode: Resource = preload("res://Resources/Settings/PerformanceOptimization.tres")
var failed := false
var checks := 0

class PlanningProbe extends "res://Scripts/Creatures/NPCStateMachine3D.gd":
	var requested_direction := Vector3.RIGHT
	var direction_queries := 0
	func _calculate_movement_direction() -> Vector3:
		direction_queries += 1
		return requested_direction
	func _sync_navigation_origin() -> void: pass

class AttackProbe extends Node:
	var active := true
	func is_npc_attack_active() -> bool: return active
	func cancel_npc_attack() -> void: active = false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func actor(faction: int, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.set_script(CHARACTER)
	node.require_head_and_torso_connectivity = false
	node.faction_id = faction
	root.add_child(node)
	node.global_position = at
	return node

func planner(owner: Node3D, slot: int) -> PlanningProbe:
	var ai := PlanningProbe.new()
	var agent := NavigationAgent3D.new()
	agent.name = "NavigationAgent3D"
	ai.add_child(agent)
	ai.behavior = BEHAVIOR.new()
	ai.behavior.require_line_of_sight = false
	ai.behavior.target_switch_cooldown = 0.0
	ai.behavior.scan_interval = 0.05
	ai.behavior.preferred_distance = 4.0
	ai.generated_x_axis_facing = true
	ai.navigation_origin_path = ^".."
	ai.friendly_avoidance_enabled = false
	owner.add_child(ai)
	ai.set_physics_process(false)
	ai._planning_slot = slot
	ai.set_performance_tracking_enabled(true)
	return ai

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	mode.enabled = true
	mode.ai_decision_interval = 0.1
	mode.stagger_ai_planning = true
	var enemy := actor(2,Vector3(50,0,0))
	var owners: Array[Node3D] = []
	var machines: Array[PlanningProbe] = []
	for i in 12:
		owners.append(actor(1,Vector3(0,0,i*0.01)))
		machines.append(planner(owners[-1],i))
	var peak_decisions := 0
	for tick in 60:
		var decisions := 0
		for ai in machines:
			var previous := ai._planning_revision
			ai._update_combat(1.0/60.0)
			decisions += ai._planning_revision-previous
		peak_decisions = maxi(peak_decisions,decisions)
	check(peak_decisions==2,"Twelve NPCs must distribute their ten-Hz plans across six physics frames")
	for ai in machines:
		check(ai._planning_revision==10,"Each NPC must plan ten times per second")
		check(ai.direction_queries==10,"Direction/avoidance must be evaluated only once per plan")
	var ai := machines[0]
	ai._planning_remaining = 0.1
	var revision := ai._planning_revision
	var goal := ai._requested_target_position
	var facing := ai.get_generated_facing_direction(0.0)
	ai.requested_direction = Vector3.LEFT
	enemy.global_position.x = -50.0
	var closer := actor(2,Vector3(10,0,0))
	for tick in 5:
		ai._update_combat(1.0/60.0)
		check(ai._enemy==enemy and ai._requested_target_position==goal,"Enemy identity and navigation goal must stay committed between plans")
		check(ai.get_movement_direction()==Vector3.RIGHT,"Direction must stay committed despite changing live navigation input")
		check(ai.get_generated_facing_direction(0.0)==facing,"Facing intent must stay committed between plans")
	ai._update_combat(1.0/60.0)
	check(ai._planning_revision==revision+1 and ai._enemy==closer,"Next scheduled decision may switch to the closer enemy")
	check(ai.get_movement_direction()==Vector3.LEFT,"The next plan must accept the new direction")
	var receiver := AttackProbe.new()
	owners[0].add_child(receiver)
	var attack := ATTACK.new()
	attack.maximum_duration = 10.0
	ai._active_attack = attack
	ai._attack_receiver = receiver
	ai._target = closer
	ai._cooldowns[attack] = 0.5
	ai.change_state(ai.State.ATTACK)
	goal = ai._requested_target_position
	for tick in 12: ai._update_combat(1.0/60.0)
	check(is_equal_approx(ai._attack_elapsed,0.2),"Attack execution must advance on every physical tick")
	check(is_equal_approx(ai._cooldowns[attack],0.3),"Cooldowns must not slow down with planning")
	check(ai._target==closer and ai._requested_target_position==goal,"A committed stationary attack must retain its target and goal across planning cycles")
	closer.free()
	ai._planning_remaining = 0.1
	ai._update_combat(1.0/60.0)
	check(not receiver.active and ai.get_movement_direction().is_zero_approx(),"A freed victim must stop attacks and movement immediately without waiting for planning")
	check(not ai._motion_plan_ready,"Death/removal must invalidate the cached plan")
	ai.move_to_position(Vector3(20,0,3))
	check(ai._manual_command and not ai._motion_plan_ready and ai._requested_target_position==Vector3(20,0,3),"An explicit command must override the autonomous plan immediately")
	# Turning optimizations off must retain full-rate control for comparison.
	mode.enabled = false
	var legacy := machines[1]
	var old_revision := legacy._planning_revision
	for tick in 12: legacy._update_combat(1.0/60.0)
	check(legacy._planning_revision-old_revision==12,"Performance switch must restore per-frame planning")
	mode.enabled = true
	var snake_ai: Node3D = load("res://Scripts/Creatures/SnakeNPCStateMachine3D.gd").new()
	var snake_agent := NavigationAgent3D.new()
	snake_agent.name = "NavigationAgent3D"
	snake_ai.add_child(snake_agent)
	snake_ai.behavior = BEHAVIOR.new()
	owners[0].add_child(snake_ai)
	snake_ai.set_physics_process(false)
	var snake_receiver := AttackProbe.new()
	owners[0].add_child(snake_receiver)
	snake_ai._enemy = enemy
	snake_ai._target = enemy
	snake_ai._active_attack = attack
	snake_ai._attack_receiver = snake_receiver
	snake_ai._cooldowns[attack] = 0.5
	snake_ai.current_state = snake_ai.State.ATTACK
	for tick in 12: snake_ai._update_combat(1.0/60.0)
	check(is_equal_approx(snake_ai._attack_elapsed,0.2) and is_equal_approx(snake_ai._planning_age,0.2),"Snake attack recovery must retain full-rate execution and planning telemetry")
	check(is_equal_approx(snake_ai._cooldowns[attack],0.3),"Snake's recovery override must not freeze shared cooldown timers")
	mode.stagger_ai_planning = false
	check(legacy._planning_due(0.0),"Disabling staggering must take effect immediately")
	mode.stagger_ai_planning = true
	check(not legacy._planning_due(0.0),"Re-enabling staggering must reassign the next planning slot")
	for owner in owners: owner.free()
	enemy.free()
	await process_frame
	print("COMMITTED_MOTION_PLANNING_", "FAILED" if failed else "PASSED", " checks=",checks," peak_plans_per_frame=",peak_decisions)
	quit(1 if failed else 0)
