@tool
extends Node
const PLAYER = preload("res://Scripts/Player/PlayerControlContext.gd")
const MODULE = preload("res://Scripts/Creatures/WolfAttackModule3D.gd")
@export var enabled := true
@export var diagnostic_logging := false
var movement: Node
var torso: PhysicalBodyPart3D
var _character_enabled := true
var _claimed: Array[RigidBody3D] = []
var _claimed_bodies: Array[RigidBody3D] = []
var _log_elapsed := 0.0
var _combo_elapsed := 0.0
var _combo_target: PhysicalBodyPart3D
var _combo_pending: Array[StringName] = []
var _combo_retry := 0.0
var _rids: Array[RID] = []

func can_start_module(module_name: StringName) -> bool:
	if module_name == &"Pounce": return not get_node("Bite").active
	if module_name == &"Bite": return not get_node("Bite").active and not is_pouncing()
	return false

func blocks_locomotion() -> bool:
	return is_pouncing() or get_node("Bite").active

func _ready() -> void:
	if Engine.is_editor_hint(): set_physics_process(false); return
	process_physics_priority = -40
	add_to_group(&"wolf_attack_controllers")
	refresh_physics_query_cache()
	var console := get_node_or_null("/root/RuntimeConsole")
	if console != null and console.has_method("is_wolf_attack_tracking_enabled"):
		diagnostic_logging = console.is_wolf_attack_tracking_enabled(get_parent())

func _modules() -> Array[MODULE]:
	var result: Array[MODULE] = []
	for child: Node in get_children():
		if child is MODULE: result.append(child)
	return result

func _module(action_id: StringName) -> MODULE:
	match action_id:
		&"wolf_pounce": return get_node_or_null("Pounce")
		&"wolf_bite": return get_node_or_null("Bite")
	return null

func refresh_physics_query_cache() -> void:
	if Engine.is_editor_hint(): return
	cancel_action(&"regenerated")
	movement = get_parent().get_node_or_null("GeneratedLegStepMovementController3D")
	torso = movement._torso if movement != null else null
	_rids.assign(get_parent().get_physical_body_rids())
	for module: MODULE in _modules():
		module.controller = self
		if module.has_method("refresh"): module.refresh()

func _ai_allowed() -> bool:
	if Engine.is_editor_hint() or not enabled or not _character_enabled or movement == null or not is_instance_valid(torso) or torso.is_broken or get_parent().is_temporarily_ragdolled(): return false
	var ai := get_parent().get_node_or_null("NPCStateMachine3D")
	return ai != null and ai.attack_execution_enabled and PLAYER.controlled_character(self) != get_parent()

func _target_valid(target: Node3D) -> bool:
	if not target is PhysicalBodyPart3D or not target.is_inside_tree() or target.is_queued_for_deletion() or target.is_broken: return false
	var character := PLAYER.character_of(target)
	return character != null and character != get_parent() and character.get_faction_id() != get_parent().get_faction_id() and target.get_world_3d() == get_parent().get_world_3d()

func has_npc_attack(action_id: StringName) -> bool:
	var module := _module(action_id)
	return _ai_allowed() and module != null and module.enabled and module.data != null and module.data.enabled

func predict_npc_attack(action_id: StringName, target: Node3D, _charge: float, samples: int, margin: float) -> Dictionary:
	if not has_npc_attack(action_id) or not _target_valid(target): return {"hit":false,"reason":&"not_ai_or_invalid_target"}
	if movement.recovery_control_active or movement._planar_mode_active() or movement.simplified_physics_mode or movement.is_action_turn_blocked(): return {"hit":false,"reason":&"turning_or_recovery"}
	return _module(action_id).predict(target,samples,margin)

func try_start_npc_attack(action_id: StringName, target: Node3D, _charge: float) -> bool:
	if not predict_npc_attack(action_id,target,0.0,24,0.1).get("hit",false): return false
	var old_action := get_parent().get_node_or_null("CreatureActionController3D")
	if old_action != null and old_action.is_active(): return false
	var started := _module(action_id).start(target)
	sync_foot_ownership()
	return started

func is_npc_attack_active() -> bool:
	for module: MODULE in _modules():
		if module.active: return true
	return not _combo_pending.is_empty()

func is_pouncing() -> bool:
	var module := _module(&"wolf_pounce")
	return module != null and module.active

func get_npc_attack_minimum_range(action_id: StringName) -> float:
	return maxf(_module(action_id).data.minimum_range*pounce_scale(),_module(action_id).landing_standoff()+pounce_scale()*0.5) if action_id == &"wolf_pounce" else 0.0

