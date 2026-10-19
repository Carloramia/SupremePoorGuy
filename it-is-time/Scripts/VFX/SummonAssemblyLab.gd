extends Node3D
## Standalone F6 test harness; does not alter GameRoot or summon inventory.
const CHARACTER_DIR := "res://Scenes/Creatures/Characters/"
const CATALOG := [
	["灰狼", "Generate_Wolf.tscn"], ["蛇兽", "Generate_Snake.tscn"],
	["角兽", "Generate_HornedBeast.tscn"], ["树桩兽", "Generate_StumpBeast.tscn"],
	["蜘蛛", "Generate_Spider.tscn"], ["人形", "Generate_Human.tscn"],
]
@export var auto_play := true
@export var default_template: Resource = preload("res://Resources/VFX/SummonAssembly_Default.tres")
@export var quick_template: Resource = preload("res://Resources/VFX/SummonAssembly_Quick.tres")
@onready var effect = $SummonAssembly3D
@onready var controls := $UI/Settings/Margin/Controls
@onready var count_input: SpinBox = controls.get_node("Count/Value")
@onready var size_input: SpinBox = controls.get_node("Size/Value")
@onready var seed_input: SpinBox = controls.get_node("Seed/Value")
@onready var species: OptionButton = controls.get_node("Species")
@onready var status: Label = $UI/Bottom/Margin/Info/Status
@onready var timeline: HSlider = $UI/Bottom/Margin/Info/Timeline
var _updating := false
var _has_played := false
var _landed_count := 0
var _finish_count := 0
var _loop_delay := -1.0
var _selected := -1
var _selection_entries: Array[Dictionary] = []
var _hovered: Array[int] = []
var _ring_material: StandardMaterial3D
var _draws_played := 0
var _last_pace := -1
var _pace_label := "标准演出"

func _ready() -> void:
	# This standalone lab has its own UI design size; do not change project.godot.
	get_window().content_scale_size = Vector2i(1440, 900)
	get_window().title = "涌现 · 召唤演出 / 全程 4 秒"
	_ring_material = $SummonRing.mesh.material.duplicate() as StandardMaterial3D
	$SummonRing.material_override = _ring_material
	species.add_item("混合怪物（依次使用全部素材）")
	for entry: Array in CATALOG:
		species.add_item(entry[0])
	_apply_template()
	var pacing: OptionButton = controls.get_node("Pacing")
	pacing.add_item("标准演出（4秒）")
	pacing.add_item("紧凑回拢（4秒）")
	pacing.add_item("自动分配内部节奏（均为4秒）")
	pacing.select(2)
	pacing.item_selected.connect(_pace_setting_changed)
	for key: String in ["Burst", "Spread", "LandingPause", "Attraction", "Speed"]:
		controls.get_node(key).value_changed.connect(func(_value: float): _refresh_parameter_labels())
	controls.get_node("PresetGiant").pressed.connect(func(): preset(2, size_input.value))
	controls.get_node("PresetNormal").pressed.connect(func(): preset(5, size_input.value))
	controls.get_node("PresetSmall").pressed.connect(func(): preset(12, size_input.value))
	controls.get_node("PresetCrowd").pressed.connect(func(): preset(20, size_input.value))
	controls.get_node("Play").pressed.connect(play)
	controls.get_node("Replay").pressed.connect(func(): play(true))
	controls.get_node("Reroll").pressed.connect(func(): seed_input.value += 1; play())
	controls.get_node("Pause").pressed.connect(toggle_pause)
	controls.get_node("Actions/Skip").pressed.connect(func(): effect.skip())
	controls.get_node("Actions/Clear").pressed.connect(clear)
	controls.get_node("Speed").value_changed.connect(func(value: float): effect.playback_speed = value)
	size_input.value_changed.connect(_size_changed)
	controls.get_node("AutoCount").toggled.connect(func(enabled: bool):
		if enabled: _size_changed(size_input.value))
	count_input.value_changed.connect(func(_value: float):
		if not _updating: controls.get_node("AutoCount").set_pressed_no_signal(false))
	timeline.drag_started.connect(func(): effect.paused = true)
	timeline.value_changed.connect(func(value: float):
		if not _updating and not effect.fragments.is_empty(): effect.seek(value))
	effect.part_landed.connect(func(_index: int, _path: String): _landed_count += 1)
	effect.batch_finished.connect(func(_roots: Array[Node3D]):
		_finish_count += 1
		if controls.get_node("Loop").button_pressed: _loop_delay = 1.5)
	# Optional deterministic capture/verification arguments are used by our test script.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--count="): count_input.value = int(arg.trim_prefix("--count="))
		if arg.begins_with("--height="): size_input.value = float(arg.trim_prefix("--height="))
	if auto_play:
		play.call_deferred()

