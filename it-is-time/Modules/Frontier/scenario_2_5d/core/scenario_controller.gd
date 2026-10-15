class_name ScenarioController
extends Node3D

signal scenario_initialized()
signal scenario_ready()
signal scenario_exit_requested(reason: StringName)
signal scene_mode_changed(mode: SceneMode.Mode)
signal interactable_hovered(object_id: StringName)
signal interactable_selected(object_id: StringName)
signal interaction_requested(object_id: StringName, definition: InteractableDefinition, runtime_state: InteractableRuntimeState)
signal explore_ground_clicked(world_position: Vector3)
signal combat_ground_clicked(world_position: Vector3)
signal camera_focus_requested(target: Node3D)
@export var definition: SceneDefinition
@export var camera_controller: ScenarioCameraController
@export var interaction_controller: ScenarioInteractionController
@export var occlusion_controller: ScenarioOcclusionController
var scene_mode: SceneMode.Mode = SceneMode.Mode.EXPLORE
var selected_target: Node3D
var initialized: bool = false

func _ready() -> void:
	if not definition:
		push_warning("SceneDefinition missing, using default bounds and camera settings")
		definition = SceneDefinition.new()
	if not camera_controller or not interaction_controller or not occlusion_controller:
		push_error("Scenario controllers must be assigned")
		return
	camera_controller.configure(definition)
	interaction_controller.camera = camera_controller.camera
	occlusion_controller.camera = camera_controller.camera
	interaction_controller.ground_clicked.connect(_ground_clicked)
	interaction_controller.interactable_selected.connect(_selected)
	interaction_controller.interactable_hovered.connect(func(id: StringName) -> void: interactable_hovered.emit(id))
	interaction_controller.interaction_requested.connect(func(id: StringName, data: InteractableDefinition, state: InteractableRuntimeState) -> void: interaction_requested.emit(id, data, state))
	camera_controller.camera_focus_requested.connect(func(target: Node3D) -> void: camera_focus_requested.emit(target))
	for target in get_tree().get_nodes_in_group("scenario_occlusion_target"):
		if is_ancestor_of(target):
			register_occlusion_target(target)
	set_scene_mode(definition.default_scene_mode)
	initialized = true
	scenario_initialized.emit()
	scenario_ready.emit()

func _ground_clicked(world_position: Vector3) -> void:
	if scene_mode == SceneMode.Mode.EXPLORE:
		explore_ground_clicked.emit(world_position)
	else:
		combat_ground_clicked.emit(world_position)

func _selected(object: Interactable3D) -> void:
	if is_instance_valid(selected_target):
		unregister_occlusion_target(selected_target)
		selected_target.queue_free()
	selected_target = null
	if object:
		var marker := Marker3D.new()
		object.add_child(marker)
		marker.position.y = 0.7
		selected_target = marker
		register_occlusion_target(marker)
	interactable_selected.emit(object.definition.object_id if object else &"")

func set_scene_mode(mode: SceneMode.Mode) -> void:
	scene_mode = mode
	# Each mode can replace UI/hover policy externally without adding gameplay here.
	scene_mode_changed.emit(mode)

func get_scene_mode() -> SceneMode.Mode:
	return scene_mode

func set_camera_input_enabled(enabled: bool) -> void:
	camera_controller.set_camera_input_enabled(enabled)

func set_focus_target(target: Node3D) -> void:
	camera_controller.set_focus_target(target)

func focus_on_target() -> void:
	camera_controller.focus_on_target()

func clear_focus_target() -> void:
	camera_controller.clear_focus_target()

func register_occlusion_target(target: Node3D) -> void:
	occlusion_controller.register_occlusion_target(target)

func unregister_occlusion_target(target: Node3D) -> void:
	occlusion_controller.unregister_occlusion_target(target)

func request_scenario_exit(reason: StringName) -> void:
	scenario_exit_requested.emit(reason)