func uses_dynamic_npc_attack_range(_action_id: StringName) -> bool:
	return true

func get_npc_attack_maximum_range(action_id: StringName, _target: Node3D = null) -> float:
	if action_id == &"wolf_pounce": return _module(action_id).maximum_target_distance(_target)
	var reach := 0.0
	if not is_instance_valid(torso) or movement == null: return reach
	if action_id == &"wolf_bite":
		var jaw = _module(action_id).jaw
		if is_instance_valid(jaw):
			var bite := _module(action_id)
			reach = torso.global_position.distance_to(jaw.global_position)+Vector3(jaw.get_meta(&"generated_size",Vector3.ONE)).length()+minf(pounce_scale()*_module(&"wolf_pounce").data.reference_body_length*bite.data.bite_advance_ratio,bite._travel_limit(forward()))
	return reach

func get_npc_attack_distance_tolerance(action_id: StringName) -> float:
	return pounce_scale()*_module(&"wolf_pounce").data.reference_body_length*_module(action_id).data.distance_tolerance_body_ratio

func get_npc_attack_preferred_distance(action_id: StringName, target: Node3D = null) -> float:
	var maximum := get_npc_attack_maximum_range(action_id,target)
	var tolerance := get_npc_attack_distance_tolerance(action_id)
	var minimum := get_npc_attack_minimum_range(action_id)
	if action_id == &"wolf_pounce":
		var bite := _module(&"wolf_bite")
		if bite.enabled and bite.data != null and bite.data.enabled:
			minimum = maxf(minimum,get_npc_attack_maximum_range(&"wolf_bite",target)+tolerance*2.0)
	var upper := maxf(minimum,maximum-tolerance)
	return lerpf(minimum,upper,_module(action_id).data.preferred_range_ratio)

func should_prepare_npc_attack(action_id: StringName, target: Node3D) -> bool:
	if action_id != &"wolf_pounce" or not has_npc_attack(action_id) or not _target_valid(target): return false
	if movement.recovery_control_active or movement._planar_mode_active() or movement.simplified_physics_mode or movement.is_action_turn_blocked(): return false
	var pounce := _module(action_id)
	return pounce.available() and pounce.has_launch_gait() and is_npc_target_in_attack_range(action_id,target)

func is_npc_attack_distance_candidate(action_id: StringName, target: Node3D) -> bool:
	return action_id != &"wolf_pounce" or not is_instance_valid(target) or not is_target_in_bite_distance(target)

func is_target_in_bite_distance(target: Node3D) -> bool:
	var bite := _module(&"wolf_bite")
	if bite == null or not bite.enabled or bite.data == null or not bite.data.enabled: return false
	if not is_instance_valid(bite.head) or bite.head.is_broken or not is_instance_valid(bite.jaw) or bite.jaw.is_broken or not is_instance_valid(bite.joint): return false
	# Distance exclusion is independent of cooldown and current attack ownership.
	return torso.global_position.distance_to(target.global_position) <= get_npc_attack_maximum_range(&"wolf_bite",target)

func is_npc_target_in_attack_range(action_id: StringName, target: Node3D) -> bool:
	if not _target_valid(target) or not is_instance_valid(torso): return false
	if action_id == &"wolf_pounce": return not is_target_in_bite_distance(target) and _module(action_id).intercept_plan(target).hit
	var distance := torso.global_position.distance_to(target.global_position)
	return distance >= get_npc_attack_minimum_range(action_id) and distance <= get_npc_attack_maximum_range(action_id,target)

func get_npc_attack_range_diagnostics(action_id: StringName, target: Node3D) -> Dictionary:
	if action_id == &"wolf_pounce" and _target_valid(target) and is_target_in_bite_distance(target):
		return {"hit":false,"reason":&"within_bite_range","bite_maximum_distance":get_npc_attack_maximum_range(&"wolf_bite",target)}
	return _module(action_id).intercept_plan(target) if action_id == &"wolf_pounce" and _target_valid(target) else {}

func get_npc_attack_maximum_duration(_action_id: StringName) -> float:
	var pounce := _module(&"wolf_pounce").data
	var bite := _module(&"wolf_bite").data
	return pounce.pounce_plant_timeout+pounce.pounce_charge_time+maxf(pounce.flight_time*sqrt(pounce_scale()),sqrt(8.0*pounce.minimum_lift_height*pounce_scale()/maxf(movement._gravity_acceleration().length(),0.001)))+pounce.landing_timeout+bite.bite_spacing_retreat_time*2.0+bite.bite_plant_timeout+bite.bite_retract_time+bite.jaw_open_time+bite.bite_lunge_timeout+bite.jaw_close_time+bite.recovery_time+0.5

