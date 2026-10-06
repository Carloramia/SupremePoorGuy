extends "res://Tests/ValidateNPCCombat3D.gd"
const NPC = preload("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn")
const TORSO = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn")
class PredictionProbe extends AttackProbe:
	func predict_npc_attack(_id: StringName, target_part: Node3D, _charge: float, _samples: int = 24, _margin: float = 0.1) -> Dictionary:
		return {"hit":target_part.name == "ReachableTorso","reason":&"test_trajectory"}

func run() -> void:
	var npc := NPC.instantiate()
	npc.get_node("NPCStateMachine3D").enabled = false
	for body: Node in npc.find_children("*","RigidBody3D",true,false): body.freeze = true
	root.add_child(npc)
	var enemy := actor(2,Vector3.ZERO)
	var torso := TORSO.instantiate() as RigidBody3D
	torso.freeze = true
	enemy.add_child(torso)
	torso.global_position = Vector3(3,3.5,0)
	for frame: int in range(4): await physics_frame
	var swing := npc.get_node("LimbSwingController3D")
	var before: Transform3D = npc.get_node("Arm_R").global_transform
	var prediction: Dictionary = swing.predict_npc_attack(&"PrimaryArm",torso,0.6)
	check(prediction.hit,"Near target collision geometry must intersect the predicted swing")
	check(before.is_equal_approx(npc.get_node("Arm_R").global_transform) and swing.get_group_state(0)==swing.SwingState.IDLE,"Prediction must not move bodies or start charging")
	torso.global_position = Vector3(30,30,0)
	await physics_frame
	await physics_frame
	check(not swing.predict_npc_attack(&"PrimaryArm",torso,0.6).hit,"A distant high target must miss despite a valid receiver")
	torso.global_position = Vector3(3,3.5,0)
	await physics_frame
	await physics_frame
	torso.linear_velocity = Vector3(100,0,0)
	check(not swing.predict_npc_attack(&"PrimaryArm",torso,0.6).hit,"A rapidly departing target must be tested at its predicted position")
	torso.linear_velocity = Vector3.ZERO
	check(not swing.predict_npc_attack(&"PrimaryArm",torso,0.01).hit,"Insufficient charge cannot produce a swing")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1,20,20)
	collision.shape = box
	wall.add_child(collision)
	root.add_child(wall)
	wall.position = Vector3(1.5,3,0)
	await physics_frame
	await physics_frame
	check(not swing.predict_npc_attack(&"PrimaryArm",torso,0.6).hit,"Terrain intersecting the swing must block the forecast")
	wall.queue_free()
	npc.queue_free()
	enemy.queue_free()
	await physics_frame
	# State machine must skip a closer unreachable Torso and try another.
	var attacker := actor(1,Vector3.ZERO)
	var victim := actor(2,Vector3.ZERO)
	var near := TORSO.instantiate() as RigidBody3D
	near.freeze = true
	near.name = "UnreachableTorso"
	victim.add_child(near)
	near.global_position = Vector3(2,0,0)
	var far := TORSO.instantiate() as RigidBody3D
	far.freeze = true
	far.name = "ReachableTorso"
	victim.add_child(far)
	far.global_position = Vector3(3,0,0)
	var receiver := PredictionProbe.new()
	receiver.name = "AttackProbe"
	attacker.add_child(receiver)
	var data = BEHAVIOR.new()
	data.require_line_of_sight = false
	var attack = ATTACK.new()
	attack.receiver_path = ^"AttackProbe"
	attack.maximum_range = 5.0
	data.attacks.append(attack)
	var ai := FSM.instantiate()
	ai.behavior = data
	ai.navigation_origin_path = ^""
	attacker.add_child(ai)
	ai.set_physics_process(false)
	ai._update_combat(0.1)
	check(receiver.target == far and ai.current_state == ai.State.ATTACK,"Choose a reachable Torso after the nearest Torso fails prediction")
	ai._cancel_attack()
	ai.change_state(ai.State.WAITING)
	ai._cooldowns.clear()
	far.name = "AlsoUnreachable"
	ai._attack_retry = 0.0
	ai._update_combat(0.1)
	check(ai.current_state != ai.State.ATTACK and ai._attack_block_reason == &"prediction_misses","Range alone must not permit an attack when every forecast misses")
	print("NPC_HIT_PREDICTION_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
