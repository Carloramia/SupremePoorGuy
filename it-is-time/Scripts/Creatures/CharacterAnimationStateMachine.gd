extends AnimationTree

@export var movement_target: Node3D
@export_range(0.0, 10.0, 0.001, "or_greater") var walk_speed_threshold: float = 0.01

var _playback: AnimationNodeStateMachinePlayback
var _previous_position: Vector3
var _current_state: StringName = &"Idle"
var _initialized: bool = false

func _ready() -> void:
	if movement_target == null:
		movement_target = get_parent().get_parent() as Node3D
	if movement_target == null:
		push_error("CharacterAnimationStateMachine requires a Node3D movement target.")
		return
	_playback = get(&"parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback == null:
		push_error("CharacterAnimationStateMachine requires an AnimationNodeStateMachine tree root.")
		return
	_previous_position = movement_target.global_position
	active = true
	_set_state(&"Idle")
	_initialized = true

func _physics_process(delta: float) -> void:
	if not _initialized or delta <= 0.0:
		return
	var current_position := movement_target.global_position
	var movement_speed := current_position.distance_to(_previous_position) / delta
	_previous_position = current_position
	if movement_speed > walk_speed_threshold:
		_set_state(&"Walk")
	else:
		_set_state(&"Idle")

func _set_state(state: StringName) -> void:
	if _playback == null or state == _current_state and _playback.get_current_node() == state:
		return
	_current_state = state
	_playback.travel(state)

func get_current_state() -> StringName:
	return _current_state
