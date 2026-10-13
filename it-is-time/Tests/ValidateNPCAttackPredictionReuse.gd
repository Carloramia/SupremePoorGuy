extends SceneTree

const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const FSM = preload("res://Scenes/Creatures/Components/NPCStateMachine3D.tscn")
var failed := false

class AttackProbe extends Node:
	var predictions := 0
	var starts := 0
	var accept_start := true
	var predicted_position := Vector3.ZERO
	func predict_npc_attack(_action: StringName, target: Node3D, _charge: float, _samples: int, _margin: float) -> Dictionary:
		predictions += 1
		predicted_position = target.global_position
		return {"hit": true, "confidence": 1.0}
	func try_start_npc_attack(_action: StringName, _target: Node3D, _charge: float) -> bool:
		starts += 1
		return accept_start
	func is_npc_attack_active() -> bool: return false
	func cancel_npc_attack() -> void: pass

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	var actor := CHARACTER.new()
	root.add_child(actor)
	var enemy := CHARACTER.new()
	root.add_child(enemy)
	enemy.position.x = 2.0
	var receiver := AttackProbe.new()
	receiver.name = "AttackProbe"
	actor.add_child(receiver)
	var machine: Node = FSM.instantiate()
	machine.enabled = false
	machine.behavior = load("res://Scripts/Creatures/NPCBehaviorData.gd").new()
	machine.behavior.require_line_of_sight = false
	var attack := NPCAttackData.new()
	attack.receiver_path = ^"AttackProbe"
	attack.cooldown = 0.0
	machine.behavior.attacks.append(attack)
	actor.add_child(machine)
	machine._enemy = enemy
	machine._target = enemy
	check(machine._try_attack(2.0), "Predicted attack must start")
	check(receiver.predictions == 1 and receiver.starts == 1, "Selection reuses its synchronous prediction; receiver still validates execution")
	machine._cancel_attack()
	receiver.accept_start = false
	await physics_frame
	enemy.position.x = 3.0
	check(not machine._try_attack(3.0), "Execution-time rejection must still prevent an attack")
	check(receiver.predictions == 2 and receiver.starts == 2 and receiver.predicted_position == enemy.global_position, "The next decision must predict the current target position again")
	check(machine._attack_block_reason == &"receiver_rejected", "Preserve execution rejection diagnostics")
	actor.free()
	enemy.free()
	print("NPC_ATTACK_PREDICTION_REUSE ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
