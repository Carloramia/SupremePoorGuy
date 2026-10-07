extends "res://Scripts/Creatures/NPCStateMachine3D.gd"
## Ground navigation is inherited; autonomous flight prepares an eligible dive approach.
@export_group("Bird Flight Planning")
@export var automatic_takeoff: bool = true
## Legacy Torso-relative preparation height, used when Use Attack Preferences is disabled.
@export_range(0.5, 100.0, 0.5, "or_greater") var attack_altitude: float = 8.0
## Legacy horizontal preparation distance, used when Use Attack Preferences is disabled.
@export_range(0.5, 100.0, 0.5, "or_greater") var approach_distance: float = 8.0
@export_range(0.1, 5.0, 0.1) var altitude_tolerance: float = 0.5
@export_range(0.1, 10.0, 0.1) var obstacle_clearance: float = 2.0
@export_flags_3d_physics var flight_obstacle_mask: int = 1
@export_group("Attack Preference")
## Preferred geometry is measured from the attacking Head to the target Torso.
@export var use_attack_preferences: bool = true
@export_range(0.0, 90.0, 0.5) var preferred_attack_angle_degrees: float = 45.0
@export_range(0.1, 200.0, 0.5, "or_greater") var preferred_attack_distance: float = 20.0
@export_range(0.0, 45.0, 0.5) var attack_angle_tolerance_degrees: float = 10.0
@export_range(0.0, 50.0, 0.1, "or_greater") var attack_distance_tolerance: float = 3.0
## After this time, any legal attack is allowed even if the preferred geometry is unavailable.
@export_range(0.1, 30.0, 0.1, "or_greater") var maximum_preference_wait: float = 6.0
var _preference_elapsed: float = 0.0
var _preference_enemy_id: int = 0
var _flight_goal := Vector3.ZERO
var _route_blocked: bool = false
var _route_frame: int = -1
var _route_hit_cache: Dictionary = {}
var _route_excluded: Array[RID] = []
var _route_enemy_id: int = 0
var _route_own_revision: int = -1
var _route_enemy_revision: int = -1
var _route_mask: int = -1
var _route_queries: int = 0
var _route_cache_hits: int = 0

func _autonomous_flight_allowed() -> bool:
	return enabled and _character_enabled and not _manual_command and _is_enemy(_enemy) and PLAYER_CONTEXT.controlled_character(self) != get_parent()

func _physics_process(delta: float) -> void:
	_sync_preference_target()
	var flight := get_parent().get_node_or_null("BirdFlightController3D")
	if _autonomous_flight_allowed() and flight != null and flight.is_airborne() and current_state != State.ATTACK:
		_preference_elapsed += delta
	else:
		_preference_elapsed = 0.0
	super._physics_process(delta)

func _sync_preference_target() -> void:
	var enemy_id := _enemy.get_instance_id() if _is_enemy(_enemy) else 0
	if enemy_id != _preference_enemy_id:
		_preference_enemy_id = enemy_id
		_preference_elapsed = 0.0

func _attack_head() -> PhysicalBodyPart3D:
	var dive := get_parent().get_node_or_null("BirdDiveAttackController3D")
	if dive != null:
		for head: PhysicalBodyPart3D in dive._heads:
			if is_instance_valid(head) and head.is_inside_tree() and not head.is_broken and not head.is_queued_for_deletion(): return head
	return null

func _effective_attack_preference() -> Vector2:
	var angle := clampf(preferred_attack_angle_degrees, 0.0, 90.0)
	var distance := maxf(preferred_attack_distance, 0.1)
	var dive := get_parent().get_node_or_null("BirdDiveAttackController3D")
	if dive != null and dive.data != null:
		angle = clampf(angle, dive.data.minimum_depression_angle_degrees, dive.data.maximum_depression_angle_degrees)
		distance = clampf(distance, dive.data.minimum_target_distance, dive.data.maximum_target_distance)
	return Vector2(angle, distance)

func _update_attack_goal(target: Node3D) -> void:
	var origin := _get_navigation_origin_position()
	var head := _attack_head()
	var attack_origin := head.global_position if head != null else origin
	var side := -1.0 if attack_origin.x < target.global_position.x else 1.0
	if use_attack_preferences:
		var preference := _effective_attack_preference()
		var angle := deg_to_rad(preference.x)
		var offset := Vector3(side * preference.y * cos(angle), preference.y * sin(angle), 0.0)
		# The Head is offset from the navigation Torso; compensate rather than placing the Torso at the desired Head location.
		_flight_goal = target.global_position + offset - (attack_origin - origin)
	else:
		_flight_goal = target.global_position + Vector3(side * approach_distance, attack_altitude, 0)

