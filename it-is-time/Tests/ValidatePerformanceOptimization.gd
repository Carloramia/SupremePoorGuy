extends SceneTree

var _mode: Resource = preload("res://Resources/Settings/PerformanceOptimization.tres")
const MOVEMENT = preload("res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const FSM = preload("res://Scenes/Creatures/Components/NPCStateMachine3D.tscn")
var failed := false

class AttackProbe extends Node:
	var active := true
	func is_npc_attack_active() -> bool: return active
	func cancel_npc_attack() -> void: active = false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	var console := root.get_node("RuntimeConsole")
	check("OFF" in console.execute_command("perfmode off") and not _mode.enabled, "Console must disable the shared optimization switch")
	check("ON" in console.execute_command("perfmode on") and _mode.enabled, "Console must enable the shared optimization switch")
	check("ON" in console.execute_command("perfmode status") and _mode.enabled, "Status must not toggle the mode")
	check("Usage:" in console.execute_command("perfmode invalid") and _mode.enabled, "Invalid commands must not change the mode")
	check(not console.is_control_performance_tracking_enabled(), "Optimization must be independent of diagnostic tracking")
	var host := Node3D.new()
	var controller := MOVEMENT.new()
	host.add_child(controller)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8842
	for count: int in range(1, 9):
		for sample: int in 12:
			var contacts: Array[Vector3] = []
			for index: int in count: contacts.append(Vector3(rng.randf_range(-4.0, 4.0), 0.0, rng.randf_range(-4.0, 4.0)))
			var center := Vector3(rng.randf_range(-2.0, 2.0), 2.0, rng.randf_range(-2.0, 2.0))
			_mode.set(&"enabled", false)
			var original: PackedFloat64Array = controller._solve_stance_support_weights(contacts, center, Vector3.UP)
			_mode.set(&"enabled", true)
			var optimized: PackedFloat64Array = controller._solve_stance_support_weights(contacts, center, Vector3.UP)
			var total := 0.0
			for index: int in count:
				check(absf(original[index] - optimized[index]) < 0.00001, "Support allocation must preserve the original result")
				check(optimized[index] >= 0.0, "Support weights must stay nonnegative")
				total += optimized[index]
			check(absf(total - 1.0) < 0.00001, "Support weights must sum to one")
	controller.slow_gait_data = LegMovementData.new()
	controller._movement_perf.set_enabled(true)
	for query: int in 100: controller._get_gait_data()
	var stats: Dictionary = controller.consume_control_performance_stats()
	check(stats.counters.get(&"gait_resource_validations", 0) == 1, "Validate a shared gait resource once per physics frame")
	await physics_frame
	controller._get_gait_data()
	check(controller.consume_control_performance_stats().counters.get(&"gait_resource_validations", 0) == 1, "Revalidate on the next physics frame")
	var foot := PhysicalBodyPart3D.new()
	host.add_child(foot)
	controller._chains[foot] = {"bodies": [foot], "joints": []}
	controller._movement_batch_active = true
	check(controller._chain_is_intact(foot), "Healthy chains must remain usable inside the movement update")
	controller._movement_batch_active = false
	foot.is_broken = true
	check(not controller._chain_is_intact(foot), "A damage callback after the update must not reuse the healthy chain snapshot")
	host.free()
	var npc := Node3D.new()
	npc.set_script(CHARACTER)
	npc.require_head_and_torso_connectivity = false
	npc.faction_id = 1
	root.add_child(npc)
	var enemy := Node3D.new()
	enemy.set_script(CHARACTER)
	enemy.require_head_and_torso_connectivity = false
	enemy.faction_id = 2
	root.add_child(enemy)
	var ai: Node = FSM.instantiate()
	ai.behavior = load("res://Scripts/Creatures/NPCBehaviorData.gd").new()
	npc.add_child(ai)
	ai.set_physics_process(false)
	var receiver := AttackProbe.new()
	npc.add_child(receiver)
	var attack = load("res://Scripts/Creatures/NPCAttackData.gd").new()
	attack.maximum_duration = 10.0
	ai._enemy = enemy
	ai._target = enemy
	ai._active_attack = attack
	ai._attack_receiver = receiver
	ai._cooldowns[attack] = 0.5
	ai._scan_elapsed = 1.0
	ai.current_state = ai.State.ATTACK
	for tick: int in 8: ai._update_combat(1.0 / 60.0)
	check(is_equal_approx(ai._attack_elapsed, 8.0 / 60.0), "Attack execution must advance every physics tick in optimized mode")
	check(is_equal_approx(ai._cooldowns[attack], 0.5 - 8.0 / 60.0), "Cooldowns must retain real time")
	ai.set_character_control_enabled(false)
	check(not receiver.active and ai.get_movement_direction().is_zero_approx(), "Character disable must cancel cached movement/attacks immediately")
	npc.free()
	enemy.free()
	_mode.set(&"enabled", true)
	await process_frame
	if not failed: print("PASS: Performance mode switching, allocation equivalence, resource caching and full-rate attack execution.")
	quit(1 if failed else 0)
