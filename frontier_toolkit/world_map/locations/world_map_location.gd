@tool
class_name WorldMapLocation
extends Node2D

@export var location_id: StringName = &""
@export var definition: LocationDefinition
@export var interaction_offset: Vector2 = Vector2(0, 35)
@export var discovery_radius: float = -1.0
@export var interaction_radius: float = -1.0
@export var completion_behavior_override: int = -1
var state: LocationRuntimeState = LocationRuntimeState.new()
var currently_visible: bool = true
var show_debug: bool = false
var default_discovery: float = 240.0
var default_interaction: float = 42.0

func interaction_point() -> Vector2:
	return to_global(interaction_offset)

func effective_discovery_radius() -> float:
	return discovery_radius if discovery_radius >= 0 else default_discovery

func effective_interaction_radius() -> float:
	return interaction_radius if interaction_radius >= 0 else default_interaction

func completion_behavior() -> int:
	return completion_behavior_override if completion_behavior_override >= 0 else int(definition.completion_behavior)

func is_active() -> bool:
	return state.lifecycle in [LocationRuntimeState.Lifecycle.AVAILABLE, LocationRuntimeState.Lifecycle.COMPLETED]

func can_interact() -> bool:
	return state.lifecycle == LocationRuntimeState.Lifecycle.AVAILABLE or (definition.repeatable and is_active())

func refresh_marker() -> void:
	visible = state.discovered and is_active()
	modulate.a = 1.0 if currently_visible else 0.55
	queue_redraw()

func _draw() -> void:
	if not definition:
		return
	var color := definition.marker_color
	draw_circle(Vector2.ZERO, 24, Color("142833"))
	draw_arc(Vector2.ZERO, 24, 0, TAU, 32, color, 2)
	if definition.icon:
		draw_texture_rect(definition.icon, Rect2(-16, -16, 32, 32), false)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(-8, 8), definition.marker_glyph, HORIZONTAL_ALIGNMENT_CENTER, 20, 23, color)
	if state.lifecycle == LocationRuntimeState.Lifecycle.COMPLETED:
		draw_circle(Vector2(18, -18), 7, Color("9dbf95"))
	if show_debug or Engine.is_editor_hint():
		draw_circle(interaction_offset, 5, Color("52d3ce"))
		draw_arc(interaction_offset, effective_interaction_radius(), 0, TAU, 48, Color(0.4, 0.9, 0.9, 0.4), 1)
		draw_arc(Vector2.ZERO, effective_discovery_radius(), 0, TAU, 64, Color(0.9, 0.8, 0.3, 0.2), 1)
