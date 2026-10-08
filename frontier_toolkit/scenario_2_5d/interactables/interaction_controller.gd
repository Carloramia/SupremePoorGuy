class_name ScenarioInteractionController
extends Node

signal interactable_hovered(object_id: StringName)
signal interactable_selected(object: Interactable3D)
signal interaction_requested(object_id: StringName, definition: InteractableDefinition, runtime_state: InteractableRuntimeState)
signal ground_clicked(position: Vector3)
@export var camera: Camera3D
@export_flags_3d_physics var pick_mask: int = 1
@export var ray_length: float = 200.0
var hovered: Interactable3D
var selected: Interactable3D
var hover_enabled: bool = true

func raycast(screen: Vector2) -> Dictionary:
	if not is_instance_valid(camera):
		return {}
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * ray_length, pick_mask)
	query.collide_with_areas = true
	return camera.get_world_3d().direct_space_state.intersect_ray(query)

func _physics_process(_delta: float) -> void:
	var next: Interactable3D = null
	if hover_enabled and get_viewport().gui_get_hovered_control() == null:
		var hit := raycast(get_viewport().get_mouse_position())
		if hit and hit.collider is Interactable3D and hit.collider.is_enabled():
			next = hit.collider
	if next != hovered:
		if is_instance_valid(hovered):
			hovered.set_hovered(false)
		hovered = next
		if hovered:
			hovered.set_hovered(true)
		interactable_hovered.emit(hovered.definition.object_id if hovered else &"")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		click_at(event.position)
		get_viewport().set_input_as_handled()

func click_at(screen: Vector2) -> void:
	var hit := raycast(screen)
	if not hit:
		select_object(null)
		return
	if hit.collider is Interactable3D:
		if hit.collider.is_enabled():
			select_object(hit.collider)
		return # Disabled interactables still block click-through.
	select_object(null)
	if hit.collider.is_in_group("scenario_ground"):
		ground_clicked.emit(hit.position)

func select_object(object: Interactable3D) -> void:
	if is_instance_valid(selected):
		selected.set_selected(false)
	selected = object
	if selected:
		selected.set_selected(true)
		if not selected.interaction_requested.is_connected(_forward_request):
			selected.interaction_requested.connect(_forward_request)
	interactable_selected.emit(selected)

func _forward_request(id: StringName, definition: InteractableDefinition, state: InteractableRuntimeState) -> void:
	interaction_requested.emit(id, definition, state)
