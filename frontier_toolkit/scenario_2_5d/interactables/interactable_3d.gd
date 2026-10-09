class_name Interactable3D
extends StaticBody3D

signal interaction_requested(object_id: StringName, definition: InteractableDefinition, runtime_state: InteractableRuntimeState)
signal hovered_changed(value: bool)
signal selected_changed(value: bool)
@export var definition: InteractableDefinition
@export var runtime_state: InteractableRuntimeState
@export var visual: BillboardVisual3D
var hovered: bool = false

func _ready() -> void:
	if not definition:
		push_warning("InteractableDefinition missing: interaction disabled")
	if runtime_state:
		runtime_state = runtime_state.duplicate(true)
	else:
		runtime_state = InteractableRuntimeState.new()
	runtime_state.selected = false

func is_enabled() -> bool:
	return definition != null and runtime_state != null and runtime_state.enabled

func set_hovered(value: bool) -> void:
	hovered = value and is_enabled()
	hovered_changed.emit(hovered)
	_update_feedback()

func set_selected(value: bool) -> void:
	runtime_state.selected = value and is_enabled()
	selected_changed.emit(runtime_state.selected)
	_update_feedback()

func _update_feedback() -> void:
	if visual:
		visual.set_tint(Color(1.3, 1.12, 0.7) if runtime_state.selected else (Color(1.12, 1.18, 1.08) if hovered else Color.WHITE))

func request_interaction() -> void:
	if is_enabled():
		interaction_requested.emit(definition.object_id, definition, runtime_state)
