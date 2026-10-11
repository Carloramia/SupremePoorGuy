@tool
extends Node
const DATA = preload("res://Scripts/Creatures/WolfAttackData.gd")
const PREDICTION = preload("res://Scripts/Creatures/NPCAttackPrediction3D.gd")
const PLAYER = preload("res://Scripts/Player/PlayerControlContext.gd")
@export var enabled := true
@export var data: DATA
var controller: Node
var active := false
var elapsed := 0.0
var cooldown_remaining := 0.0
var target: PhysicalBodyPart3D
var owned_feet: Array[RigidBody3D] = []
var owned_bodies: Array[RigidBody3D] = []

func available() -> bool:
	return enabled and data != null and data.enabled and not active and cooldown_remaining <= 0.0 and (controller == null or controller.can_start_module(name))

func predict(_target: PhysicalBodyPart3D, _samples: int, _margin: float) -> Dictionary:
	return {"hit":false,"reason":&"unimplemented"}

func start(next_target: PhysicalBodyPart3D) -> bool:
	if not available() or controller == null or not controller._ai_allowed(): return false
	target = next_target
	elapsed = 0.0
	active = true
	controller.log_event(name, &"started")
	return true

func tick(delta: float) -> void:
	cooldown_remaining = maxf(0.0, cooldown_remaining-delta)
	if active: elapsed += delta

func finish(reason: StringName = &"completed") -> void:
	if not active: return
	active = false
	cooldown_remaining = data.cooldown if data != null else 0.0
	owned_feet.clear()
	owned_bodies.clear()
	controller.sync_foot_ownership()
	controller.log_event(name, reason,diagnostics())

func alive(body: Variant) -> bool:
	return is_instance_valid(body) and body is RigidBody3D and body.is_inside_tree() and not body.is_queued_for_deletion() and not body.is_broken and not body.freeze

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): finish(&"removed")

func predicts_enemy_hit(shape: Shape3D, pose: Transform3D, enemy_part: PhysicalBodyPart3D, time: float, margin: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = pose
	query.transform.origin -= PREDICTION.velocity(enemy_part)*time
	query.margin = maxf(margin,0.0)
	query.collision_mask = 0xFFFFFFFF
	query.exclude = controller.own_rids()
	var enemy := PLAYER.character_of(enemy_part)
	for contact: Dictionary in controller.get_parent().get_world_3d().direct_space_state.intersect_shape(query,64):
		if contact.collider is PhysicalBodyPart3D and not contact.collider.is_broken and PLAYER.character_of(contact.collider) == enemy: return true
	return false

func diagnostics() -> Dictionary:
	return {"module":name,"active":active,"elapsed":elapsed,"cooldown":cooldown_remaining}