func _attack_preference_check(target: Node3D) -> Dictionary:
	var head := _attack_head()
	if head == null or not is_instance_valid(target) or not target.is_inside_tree(): return {"ready":false,"reason":&"no_head_or_target"}
	var difference := target.global_position - head.global_position
	var distance := difference.length()
	var horizontal := difference.slide(Vector3.UP).length()
	var angle := rad_to_deg(atan2(-difference.y, horizontal))
	var preference := _effective_attack_preference()
	var ready := absf(angle - preference.x) <= attack_angle_tolerance_degrees and absf(distance - preference.y) <= attack_distance_tolerance
	return {"ready":ready,"angle_degrees":angle,"distance":distance,"preferred_angle_degrees":preference.x,"preferred_distance":preference.y,"wait_elapsed":_preference_elapsed,"fallback_allowed":_preference_elapsed >= maximum_preference_wait}

func _try_attack(distance: float) -> bool:
	_sync_preference_target()
	if use_attack_preferences and _autonomous_flight_allowed():
		var check := _attack_preference_check(_target)
		if not check.ready and _preference_elapsed < maximum_preference_wait:
			_attack_block_reason = &"approaching_preferred_attack_geometry"
			_attack_retry = maxf(behavior.scan_interval, 0.05)
			return false
	return super._try_attack(distance)

func _plan_attack_distance(distance: float, attacks: Array[ATTACK]) -> bool:
	var flight := get_parent().get_node_or_null("BirdFlightController3D")
	if not _autonomous_flight_allowed() or flight == null or not flight.is_airborne():
		return super._plan_attack_distance(distance, attacks)
	var origin := _get_navigation_origin_position()
	_update_attack_goal(_target)
	_set_agent_target(_flight_goal)
	return origin.distance_to(_flight_goal) > altitude_tolerance

func _flight_route_hit() -> Dictionary:
	var actor := get_parent()
	var enemy_id := _enemy.get_instance_id() if _is_enemy(_enemy) else 0
	var own_revision: int = actor.get_body_parts_revision()
	var enemy_revision: int = _enemy.get_body_parts_revision() if enemy_id != 0 else -1
	var structure_changed := own_revision != _route_own_revision or enemy_revision != _route_enemy_revision or enemy_id != _route_enemy_id
	if structure_changed:
		_route_excluded = actor.get_physical_body_rids()
		if enemy_id != 0: _route_excluded.append_array(_enemy.get_physical_body_rids())
		_route_own_revision = own_revision
		_route_enemy_revision = enemy_revision
		_route_enemy_id = enemy_id
	var frame := Engine.get_physics_frames()
	if _route_frame == frame and not structure_changed and _route_mask == flight_obstacle_mask:
		_route_cache_hits += 1
		return _route_hit_cache
	var origin := _get_navigation_origin_position()
	_route_hit_cache = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, _flight_goal, flight_obstacle_mask, _route_excluded))
	_route_frame = frame
	_route_mask = flight_obstacle_mask
	_route_queries += 1
	return _route_hit_cache

func get_npc_flight_vertical_speed() -> float:
	if not _autonomous_flight_allowed(): return 0.0
	var flight := get_parent().get_node_or_null("BirdFlightController3D")
	var dive := get_parent().get_node_or_null("BirdDiveAttackController3D")
	if flight == null or (dive != null and dive.is_active()): return 0.0
	if not flight.is_airborne(): return flight.ascent_speed if automatic_takeoff else 0.0
	var target := _enemy_torso(_enemy)
	_update_attack_goal(target)
	var target_height := _flight_goal.y
	var hit := _flight_route_hit()
	_route_blocked = not hit.is_empty()
	if _route_blocked: target_height = maxf(target_height, hit.position.y + obstacle_clearance)
	var error := target_height - _get_navigation_origin_position().y
	if absf(error) <= altitude_tolerance: return 0.0
	return clampf(error, -flight.descent_speed, flight.ascent_speed)

func get_movement_direction() -> Vector3:
	var direction := super.get_movement_direction()
	var flight := get_parent().get_node_or_null("BirdFlightController3D")
	if not _autonomous_flight_allowed() or flight == null or not flight.is_airborne() or direction.is_zero_approx(): return direction
	if not _flight_route_hit().is_empty():
		# Use the ground mesh's obstacle detour projected into the flight plane.
		if _navigation_map_is_ready() and not navigation_agent.is_navigation_finished():
			return (navigation_agent.get_next_path_position() - _get_navigation_origin_position()).slide(Vector3.UP).normalized()
		return Vector3.ZERO # Climb first; do not push through an obstacle without a route.
	return direction

func get_state_diagnostics() -> Dictionary:
	var result := super.get_state_diagnostics()
	result["flight_goal"] = _flight_goal
	result["flight_route_blocked"] = _route_blocked
	result["automatic_takeoff"] = automatic_takeoff
	result["flight_route_queries"] = _route_queries
	result["flight_route_cache_hits"] = _route_cache_hits
	result["attack_preference_enabled"] = use_attack_preferences
	result["attack_preference"] = _attack_preference_check(_target) if is_instance_valid(_target) else {}
	return result
