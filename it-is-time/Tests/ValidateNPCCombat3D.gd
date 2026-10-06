extends SceneTree
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const FSM = preload("res://Scenes/Creatures/Components/NPCStateMachine3D.tscn")
const BEHAVIOR = preload("res://Scripts/Creatures/NPCBehaviorData.gd")
const ATTACK = preload("res://Scripts/Creatures/NPCAttackData.gd")
const DAMAGE = preload("res://Scripts/Creatures/CharacterDamageController3D.gd")
class AttackProbe extends Node:
	func predict_npc_attack(_id: StringName, _target: Node3D, _charge: float, _samples: int = 24, _margin: float = 0.1) -> Dictionary:
		return {"hit":true,"reason":&"test_prediction"}
	var active := false
	var starts := 0
	var target: Node3D
	func try_start_npc_attack(_id: StringName, enemy: Node3D, _charge: float) -> bool:
		active = true
		starts += 1
		target = enemy
		return true
	func is_npc_attack_active() -> bool: return active
	func cancel_npc_attack() -> void: active = false
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func actor(id: int, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.set_script(CHARACTER)
	node.faction_id = id
	root.add_child(node)
	node.position = at
	return node
func run() -> void:
	var npc := actor(1,Vector3(0,3,0))
	var ally := actor(1,Vector3(1,3,0))
	var enemy := actor(0,Vector3(3,3,0))
	var other := actor(2,Vector3(4,3,0))
	var damage := Node.new()
	damage.set_script(DAMAGE)
	damage.name = "CharacterDamageController3D"
	enemy.add_child(damage)
	check(damage.team_id == 0,"Damage faction must follow the root")
	ally.faction_id = 2
	ally.faction_id = 1
	var receiver := AttackProbe.new()
	receiver.name = "AttackProbe"
	npc.add_child(receiver)
	var behavior = BEHAVIOR.new()
	behavior.require_line_of_sight = false
	behavior.scan_interval = 0.05
	behavior.preferred_distance = 4.0
	var attack = ATTACK.new()
	attack.receiver_path = ^"AttackProbe"
	attack.maximum_range = 4.0
	attack.cooldown = 0.5
	behavior.attacks.append(attack)
	var ai := FSM.instantiate()
	ai.behavior = behavior
	ai.navigation_origin_path = ^""
	npc.add_child(ai)
	for frame: int in range(5): await physics_frame
	check(ai._enemy == enemy and receiver.target == enemy,"Must choose the closest enemy and ignore a closer ally")
	check(ai.current_state == ai.State.ATTACK and receiver.starts == 1,"A successful attack must enter ATTACK exactly once")
	receiver.active = false
	for frame: int in range(10): await physics_frame
	check(receiver.starts == 1,"Cooldown must prevent repeated attacks")
	for frame: int in range(30): await physics_frame
	check(receiver.starts == 2,"Cooldown expiry must permit another attack")
	damage._character_disabled = true
	for frame: int in range(10): await physics_frame
	check(ai._enemy == other and not receiver.active,"Death must cancel the old attack and select another enemy")
	for frame: int in range(40): await physics_frame
	check(receiver.target == other and receiver.active,"The new enemy must be attacked after the remaining cooldown")
	other.faction_id = 1
	for frame: int in range(5): await physics_frame
	check(ai._enemy == null and not receiver.active,"Faction change must stop friendly fire")
	other.faction_id = 2
	behavior.require_line_of_sight = true
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1,10,10)
	collision.shape = box
	wall.add_child(collision)
	root.add_child(wall)
	wall.position = Vector3(2,3,0)
	for frame: int in range(10): await physics_frame
	check(not ai._visible(other) and ai._enemy == null,"An obstacle must block acquisition and attacks")
	wall.queue_free()
	for frame: int in range(10): await physics_frame
	check(ai._enemy == other,"Removing the obstacle must allow acquisition")
	ai.enabled = false
	await physics_frame
	await physics_frame
	check(ai.get_movement_direction() == Vector3.ZERO and not receiver.active,"Disabled AI must stop movement and attacks")
	check(is_equal_approx(attack.cooldown,0.5),"Runtime cooldown must not mutate shared resources")
	# Exercise the real configurable arm receiver, not only the decision probe.
	var arm_npc = load("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn").instantiate()
	var target_torso = load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn").instantiate()
	target_torso.freeze = true
	other.add_child(target_torso)
	target_torso.global_position = Vector3(3,3.5,0)
	for body: Node in arm_npc.find_children("*","RigidBody3D",true,false): body.freeze = true
	root.add_child(arm_npc)
	var swing = arm_npc.get_node("LimbSwingController3D")
	var charged := false
	var swung := false
	for frame: int in range(150):
		await physics_frame
		if swing.get_group_state(0) == swing.SwingState.CHARGING: charged = true
		if swing.get_group_state(0) == swing.SwingState.SWINGING: swung = true
	check(charged and swung,"The ordinary NPC must charge and release its configured Arm group")
	print("NPC_COMBAT_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