func _apply_template() -> void:
	_updating = true
	count_input.value = default_template.count
	size_input.value = default_template.height
	seed_input.value = default_template.random_seed
	controls.get_node("AutoCount").set_pressed_no_signal(false)
	controls.get_node("Burst").value = default_template.burst_height
	controls.get_node("Spread").value = default_template.scatter_radius
	controls.get_node("LandingPause").value = default_template.landing_pause
	controls.get_node("Attraction").value = default_template.landing_to_assembly_duration - default_template.landing_pause
	controls.get_node("Speed").value = default_template.playback_speed
	effect.landing_pause = default_template.landing_pause
	effect.total_duration = default_template.total_duration
	effect.acceleration_power = default_template.acceleration_power
	effect.layout_width = default_template.layout_width
	effect.layout_depth = default_template.layout_depth
	effect.max_row_spacing = default_template.max_row_spacing
	effect.scatter_center_bias = default_template.scatter_center_bias
	for property: String in ["anticipation_duration", "flight_duration", "launch_window", "absorption_arc_height"]:
		effect.set(property, default_template.get(property))
	for property: String in ["assembly_height", "assembly_height_variation", "drop_duration", "landing_stagger", "landing_sequence_window", "first_bounce_height", "second_bounce_height", "first_bounce_duration", "second_bounce_duration"]:
		effect.set(property, default_template.get(property))
	_updating = false
	_refresh_parameter_labels()

func _refresh_parameter_labels() -> void:
	controls.get_node("BurstLabel").text = "喷射高度：%.2f" % controls.get_node("Burst").value
	controls.get_node("SpreadLabel").text = "随机散布半径：%.2f" % controls.get_node("Spread").value
	controls.get_node("LandingPauseLabel").text = "停顿分配：%.2f（按4秒换算）" % controls.get_node("LandingPause").value
	controls.get_node("AttractionLabel").text = "吸附分配：%.2f（从慢到快）" % controls.get_node("Attraction").value
	controls.get_node("SpeedLabel").text = "播放速度：%.1f 倍" % controls.get_node("Speed").value

func _pace_setting_changed(_index: int) -> void:
	_last_pace = -1 # Apply the chosen mode on next play, not midway through a take.

func _choose_pace(replay: bool) -> void:
	var setting: int = controls.get_node("Pacing").selected
	var next := 1 if setting == 1 or (setting == 2 and _draws_played > 0) else 0
	if replay and _last_pace >= 0: next = _last_pace
	if next != _last_pace:
		var template: Resource = quick_template if next == 1 else default_template
		for property: String in ["anticipation_duration", "flight_duration", "launch_window", "absorption_arc_height", "drop_duration", "landing_stagger", "landing_sequence_window", "first_bounce_height", "second_bounce_height", "first_bounce_duration", "second_bounce_duration"]:
			effect.set(property, template.get(property))
		controls.get_node("LandingPause").value = template.landing_pause
		controls.get_node("Attraction").value = template.landing_to_assembly_duration - template.landing_pause
	_last_pace = next
	_pace_label = "紧凑回拢" if next == 1 else "标准演出"
	if not replay: _draws_played += 1