func pounce_scale() -> float:
	if not is_instance_valid(torso): return 1.0
	var size: Vector3 = torso.get_meta(&"generated_size",Vector3.ONE)
	return maxf(size.x*torso.global_basis.x.length()/_module(&"wolf_pounce").data.reference_body_length,0.01)

func forward() -> Vector3:
	return torso.global_basis.x.slide(Vector3.UP).normalized() if is_instance_valid(torso) else Vector3.RIGHT

func scale_factor() -> float:
	var generator := get_parent().get_node_or_null(get_parent().generator_path)
	return maxf(generator.overall_scale,0.01) if generator != null else 1.0

func own_rids() -> Array[RID]:
	return _rids

func sync_foot_ownership() -> void:
	if movement == null: return
	var wanted: Array[RigidBody3D] = []
	var bodies: Array[RigidBody3D] = []
	for module: MODULE in _modules():
		if module.active:
			for foot: RigidBody3D in module.owned_feet:
				if is_instance_valid(foot) and not wanted.has(foot): wanted.append(foot)
			for body: RigidBody3D in module.owned_bodies:
				if is_instance_valid(body) and not bodies.has(body): bodies.append(body)
	if wanted == _claimed and bodies == _claimed_bodies: return
	if not _claimed.is_empty() or not _claimed_bodies.is_empty(): movement.end_action_control(self)
	_claimed = wanted
	_claimed_bodies = bodies
	if not wanted.is_empty() or not bodies.is_empty(): movement.begin_action_control(wanted,bodies,self)

func try_end_combo(target: PhysicalBodyPart3D) -> void:
	_combo_target = target
	_combo_elapsed = 0.0
	_combo_retry = 0.0
	_combo_pending.assign([&"wolf_bite"])
	_update_combo(0.0)

func _update_combo(delta: float) -> void:
	if _combo_pending.is_empty(): return
	if get_node("Bite").active: return
	if not is_pouncing(): _combo_elapsed += delta
	if not _target_valid(_combo_target) or _combo_elapsed > _module(&"wolf_pounce").data.combo_window:
		for action_id: StringName in _combo_pending: log_event(_module(action_id).name,&"combo_skipped_prediction_miss")
		_combo_pending.clear(); return
	_combo_retry -= delta
	if _combo_retry > 0.0: return
	_combo_retry = 0.05
	for action_id: StringName in _combo_pending.duplicate():
		var module := _module(action_id)
		if module.active or module.cooldown_remaining > 0.0 or not module.enabled or module.data == null or not module.data.enabled:
			_combo_pending.erase(action_id); continue
		var prediction := module.predict(_combo_target,24,0.1)
		if prediction.get("hit",false) and module.start(_combo_target):
			log_event(module.name,&"pounce_combo",prediction)
			_combo_pending.erase(action_id)
			_combo_elapsed = 0.0
			break

func _physics_process(delta: float) -> void:
	if not _ai_allowed() or movement.recovery_control_active or movement._planar_mode_active():
		cancel_action(&"control_disabled"); return
	for module: MODULE in _modules():
		if module.active and (not module.enabled or module.data == null or not module.data.enabled or not _target_valid(module.target)): module.finish(&"disabled_or_target_lost")
		module.tick(delta)
	_update_combo(delta)
	sync_foot_ownership()
	_log_elapsed += delta
	if diagnostic_logging and _log_elapsed >= 0.1 and is_npc_attack_active():
		_log_elapsed = 0.0
		print("[wolf_attack] character=",get_parent().get_path()," modules=",get_attack_diagnostics())

func cancel_npc_attack() -> void: cancel_action(&"npc_cancelled")
func cancel_player_actions() -> void: cancel_action(&"player_control_changed")
func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value: cancel_action(&"character_disabled")

func cancel_action(reason: StringName = &"cancelled") -> void:
	_combo_pending.clear()
	for module: MODULE in _modules(): module.finish(reason)
	sync_foot_ownership()

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): cancel_action(&"removed")

func log_event(module: StringName, event: StringName, details: Dictionary = {}) -> void:
	if diagnostic_logging: print("[wolf_attack] character=",get_parent().get_path()," module=",module," event=",event," details=",details)

func get_attack_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for module: MODULE in _modules(): result.append(module.diagnostics())
	return result
