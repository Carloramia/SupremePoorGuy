extends SceneTree

class QuietPart extends PhysicalBodyPart3D:
	func _spawn_damage_number(_amount: float, _position: Vector3) -> void: pass

var failed := false
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failed = true; push_error(message)

func _initialize() -> void: call_deferred("run")

func part_under(actor: Node3D) -> QuietPart:
	var part := QuietPart.new()
	part.freeze = true
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	part.add_child(sprite)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	part.add_child(shape)
	actor.add_child(part)
	return part

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var audio := root.get_node("CombatAudio") as CombatAudio3D
	check(audio != null and audio.settings != null, "Audio service and default configuration load")
	if audio == null or audio.settings == null: quit(1); return
	var original := audio.settings
	audio.settings = original.duplicate(true)
	check(AudioServer.get_bus_index(&"SFX") >= 0, "Exported SFX bus is available")
	check(audio.settings.cues.size() == 7, "All seven event presets are present")
	for cue: CombatSoundCue in audio.settings.cues:
		check(cue.streams.size() == 2, "Each sound has two variants")
		for stream: AudioStream in cue.streams:
			check(stream is AudioStreamWAV and stream.get_length() > 0.1, "WAV variants are imported and nonempty")
			check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "One-shots must never loop")
	var actor := Node3D.new()
	actor.add_to_group(&"physical_characters_3d")
	root.add_child(actor)
	var first := part_under(actor)
	var second := part_under(actor)
	check(first.apply_damage(0.0) == 0.0 and audio._voices.is_empty(), "Zero damage is silent")
	check(first.apply_damage(2.0) == 2.0 and audio._voices.size() == 1, "Actual HP damage plays a hit")
	second.apply_damage(2.0)
	check(audio._voices.size() == 1, "Compound hits share a character cooldown")
	first.break_part()
	second.break_part()
	check(audio._voices.size() == 2, "Death cascades play one break sound per character")
	first.break_part()
	check(audio._voices.size() == 2, "Repeated Broken calls do not replay")
	audio.stop_all()
	await process_frame
	for cue: CombatSoundCue in audio.settings.cues:
		check(audio.play_cue(cue.event, actor), "Every configured event can play")
	check(audio._voices.size() == 7, "Distinct events have independent cooldowns")
	audio.stop_all()
	await process_frame
	audio.settings.maximum_voices = 1
	check(audio.play_cue(&"stomp", actor), "First voice is admitted")
	check(not audio.play_cue(&"bite", second), "Global voice cap rejects excess playback")
	var voice := audio._voices[0]
	await physics_frame
	await physics_frame
	paused = true
	await process_frame
	check(voice.stream_paused, "Existing audio pauses with the battle")
	check(not audio.play_cue(&"hit", actor), "Paused battles do not start sounds")
	paused = false
	await process_frame
	check(not voice.stream_paused, "Audio resumes with the battle")
	audio.stop_all()
	await process_frame
	audio.settings.maximum_voices = 24
	audio.settings.enabled = false
	check(not audio.play_cue(&"attack", actor), "Settings disable all new playback")
	audio.settings.enabled = true
	check(not audio.play_cue(&"unknown", actor), "Unknown events are silent")
	check(not audio.play_cue(&"attack", actor, Vector3(NAN, 0, 0)), "Reject invalid positions")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.audio_listener_enable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.make_current()
	var source := Node3D.new()
	viewport.add_child(source)
	var listener := AudioListener3D.new()
	viewport.add_child(listener)
	listener.make_current()
	var capture := AudioEffectCapture.new()
	var bus := AudioServer.get_bus_index(&"SFX")
	var effect_index := AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus, capture)
	check(CombatAudio3D.play_at(source, &"attack", Vector3(2, 3, 4)), "Independent battle worlds play sounds")
	var world_voice := audio._voices[-1]
	check(world_voice.get_viewport() == viewport and world_voice.get_world_3d() == source.get_world_3d(), "Sound stays in its emitter's World3D")
	check(world_voice.global_position.is_equal_approx(Vector3(2, 3, 4)), "Contact position is used")
	await create_timer(0.15).timeout
	var mixed := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for frame: Vector2 in mixed: peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	check(peak > 0.001, "Spatial playback produces a non-silent SFX mix")
	print("COMBAT_AUDIO_MIX frames=", mixed.size(), " peak=", peak)
	audio.stop_all()
	await process_frame
	capture.clear_buffer()
	var attack := audio.settings.cues[0]
	attack.minimum_pitch = 1.0
	attack.maximum_pitch = 1.0
	attack.streams.assign([attack.streams[0]])
	var burst_sources: Array[Node3D] = []
	for index: int in 24:
		var emitter := Node3D.new()
		viewport.add_child(emitter)
		burst_sources.append(emitter)
		audio.play_cue(&"attack", emitter)
	check(audio._voices.size() == 24, "The configured mixed-battle voice budget is enforced")
	await create_timer(0.15).timeout
	mixed = capture.get_buffer(capture.get_frames_available())
	peak = 0.0
	for frame: Vector2 in mixed: peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	check(peak > 0.001 and peak <= db_to_linear(-1.0) + 0.002, "The SFX limiter controls simultaneous impact peaks")
	print("COMBAT_AUDIO_BURST voices=24 peak=", peak)
	for emitter: Node3D in burst_sources: emitter.queue_free()
	AudioServer.remove_bus_effect(bus, effect_index)
	source.queue_free()
	await process_frame
	check(audio._voices.is_empty(), "Removing an emitter releases its voices")
	check(audio.play_cue(&"attack", actor), "A short sound starts for completion checking")
	await create_timer(0.8).timeout
	await process_frame
	check(audio._voices.is_empty(), "Finished one-shots release their playback nodes")
	viewport.queue_free()
	actor.queue_free()
	audio.settings = original
	await process_frame
	print("COMBAT_AUDIO_", "FAILED" if failed else "PASSED", " checks=", checks)
	quit(1 if failed else 0)
