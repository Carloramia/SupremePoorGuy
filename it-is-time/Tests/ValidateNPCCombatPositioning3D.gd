extends "res://Tests/ValidateNPCCombat3D.gd"

class PredictionProbe extends AttackProbe:
	var hit := false
	var predictions := 0
	var geometry_range := 0.0
	func get_npc_attack_maximum_range(_id: StringName, _target: Node3D) -> float: return geometry_range
	func predict_npc_attack(_id: StringName, _target: Node3D, _charge: float, _samples: int = 24, _margin: float = 0.1) -> Dictionary:
		predictions += 1
		return {"hit":hit,"reason":&"positioning_test","confidence":1.0}

func run() -> void:
	var npc := actor(1,Vector3.ZERO)
	var enemy := actor(2,Vector3(3.5,0,0.6))
	var part_scene := load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn") as PackedScene
	var own := part_scene.instantiate() as PhysicalBodyPart3D
	own.name = "Torso"
	own.freeze = true
	npc.add_child(own)
	var target := part_scene.instantiate() as PhysicalBodyPart3D
	target.freeze = true
	enemy.add_child(target)
	var receiver := PredictionProbe.new()
	receiver.name = "AttackProbe"
	npc.add_child(receiver)
	var attack = ATTACK.new()
	attack.receiver_path = ^"AttackProbe"
	attack.maximum_range = 5.0
	attack.preferred_distance = 2.0
	var data = BEHAVIOR.new()
	data.require_line_of_sight = false
	data.attacks.append(attack)
	var ai := FSM.instantiate()
	ai.behavior = data
	ai.humanoid_xz_positioning = true
	npc.add_child(ai)
	ai.set_physics_process(false)
	await physics_frame
	ai._enemy = enemy
	ai._target = target
	var floor_distance: float = ai._minimum_body_standoff()
	check(floor_distance > 2.8, "Collision geometry must define a non-overlapping center distance")
	check(ai._preferred_attack_distance(attack) >= floor_distance + attack.distance_tolerance - 0.001, "The lower edge of the stop band must preserve body clearance")
	ai._prediction_distance_sample = 0
	check(ai._preferred_attack_distance(attack) >= floor_distance, "Prediction distance search must not restore overlapping positions")
	check(ai._target_z_attack_ready(attack,target), "Small Z offsets must reach the prediction stage")
	check(not ai._try_attack(3.5) and receiver.predictions > 0 and receiver.starts == 0, "Missed predictions must not launch attacks through the relaxed Z band")
	receiver.hit = true
	check(ai._try_attack(3.5) and receiver.starts == 1, "A predicted hit at Z=0.6 must permit an attack")
	ai._cancel_attack()
	attack.prediction_enabled = false
	check(not ai._target_z_attack_ready(attack,target), "Disabling prediction must retain the strict Z limit")
	attack.prediction_enabled = true
	target.position.z = 3.0
	check(not ai._try_attack(3.5) and ai._attack_block_reason == &"z_alignment_pending", "Large Z offsets must still require repositioning")
	ai.change_state(ai.State.MOVE_TO_TARGET)
	ai._has_requested_target = true
	ai._requested_target_position = own.global_position + Vector3(0.2,0,0)
	check(ai.get_npc_movement_speed_scale(6.0) < 0.11, "Near the stand-off position, desired speed must decrease")
	ai._requested_target_position = own.global_position + Vector3(10,0,0)
	check(is_equal_approx(ai.get_npc_movement_speed_scale(6.0),1.0), "Far approaches must retain full speed")
	ai.change_state(ai.State.WAITING)
	check(ai.get_npc_movement_speed_scale(6.0) == 0.0, "Holding a position must request zero velocity for braking")
	var arm := part_scene.instantiate() as PhysicalBodyPart3D
	arm.tags = [2]
	arm.freeze = true
	arm.position.x = 4.0
	npc.add_child(arm)
	await physics_frame
	ai._prediction_distance_sample = -1
	var envelope: float = ai._minimum_character_standoff()
	check(envelope > attack.maximum_range, "Extended limbs must be included in the stop envelope")
	var preferred: float = ai._preferred_attack_distance(attack)
	check(is_equal_approx(preferred, attack.maximum_range - attack.distance_tolerance), "An oversized envelope must use the far legal attack edge instead of an unreachable distance")
	check(preferred >= floor_distance, "Equipment handling must never remove the Torso clearance floor")
	receiver.geometry_range = 7.0
	receiver.hit = false
	ai._cooldowns.clear()
	target.global_position = own.global_position + Vector3(6.0, 0.0, 0.0)
	check(ai._attack_in_range(attack,target,6.0), "Actual weapon reach must permit prediction beyond the authored 5 meter gate")
	check(not ai._try_attack(6.0) and ai._attack_block_reason == &"prediction_misses", "A larger reach envelope must never bypass trajectory prediction")
	attack.prediction_enabled = false
	check(not ai._attack_in_range(attack,target,6.0), "Without prediction the authored maximum remains binding")
	print("NPC_COMBAT_POSITIONING_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
