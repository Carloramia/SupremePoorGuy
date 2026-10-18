class_name CombatAudio3D
extends Node

const CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")
@export var settings: CombatAudioSettings
var _voices: Array[AudioStreamPlayer3D] = []
var _last_played: Dictionary = {}
var _rng := RandomNumberGenerator.new()

static func play_at(emitter: Node, event: StringName, point: Vector3 = Vector3.INF) -> bool:
	if Engine.is_editor_hint() or not is_instance_valid(emitter) or not emitter.is_inside_tree(): return false
	var service := emitter.get_node_or_null("/root/CombatAudio") as CombatAudio3D
	return service.play_cue(event, emitter, point) if service != null else false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	# Editor class discovery happens before WAV import on a fresh checkout.
	if settings == null: settings = load("res://Resources/Audio/CombatAudio.tres")

func play_cue(event: StringName, emitter: Node, point: Vector3 = Vector3.INF) -> bool:
	if settings == null or not settings.enabled or get_tree().paused: return false
	if not is_instance_valid(emitter) or not emitter.is_inside_tree() or emitter.is_queued_for_deletion(): return false
	var spatial := emitter
	while spatial != null and not spatial is Node3D: spatial = spatial.get_parent()
	if spatial == null: return false
	var cue: CombatSoundCue
	for candidate: CombatSoundCue in settings.cues:
		if candidate != null and candidate.event == event: cue = candidate; break
	if cue == null or cue.streams.is_empty(): return false
	var location: Vector3 = spatial.global_position if point == Vector3.INF else point
	if not location.is_finite(): return false
	var actor := CONTEXT.character_of(emitter)
	var scope: Node = actor if actor != null else spatial
	var key := "%s:%s" % [scope.get_instance_id(), event]
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_last_played.get(key, -100.0)) < cue.cooldown: return false
	_voices = _voices.filter(func(voice): return is_instance_valid(voice) and not voice.is_queued_for_deletion())
	if _voices.size() >= maxi(settings.maximum_voices, 1): return false
	var stream: AudioStream = cue.streams[_rng.randi_range(0, cue.streams.size() - 1)]
	if stream == null: return false
	var voice := AudioStreamPlayer3D.new()
	voice.name = "CombatSFX_" + str(event)
	voice.stream = stream
	voice.bus = &"SFX"
	voice.volume_db = settings.volume_db + cue.volume_db
	voice.max_db = minf(voice.volume_db, 0.0)
	voice.pitch_scale = _rng.randf_range(maxf(cue.minimum_pitch, 0.01), maxf(cue.maximum_pitch, cue.minimum_pitch))
	voice.unit_size = maxf(settings.unit_size, 0.01)
	voice.max_distance = maxf(settings.maximum_distance, 1.0)
	voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	voice.top_level = true
	# Keep the emitter's World3D and lifetime, including independent battle SubViewports.
	spatial.add_child(voice)
	voice.global_position = location
	voice.finished.connect(voice.queue_free)
	voice.tree_exiting.connect(_forget_voice.bind(voice))
	_voices.append(voice)
	_last_played[key] = now
	if _last_played.size() > 128:
		for old_key: String in _last_played.keys():
			if now - float(_last_played[old_key]) > 2.0: _last_played.erase(old_key)
	voice.play()
	return true

func _forget_voice(voice: AudioStreamPlayer3D) -> void:
	_voices.erase(voice)

func _notification(what: int) -> void:
	if what != NOTIFICATION_PAUSED and what != NOTIFICATION_UNPAUSED: return
	for voice: AudioStreamPlayer3D in _voices:
		if is_instance_valid(voice): voice.stream_paused = what == NOTIFICATION_PAUSED

func stop_all() -> void:
	for voice: AudioStreamPlayer3D in _voices.duplicate():
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	_voices.clear()
	_last_played.clear()
