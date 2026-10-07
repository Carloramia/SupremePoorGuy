extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var bird := BIRD.instantiate()
	bird.generate_on_ready = false
	bird.position.y = 20.0
	root.add_child(bird)
	var brain := bird.get_node("NPCStateMachine3D")
	brain.enabled = false
	var generator := bird.get_node("BirdGenerator")
	generator.overall_scale = 1.0
	generator._random.seed = 43
	check(bird.generate_creature(), "Preference fixture must generate")
	for part: RigidBody3D in bird._get_physical_body_parts(): part.freeze = true
	var enemy := Node3D.new()
	enemy.set_script(CHARACTER)
	enemy.faction_id = 0
	enemy.require_head_and_torso_connectivity = false
	root.add_child(enemy)
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.freeze = true
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso])
	enemy.add_child(target)
	brain._enemy = enemy
	brain._target = target
	var head: PhysicalBodyPart3D = brain._attack_head()
	var dive := bird.get_node("BirdDiveAttackController3D")
	brain.preferred_attack_angle_degrees = 30.0
	brain.preferred_attack_distance = 30.0
	brain._update_attack_goal(target)
	var head_offset: Vector3 = head.global_position - brain._get_navigation_origin_position()
	var expected_head: Vector3 = brain._flight_goal + head_offset
	check(is_equal_approx(expected_head.distance_to(target.global_position), 30.0), "Preferred distance must be a 3D Head-to-target distance")
	check(absf(rad_to_deg(atan2(expected_head.y - target.global_position.y, expected_head.slide(Vector3.UP).distance_to(target.global_position.slide(Vector3.UP)))) - 30.0) < 0.001, "Preferred angle must control Head-to-target depression")
	head.global_position = expected_head
	check(brain._attack_preference_check(target).ready, "Desired preparation geometry must satisfy the preference")
	head.global_position = target.global_position + Vector3(-20, 20, 0)
	dive._flight._set_state(dive._flight.State.AIRBORNE, "test_airborne")
	brain._preference_elapsed = 0.0
	brain.enabled = true
	check(not brain._try_attack(20.0), "Legal non-preferred geometry must wait before attacking")
	check(brain._attack_block_reason == &"approaching_preferred_attack_geometry", "Preference wait must expose its reason")
	brain._preference_elapsed = brain.maximum_preference_wait
	check(brain._attack_preference_check(target).fallback_allowed, "Preference wait must be bounded")
	check(brain._try_attack(20.0), "After its bounded wait the NPC must be allowed to start a legal non-preferred attack")
	dive.cancel_action(&"preference_test")
	brain.enabled = false
	brain.preferred_attack_angle_degrees = 0.0
	brain.preferred_attack_distance = 999.0
	var effective: Vector2 = brain._effective_attack_preference()
	check(is_equal_approx(effective.x, dive.data.minimum_depression_angle_degrees) and is_equal_approx(effective.y, dive.data.maximum_target_distance), "Preferences must remain inside the actual dive geometry limits")
	# AI range fields are not a close-range veto when the receiver provides its 3D range hook.
	dive._flight._set_state(dive._flight.State.AIRBORNE, "test_airborne")
	head.global_position = target.global_position + Vector3(-50, 50, 0)
	check(brain._attack_in_range(preload("res://Resources/AI/BirdDiveAttack.tres"), target, 50.0), "A legal 70-unit dive must not be rejected by the generic AI 40-unit horizontal range")
	head.global_position = target.global_position + Vector3(-50, 1, 0)
	check(not brain._attack_in_range(preload("res://Resources/AI/BirdDiveAttack.tres"), target, 50.0), "Far shallow approaches must still respect the minimum dive angle")
	brain.use_attack_preferences = false
	brain._update_attack_goal(target)
	check(is_equal_approx(brain._flight_goal.y - target.global_position.y, brain.attack_altitude), "Disabling preferences must restore legacy altitude planning")
	print("BIRD_NPC_ATTACK_PREFERENCES_FAILED" if failed else "BIRD_NPC_ATTACK_PREFERENCES_PASSED")
	quit(1 if failed else 0)
