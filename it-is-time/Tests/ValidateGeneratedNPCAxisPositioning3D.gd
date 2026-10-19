extends SceneTree

const NPC = preload("res://Scripts/Creatures/NPCStateMachine3D.gd")
const ATTACK = preload("res://Scripts/Creatures/NPCAttackData.gd")
const BEHAVIOR = preload("res://Scripts/Creatures/NPCBehaviorData.gd")

class Brain extends NPC:
	func _ready() -> void: set_physics_process(false)
	func _get_navigation_origin_position() -> Vector3: return Vector3.ZERO
	func _set_agent_target(point: Vector3) -> void:
		_requested_target_position = point
		_has_requested_target = true
	func _is_enemy(actor: Variant) -> bool: return is_instance_valid(actor)
	func _enemy_position(_actor: Node3D) -> Vector3: return _target.global_position

class Receiver extends Node:
	var prepare := false
	var preparation_calls := 0
	var owns_lane := false
	func try_start_npc_attack(_action: StringName, _target: Node3D, _charge: float) -> bool: return true
	func is_npc_attack_active() -> bool: return false
	func cancel_npc_attack() -> void: pass
	func uses_navigation_attack_gate() -> bool: return owns_lane
	func should_prepare_npc_attack(_action: StringName, _target: Node3D) -> bool:
		preparation_calls += 1
		return prepare

var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	for name: String in [
		"Generate_Wolf_NPC", "Generate_StumpBeast_NPC", "Generate_HornedBeast_NPC", "Generate_Spider_NPC",
		"Generate_Snake_NPC", "Generate_Creature_NPC", "Generate_Bird_NPC", "Generate_Rat_1_NPC", "Generate_Rat_2_NPC",
		"Generate_Human_NPC", "Human/Armed/Generate_Human_Bow_NPC", "Human/Armed/Generate_Human_Spear1_NPC",
		"Human/Armed/Generate_Human_Spear5_NPC", "Human/Armed/Generate_Human_ClawGauntlet_NPC",
		"Human/Armed/Generate_Human_CurvedSword_NPC", "Human/Armed/Generate_Human_Flail_NPC", "Human/Armed/Generate_Human_Shield_NPC"
	]:
		var actor: Node = load("res://Scenes/Creatures/Characters/"+name+".tscn").instantiate()
		actor.generate_on_ready = false
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(actor)
		var ai: Node = actor.get_node("NPCStateMachine3D")
		check(ai.generated_x_axis_facing and ai._uses_axis_positioning(), name+" must pair X-only facing with X/Z positioning")
		actor.free()
	var actor := Node3D.new()
	var receiver := Receiver.new()
	receiver.name = "AttackProbe"
	actor.add_child(receiver)
	var brain := Brain.new()
	var agent := NavigationAgent3D.new()
	agent.name = "NavigationAgent3D"
	brain.add_child(agent)
	actor.add_child(brain)
	root.add_child(actor)
	var target := Node3D.new()
	root.add_child(target)
	brain._enemy = target
	brain._target = target
	brain.behavior = BEHAVIOR.new()
	brain.generated_x_axis_facing = true
	brain.humanoid_xz_positioning = false
	var attack := ATTACK.new()
	attack.receiver_path = ^"AttackProbe"
	attack.minimum_range = 1.0
	attack.maximum_range = 10.0
	attack.preferred_distance = 6.0
	attack.distance_tolerance = 0.25
	attack.prediction_enabled = true
	brain.behavior.attacks.assign([attack])
	brain.current_state = brain.State.MOVE_TO_TARGET
	for side: float in [-1.0, 1.0]:
		target.position = Vector3(side*6.0, 0.0, 30.0)
		check(brain._plan_attack_distance(target.position.length(), brain._available_attacks()), "A large Z offset must request lane alignment")
		check(is_zero_approx(brain._requested_target_position.x) and is_equal_approx(brain._requested_target_position.z,30.0), "An actor inside its X stop band must move along Z without orbiting")
		check(not brain._target_z_attack_ready(attack,target), "Ordinary attacks must wait for lane alignment")
		brain.current_state = brain.State.MOVE_TO_TARGET
		check(brain.get_npc_movement_speed_scale(8.0) > 0.0, "Z-only alignment must retain propulsion at zero X error")
		target.position.z = 0.0
		check(not brain._plan_attack_distance(6.0,brain._available_attacks()), "Aligned actors must retain their attack stop band")
		target.position = Vector3(side*20.0, 0.0, 30.0)
		check(brain._plan_attack_distance(target.position.length(),brain._available_attacks()), "Far targets must be approached")
		check(brain._requested_target_position.is_equal_approx(Vector3(side*14.0,0.0,30.0)), "Approach must use X stand-off and target Z independently")
	# Preparation must not reserve a pounce while its target is in another lane.
	receiver.prepare = true
	receiver.preparation_calls = 0
	target.position = Vector3(6,0,30)
	check(brain._plan_attack_distance(30.6,brain._available_attacks()) and receiver.preparation_calls == 0, "Preparation must not preempt lane correction")
	target.position.z = 0.0
	check(not brain._plan_attack_distance(6.0,brain._available_attacks()) and receiver.preparation_calls == 1, "Aligned preparation must remain available")
	receiver.prepare = false
	brain._friendly_approach_offset = 10.0
	target.position.z = 30.0
	brain._plan_attack_distance(target.position.length(),brain._available_attacks())
	check(absf(brain._requested_target_position.z-target.position.z)+brain.attack_z_tolerance <= brain.predicted_attack_z_tolerance, "An avoidance lane plus arrival tolerance must remain inside attack alignment tolerance")
	brain._friendly_approach_offset = 0.0
	# Charge/Snake own attack-origin alignment rather than using the Torso-only gate.
	receiver.owns_lane = true
	target.position.z = 30.0
	check(brain._target_z_attack_ready(attack,target), "A receiver's own alignment stage must remain usable")
	receiver.owns_lane = false
	# Losing all attack limbs must not restore the old radial planner.
	brain.behavior.preferred_distance = 6.0
	brain.behavior.attacks.clear()
	target.position = Vector3(2,0,30)
	check(brain._plan_attack_distance(target.position.length(),brain._available_attacks()), "Unarmed pursuit must still align Z")
	check(brain._requested_target_position.is_equal_approx(Vector3(0,0,30)), "Unarmed pursuit must not retreat or orbit inside the X stop distance")
	target.position.z = 0.0
	check(not brain._plan_attack_distance(2.0,brain._available_attacks()), "Unarmed close-range pursuit must stop")
	# Facing depends on enemy X, never on the diagonal navigation direction.
	await physics_frame
	target.position = Vector3(-20,0,30)
	brain.get_generated_facing_direction(0.0)
	check(brain.get_generated_facing_direction(0.3) == Vector3.LEFT, "A distant lane must not alter left-facing selection")
	brain.current_state = brain.State.ATTACK
	target.position.x = 20.0
	check(brain.get_generated_facing_direction(1.0) == Vector3.LEFT, "An attack must retain its starting facing")
	brain.current_state = brain.State.WAITING
	await physics_frame
	target.position.x = 0.01
	check(brain.get_generated_facing_direction(1.0) == Vector3.LEFT, "X dead-zone noise must retain facing")
	actor.free()
	target.free()
	print("GENERATED_NPC_AXIS_POSITIONING_FAILED" if failed else "GENERATED_NPC_AXIS_POSITIONING_PASSED")
	quit(1 if failed else 0)
