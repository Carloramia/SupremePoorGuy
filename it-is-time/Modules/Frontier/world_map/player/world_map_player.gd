class_name WorldMapPlayer
extends CharacterBody2D

signal movement_started(target_position: Vector2)
signal movement_cancelled(reason: String)
signal movement_paused(reason: String)
signal movement_resumed
signal movement_finished(position: Vector2)

@export var base_speed: float = 165.0
@export var visual_scene: PackedScene
var navigation: WorldMapNavigation
var agent: NavigationAgent2D
var movement_target: Vector2
var has_target: bool = false
var paused: bool = false
var map_paused: bool = false
var speed_areas: Array[WorldMapSpeedArea] = []
var path_line: Line2D
var target_marker: Node2D
var movement_route: PackedVector2Array = PackedVector2Array()
var route_index: int = 0

func _ready() -> void:
	agent = NavigationAgent2D.new()
	agent.path_desired_distance = 5.0
	agent.target_desired_distance = 3.0
	add_child(agent)
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	if visual_scene:
		add_child(visual_scene.instantiate())
	path_line = Line2D.new()
	path_line.top_level = true
	path_line.width = 3.0
	path_line.default_color = Color("edca81")
	path_line.z_index = 7
	add_child(path_line)
	target_marker = Node2D.new()
	target_marker.top_level = true
	target_marker.z_index = 8
	target_marker.draw.connect(func() -> void:
		target_marker.draw_arc(Vector2.ZERO, 13, 0, TAU, 32, Color("edca81"), 2.0)
		target_marker.draw_circle(Vector2.ZERO, 3, Color("edca81")))
	add_child(target_marker)
	target_marker.hide()
	z_index = 8

func _draw() -> void:
	if not visual_scene:
		draw_circle(Vector2(0, 4), 13, Color(0, 0, 0, 0.3))
		draw_circle(Vector2.ZERO, 10, Color("f2dfb6"))
		draw_arc(Vector2.ZERO, 14, 0, TAU, 32, Color("52d3ce"), 2)
		draw_line(Vector2(-4, -2), Vector2(4, -2), Color("234751"), 2)

func set_move_target(destination: Vector2) -> bool:
	if map_paused or navigation == null:
		return false
	var path := navigation.legal_path(global_position, destination)
	if path.is_empty():
		return false
	cancel_movement("new target")
	movement_target = destination
	has_target = true
	paused = false
	agent.target_position = destination
	path_line.points = path
	target_marker.global_position = destination
	target_marker.show()
	target_marker.queue_redraw()
	movement_started.emit(destination)
	return true

func set_move_route(route: PackedVector2Array) -> bool:
	if map_paused or navigation == null or route.is_empty() or route[0].distance_to(global_position) > 0.1:
		return false
	for index in range(route.size() - 1):
		if not navigation.is_segment_walkable(route[index], route[index + 1]):
			return false
	cancel_movement("new road route")
	movement_route = route.duplicate()
	route_index = 1
	movement_target = route[-1]
	has_target = true
	agent.target_position = route[mini(route_index, route.size() - 1)]
	path_line.points = movement_route
	target_marker.global_position = movement_target
	target_marker.show()
	target_marker.queue_redraw()
	movement_started.emit(movement_target)
	return true

func _physics_process(delta: float) -> void:
	if paused or map_paused or not has_target:
		velocity = Vector2.ZERO
		return
	if not movement_route.is_empty():
		_follow_route(delta)
		return
	if agent.is_navigation_finished():
		_finish_movement()
		return
	var next := agent.get_next_path_position()
	var offset := next - global_position
	var speed := effective_speed()
	velocity = offset.normalized() * minf(speed, offset.length() / maxf(delta, 0.001))
	var candidate := global_position + velocity * delta
	if not navigation.definition.contains(navigation.to_local(candidate)):
		cancel_movement("map bounds")
		return
	move_and_slide()
	var actual := agent.get_current_navigation_path()
	if not actual.is_empty():
		var remaining := PackedVector2Array([global_position])
		for index in range(agent.get_current_navigation_path_index(), actual.size()):
			remaining.append(actual[index])
		path_line.points = remaining

func _follow_route(delta: float) -> void:
	# Reach each bend exactly before advancing, avoiding NavigationAgent corner cutting.
	while route_index < movement_route.size() and global_position.distance_to(movement_route[route_index]) <= 0.01:
		route_index += 1
		if route_index < movement_route.size():
			agent.target_position = movement_route[route_index]
	if route_index >= movement_route.size():
		_finish_movement()
		return
	agent.get_next_path_position()
	var offset := movement_route[route_index] - global_position
	velocity = offset.normalized() * minf(effective_speed(), offset.length() / maxf(delta, 0.001))
	if not navigation.definition.contains(navigation.to_local(global_position + velocity * delta)):
		cancel_movement("map bounds")
		return
	move_and_slide()
	var remaining := PackedVector2Array([global_position])
	for index in range(route_index, movement_route.size()):
		remaining.append(movement_route[index])
	path_line.points = remaining

func _finish_movement() -> void:
	has_target = false
	velocity = Vector2.ZERO
	movement_route.clear()
	route_index = 0
	_clear_visuals()
	movement_finished.emit(global_position)

func effective_speed() -> float:
	var selected: WorldMapSpeedArea = null
	for area in speed_areas:
		if is_instance_valid(area) and (selected == null or area.priority > selected.priority or (area.priority == selected.priority and String(area.name) < String(selected.name))):
			selected = area
	return base_speed * (selected.speed_multiplier if selected else 1.0)

func pause_movement(reason: String = "external") -> void:
	paused = true
	velocity = Vector2.ZERO
	movement_paused.emit(reason)

func resume_movement() -> void:
	paused = false
	movement_resumed.emit()

func cancel_movement(reason: String = "external") -> void:
	has_target = false
	movement_route.clear()
	route_index = 0
	paused = false
	velocity = Vector2.ZERO
	if agent:
		agent.target_position = global_position
	_clear_visuals()
	movement_cancelled.emit(reason)

func _clear_visuals() -> void:
	if path_line:
		path_line.clear_points()
	if target_marker:
		target_marker.hide()
