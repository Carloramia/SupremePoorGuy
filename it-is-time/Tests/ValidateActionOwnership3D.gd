extends SceneTree

var failed := false

class ActorProbe extends Node3D:
	var expanded: Array[RigidBody3D] = []
	func set_limb_action_limits(feet: Array[RigidBody3D], enabled: bool) -> void:
		if enabled: expanded.assign(feet)
		else: expanded.clear()

class MovementProbe extends "res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd":
	var released: Array[RigidBody3D] = []
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _release_support_pin(foot: RigidBody3D) -> void: released.append(foot)

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	var actor := ActorProbe.new()
	root.add_child(actor)
	var movement := MovementProbe.new()
	actor.add_child(movement)
	var feet: Array[RigidBody3D] = []
	for index: int in 3:
		var foot := RigidBody3D.new()
		foot.freeze = true
		actor.add_child(foot)
		feet.append(foot)
	var first := Node.new()
	var second := Node.new()
	actor.add_child(first)
	actor.add_child(second)
	movement.begin_action_control([feet[0]], [feet[0]], first)
	movement.set_action_foot_grounded(feet[0], true)
	movement.set_action_body_weight(feet[0], 0.75)
	movement.begin_action_control([feet[0], feet[1]], [feet[0], feet[1]], second)
	check(movement.released.size() == 2 and movement._action_feet[feet[0]], "Overlapping owners must not release an already grounded action foot")
	movement.end_action_control(first)
	check(movement._action_feet.size() == 2 and movement._action_feet[feet[0]], "Ending one owner must retain another owner's feet and ground state")
	check(is_equal_approx(movement._action_body_weights[feet[0]], 0.75), "Remaining body support weights must survive unrelated cancellation")
	check(actor.expanded.size() == 2, "Temporary joint limits must remain expanded for all remaining owners")
	movement.begin_action_control([feet[2]], [feet[2]], second)
	check(movement._action_feet.size() == 1 and movement._action_feet.has(feet[2]), "Replacing one owner's claim must release its former feet")
	second.free()
	check(movement._action_feet.is_empty() and actor.expanded.is_empty(), "Removing the last owner must restore gait control and authored joint limits")
	movement.begin_action_control([feet[0]], [feet[0]])
	movement.begin_action_control([feet[1]], [feet[1]], first)
	movement.end_action_control()
	check(movement._action_feet.is_empty() and movement._action_owners.is_empty(), "The existing no-argument cleanup API must still release every action")
	var stomp := preload("res://Scripts/Creatures/CreatureActionController3D.gd").new()
	actor.add_child(stomp)
	stomp._movement = movement
	stomp._data = preload("res://Scripts/Creatures/CreatureActionData.gd").new()
	stomp.phase = stomp.Phase.RISING
	movement.begin_action_control([feet[0]], [feet[0]], stomp)
	movement.begin_action_control([feet[1]], [feet[1]], first)
	stomp.cancel_action(&"ragdoll")
	check(not stomp.is_active() and movement._action_feet.size() == 1 and movement._action_feet.has(feet[1]), "The actual stomp cancellation path must release only its own claim")
	actor.free()
	print("ACTION_OWNERSHIP ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
