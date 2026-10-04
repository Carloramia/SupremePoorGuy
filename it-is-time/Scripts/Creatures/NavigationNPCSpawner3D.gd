extends Node3D

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

@export_group("Activation")
## Stops spawning and navigation sampling; existing NPCs remain in the level.
@export var spawn_enabled: bool = true:
	set(value):
		if spawn_enabled == value: return
		spawn_enabled = value
		if not is_instance_valid(_spawn_timer) or not _spawn_timer.is_inside_tree(): return
		if value:
			_spawn_timer.start(maxf(initial_delay, 0.001))
		else:
			_spawn_timer.stop()

@export_group("Spawn")
@export var npc_scene: PackedScene = preload("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn")
@export_range(0.1, 3600.0, 0.1, "or_greater") var spawn_interval: float = 8.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var initial_delay: float = 2.0
@export_range(1, 1000, 1, "or_greater") var maximum_npc_count: int = 10
@export_range(0.0, 100.0, 0.1, "or_greater") var spawn_height: float = 5.0
@export var spawn_parent_path: NodePath = NodePath("../Flat")

@export_group("Navigation Sampling")
@export var navigation_region_path: NodePath = NodePath("../NavigationRegion3D")
@export var target_group: StringName = &"npc_navigation_target"
@export_flags_3d_navigation var navigation_layers: int = 1
@export_range(1, 128, 1) var maximum_sample_attempts: int = 24
@export_range(0.0, 1000.0, 0.1, "or_greater") var minimum_target_distance: float = 12.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var maximum_target_distance: float = 80.0
@export_range(0.01, 10.0, 0.01, "or_greater") var path_endpoint_tolerance: float = 1.0

var _spawn_timer: Timer
var _spawned_npcs: Array[Node3D] = []

func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.name = "SpawnTimer"
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)
	if spawn_enabled:
		_spawn_timer.start(maxf(initial_delay, 0.001))

func _on_spawn_timer_timeout() -> void:
	if not spawn_enabled: return
	_spawn_timer.wait_time = spawn_interval
	try_spawn_npc()

func try_spawn_npc() -> Node3D:
	if not spawn_enabled: return null
	_remove_invalid_npcs()
	if _spawned_npcs.size() >= maximum_npc_count or npc_scene == null:
		return null
	var region := get_node_or_null(navigation_region_path) as NavigationRegion3D
	var spawn_parent := get_node_or_null(spawn_parent_path) as Node3D
	var target := PLAYER_CONTEXT.anchor(self) if PLAYER_CONTEXT.controller(self) != null else get_tree().get_first_node_in_group(target_group) as Node3D
	if not is_instance_valid(region) or not is_instance_valid(spawn_parent) or not is_instance_valid(target):
		return null
	var navigation_map: RID = region.get_navigation_map()
	if not navigation_map.is_valid() or NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return null
	var target_navigation_point: Vector3 = NavigationServer3D.map_get_closest_point(
		navigation_map,
		target.global_position
	)
	var spawn_navigation_point: Variant = _find_reachable_spawn_point(
		navigation_map,
		target_navigation_point
	)
	if spawn_navigation_point == null:
		return null
	var npc := npc_scene.instantiate() as Node3D
	if npc == null:
		return null
	spawn_parent.add_child(npc)
	npc.global_position = spawn_navigation_point + Vector3.UP * spawn_height
	_spawned_npcs.append(npc)
	return npc

func _find_reachable_spawn_point(navigation_map: RID, target_point: Vector3) -> Variant:
	for _attempt: int in range(maximum_sample_attempts):
		var candidate: Vector3 = NavigationServer3D.map_get_random_point(
			navigation_map,
			navigation_layers,
			true
		)
		var horizontal_offset: Vector3 = candidate - target_point
		horizontal_offset.y = 0.0
		var distance: float = horizontal_offset.length()
		if distance < minimum_target_distance:
			continue
		if maximum_target_distance > 0.0 and distance > maximum_target_distance:
			continue
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			navigation_map,
			candidate,
			target_point,
			true,
			navigation_layers
		)
		if path.size() < 2:
			continue
		if path[path.size() - 1].distance_to(target_point) > path_endpoint_tolerance:
			continue
		return candidate
	return null

func _remove_invalid_npcs() -> void:
	for index: int in range(_spawned_npcs.size() - 1, -1, -1):
		if not is_instance_valid(_spawned_npcs[index]):
			_spawned_npcs.remove_at(index)

func get_spawned_npc_count() -> int:
	_remove_invalid_npcs()
	return _spawned_npcs.size()