func preset(count: int, height: float) -> void:
	_updating = true
	controls.get_node("AutoCount").set_pressed_no_signal(false)
	size_input.value = height
	count_input.value = count
	_updating = false
	play(true)

func _size_changed(height: float) -> void:
	if _updating or not controls.get_node("AutoCount").button_pressed:
		return
	_updating = true
	count_input.value = clampi(roundi(5.0 * pow(3.2 / height, 1.15)), 1, 24)
	_updating = false

func play(replay: bool = false) -> void:
	_choose_pace(replay)
	_loop_delay = -1.0
	_landed_count = 0
	_finish_count = 0
	_selected = -1
	effect.random_seed = int(seed_input.value)
	effect.burst_height = controls.get_node("Burst").value
	var spread: float = controls.get_node("Spread").value
	effect.scatter_half_extents = Vector2(spread, spread)
	effect.landing_pause = controls.get_node("LandingPause").value
	effect.attraction_duration = controls.get_node("Attraction").value + effect.landing_pause
	effect.playback_speed = controls.get_node("Speed").value
	var requests: Array[Dictionary] = []
	for i: int in int(count_input.value):
		var index := i % CATALOG.size() if species.selected == 0 else species.selected - 1
		requests.append({"scene": CHARACTER_DIR + CATALOG[index][1], "height": size_input.value, "id": i})
	_has_played = effect.play_batch(requests)
	controls.get_node("Pause").text = "暂停 / 继续  [空格]"
	if not _has_played:
		status.text = effect.load_error
		push_error(effect.load_error)

func toggle_pause() -> void:
	effect.paused = not effect.paused
	if not effect.running and effect.elapsed < effect.duration:
		effect.running = true
	controls.get_node("Pause").text = "继续播放  [空格]" if effect.paused else "暂停 / 继续  [空格]"

func clear() -> void:
	_loop_delay = -1.0
	effect.clear()
	_has_played = false
	_selected = -1
	_selection_entries.clear()
	_hovered.clear()
	$UI/SelectionOverlay.entries = []
	$UI/SelectionOverlay.accents = []
	$UI/SelectionOverlay.queue_redraw()
	$SummonRing.scale = Vector3.ONE
	_ring_material.albedo_color = Color(0.38, 0.74, 0.69, 0.35)
	status.text = "已清空。选择数量与体型，开始测试。"
	_updating = true
	timeline.value = 0
	_updating = false

func _process(delta: float) -> void:
	if _loop_delay >= 0.0:
		_loop_delay -= delta
		if _loop_delay < 0.0: play(true)
	if not _has_played: return
	var stats: Dictionary = effect.statistics()
	_updating = true
	timeline.max_value = maxf(stats.duration, 0.01)
	timeline.value = stats.time
	_updating = false
	status.text = "%d只 / %d部件  飞行%d 停%d 吸%d  成形%d 落地中%d 稳定%d  %.2f / %.2fs  %.0f FPS" % [
		stats.units, stats.parts, stats.airborne, stats.resting, stats.attracting, stats.assembled, stats.settling, stats.settled,
		stats.time, stats.duration, Engine.get_frames_per_second()]
	_update_selection()
	_update_animation_feedback(stats)
	$UI/Header/Subtitle.text = "全程4秒 · %s · 各自停 %.2fs / 吸附 %.2fs · Enter 跳过" % [_pace_label, effect.landing_pause * effect.presentation_scale(), (effect.attraction_duration - effect.landing_pause) * effect.presentation_scale()]

