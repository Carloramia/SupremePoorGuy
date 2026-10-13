extends SceneTree

const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const BALANCE = preload("res://Scripts/Creatures/TorsoBalanceController3D.gd")
var failed := false

class ActionProbe extends Node:
	var cancellations := 0
	var last_reason: StringName
	var control_enabled := true
	func cancel_action(reason: StringName) -> void:
		cancellations += 1
		last_reason = reason
	func set_character_control_enabled(value: bool) -> void: control_enabled = value

class SwingProbe extends Node:
	var cancelled := false
	func cancel_npc_attack() -> void: pass
	func cancel_player_actions() -> void: cancelled = true

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	var actor := CHARACTER.new()
	actor.require_head_and_torso_connectivity = false
	root.add_child(actor)
	var torso := PhysicalBodyPart3D.new()
	torso.name = "Torso"
	torso.freeze = true
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	torso.add_child(sprite)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	torso.add_child(collision)
	actor.add_child(torso)
	var balance := BALANCE.new()
	balance.name = "TorsoBalanceController3D"
	torso.add_child(balance)
	var action := ActionProbe.new()
	action.process_mode = Node.PROCESS_MODE_ALWAYS
	actor.add_child(action)
	var swing := SwingProbe.new()
	swing.name = "LimbSwingController3D"
	actor.add_child(swing)
	var disabled := ActionProbe.new()
	disabled.process_mode = Node.PROCESS_MODE_DISABLED
	actor.add_child(disabled)
	var first := Node.new()
	var second := Node.new()
	root.add_child(first)
	root.add_child(second)
	actor.set_temporary_ragdoll(first, true)
	check(balance.process_mode == Node.PROCESS_MODE_DISABLED, "Ragdoll must suspend the controller nested below a physical Torso")
	check(action.cancellations == 1 and action.last_reason == &"ragdoll" and swing.cancelled, "Ragdoll cleans up both generic actions and player swing state")
	check(torso.process_mode != Node.PROCESS_MODE_DISABLED, "Physical body simulation must keep running")
	actor.set_temporary_ragdoll(second, true)
	check(action.cancellations == 1, "Overlapping ragdoll sources must not cancel an action twice")
	var late := ActionProbe.new()
	torso.add_child(late)
	await process_frame
	check(late.process_mode == Node.PROCESS_MODE_DISABLED and late.cancellations == 1, "New nested controls must join an active suspension")
	actor.set_temporary_ragdoll(first, false)
	check(balance.process_mode == Node.PROCESS_MODE_DISABLED, "A remaining source keeps all controls suspended")
	actor.set_temporary_ragdoll(second, false)
	check(balance.process_mode == Node.PROCESS_MODE_INHERIT and action.process_mode == Node.PROCESS_MODE_ALWAYS, "Last source restores each component's original processing mode")
	check(disabled.process_mode == Node.PROCESS_MODE_DISABLED, "A component disabled before ragdoll must remain disabled")
	late.free()
	check(actor.get_control_components().size() == 4, "Removed components must leave the cached catalog")
	actor.set_temporary_ragdoll(first, true)
	actor._ensure_damage_controller()
	actor.get_node("CharacterDamageController3D")._disable_character_controllers()
	actor.set_temporary_ragdoll(first, false)
	check(not action.control_enabled and not balance._character_enabled, "Death disables direct and nested controls through the same catalog")
	check(action.process_mode == Node.PROCESS_MODE_DISABLED and balance.process_mode == Node.PROCESS_MODE_DISABLED, "Ragdoll expiration cannot revive dead controls")
	first.free()
	second.free()
	actor.free()
	await process_frame
	print("CHARACTER_CONTROL_LIFECYCLE ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