func _update_animation_feedback(stats: Dictionary) -> void:
	var time: float = effect.animation_time()
	var lead: float = maxf(effect.anticipation_duration, 0.01)
	var scale_value := 1.0
	var alpha := 0.35
	if time < lead:
		var p := time / lead
		scale_value = 1.0 - 0.05 * p
		alpha = lerpf(0.35, 0.85, p)
	elif time < lead + 0.32:
		var p := (time - lead) / 0.32
		scale_value = 0.95 + 0.14 * sin(p * PI)
		alpha = lerpf(0.85, 0.4, p)
	elif stats.attracting > 0:
		alpha = 0.4 + 0.12 * float(stats.attracting) / maxf(stats.parts, 1)
	$SummonRing.scale = Vector3(scale_value, 1, scale_value)
	_ring_material.albedo_color = Color(0.38, 0.74, 0.69, alpha)
	var accents: Array[Dictionary] = []
	var camera := $Camera3D as Camera3D
	for unit: Dictionary in effect.units:
		var join_age := time - float(unit.assembly_end)
		if join_age >= 0.0 and join_age < 0.14:
			var center: Vector3 = unit.ground + unit.root.position + Vector3.UP * (float(unit.height) * 0.4)
			accents.append({"kind": "join", "center": camera.unproject_position(center),
				"radius": 12.0 + join_age * 24, "strength": (1.0 - join_age / 0.14) * 0.7})
		var contact_age := time - float(unit.impact_at)
		if contact_age >= 0.0 and contact_age < 0.18:
			accents.append({"kind": "contact", "center": camera.unproject_position(unit.ground),
				"radius": 7.0 + contact_age * 75, "strength": (1.0 - contact_age / 0.18) * 0.55})
	$UI/SelectionOverlay.accents = accents
	$UI/SelectionOverlay.queue_redraw()

func _update_selection() -> void:
	_selection_entries.clear()
	_hovered.clear()
	var camera := $Camera3D as Camera3D
	var mouse := get_viewport().get_mouse_position()
	for i: int in effect.units.size():
		var unit: Dictionary = effect.units[i]
		if effect.animation_time() < float(unit.assembly_end): continue
		var box: AABB = unit.normalize * unit.snapshot.bounds
		box.position += Vector3(unit.ground) + unit.root.position
		var rect := Rect2()
		for corner: int in 8:
			var point := camera.unproject_position(box.get_endpoint(corner))
			rect = Rect2(point, Vector2.ZERO) if corner == 0 else rect.expand(point)
		var source: String = unit.root.get_meta(&"summon_source_scene")
		var title := source.get_file().trim_prefix("Generate_").trim_suffix(".tscn")
		_selection_entries.append({"index": i, "rect": rect, "label": title, "z": unit.ground.z})
		if rect.grow(5).has_point(mouse): _hovered.append(i)
	# Front-most card is selected first. Repeat click or Tab can reach covered cards.
	_hovered.sort_custom(func(a: int, b: int): return effect.units[a].ground.z > effect.units[b].ground.z)
	$UI/SelectionOverlay.entries = _selection_entries
	$UI/SelectionOverlay.selected = _selected
	$UI/SelectionOverlay.hovered = _hovered
	$UI/SelectionOverlay.queue_redraw()
	if _selected >= 0:
		status.text += "    已选 #%d / 重叠候选 %d" % [_selected + 1, _hovered.size()]

func _cycle_selection(reverse: bool = false) -> void:
	var candidates: Array[int] = _hovered.duplicate()
	if candidates.is_empty():
		for entry: Dictionary in _selection_entries: candidates.append(entry.index)
	if candidates.is_empty(): return
	var current := candidates.find(_selected)
	_selected = candidates[posmod(current + (-1 if reverse else 1), candidates.size())]
	_update_selection()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _hovered.is_empty():
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null: focused.release_focus()
			_cycle_selection()
			get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_SPACE: toggle_pause()
		KEY_R: play(true)
		KEY_N: seed_input.value += 1; play()
		KEY_ENTER, KEY_KP_ENTER: effect.skip(); get_viewport().set_input_as_handled()
		KEY_TAB: _cycle_selection(event.shift_pressed); get_viewport().set_input_as_handled()
		KEY_ESCAPE: clear()
		KEY_1: preset(2, size_input.value)
		KEY_2: preset(5, size_input.value)
		KEY_3: preset(12, size_input.value)
		KEY_4: preset(20, size_input.value)

