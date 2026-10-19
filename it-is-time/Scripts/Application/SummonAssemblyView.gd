extends SubViewportContainer
## A private physics world; it never joins the real battle or writes back creature state.
signal finished
const TEXT = preload("res://Scripts/Localization/GameText.gd")
var settings: Resource = preload("res://Resources/Application/DefaultSummonAnimation.tres")
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var paused := false
var _physics_lease := false
var _suspended_spaces: Dictionary = {}
var _free_mouse := false
var _observation_hint: Label

var phase: String:
	get: return stage.phase if is_instance_valid(stage) else "stopped"
var elapsed: float:
	get: return stage.elapsed if is_instance_valid(stage) else 0.0
var pieces: Array:
	get: return stage.pieces if is_instance_valid(stage) else []

func begin(records: Array) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	stretch = true
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	stage = settings.stage_scene.instantiate()
	viewport.add_child(stage)
	stage.finished.connect(_finished)
	stage.configure(records,settings)
	camera = stage.get_node("DragCamera3D").get_camera()
	_observation_hint = Label.new()
	_observation_hint.name = "ObservationHint"
	_observation_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_observation_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_observation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_observation_hint.add_theme_font_size_override("font_size",16)
	_observation_hint.add_theme_color_override("font_color",Color.WHITE)
	_observation_hint.add_theme_color_override("font_outline_color",Color("29231d"))
	_observation_hint.add_theme_constant_override("outline_size",4)
	add_child(_observation_hint)
	_observation_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_observation_hint.offset_top = 10
	_observation_hint.offset_bottom = 64
	_update_observation_hint()
	resized.connect(_frame_camera)
	_frame_camera()
	_sync_physics()
	_sync_observation_input()

func is_observation_input_blocked() -> bool:
	return _free_mouse or _observation_suspended()

func _observation_suspended() -> bool:
	if paused or phase in ["stopped","finished"] or not is_visible_in_tree(): return true
	var host := preload("res://Scripts/Player/PlayerControlContext.gd").application(self)
	if host != null and host.ui != null and host.ui.overlay.visible: return true
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	return console != null and console.is_console_open()

func _process(_delta: float) -> void:
	_sync_observation_input()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"QPressed") or _observation_suspended(): return
	_free_mouse = not _free_mouse
	_sync_observation_input()
	_update_observation_hint()
	get_viewport().set_input_as_handled()

func _sync_observation_input() -> void:
	if not is_instance_valid(stage): return
	var enabled := not is_observation_input_blocked()
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	var rig: Node3D = stage.get_node("DragCamera3D")
	rig.input_enabled = enabled
	if not enabled: rig.cancel_orbit()
	var cursor: TerrainCursor3D = stage.get_node("TerrainCursor3D")
	cursor.input_enabled = enabled
	cursor._process(0.0)

func _update_observation_hint() -> void:
	TEXT.bind(_observation_hint,&"text",func(): return TEXT.text("summon.observation.free_mouse" if _free_mouse else "summon.observation.controls"))

func _frame_camera() -> void:
	if is_instance_valid(stage): stage.frame_camera(size.x/maxf(size.y,1.0))

func advance(_delta: float) -> void:
	if paused or phase in ["stopped","finished"]: return
	if phase == "preparing": stage.prepare_frame()
	_sync_physics()

func _physics_process(_delta: float) -> void:
	if is_instance_valid(viewport): _sync_physics()

func set_paused(value: bool) -> void:
	paused = value
	if is_instance_valid(stage): stage.paused = value
	_sync_physics()
	_sync_observation_input()

func _sync_physics() -> void:
	if not is_instance_valid(viewport) or not is_inside_tree(): return
	var active := not paused and phase not in ["stopped","finished"]
	var own := viewport.find_world_3d().space
	PhysicsServer3D.space_set_active(own,active)
	if active and get_tree().paused:
		# SceneTree pause disables the server globally. Stop every other space before reopening it.
		if not _physics_lease:
			_physics_lease = true
			get_tree().node_added.connect(_on_viewport_added)
			_suspend_viewport(get_tree().root)
			for view: Viewport in get_tree().root.find_children("*","Viewport",true,false): _suspend_viewport(view)
		PhysicsServer3D.set_active(true)
	elif _physics_lease:
		_release_physics()

func _on_viewport_added(node: Node) -> void:
	if node is Viewport: _suspend_viewport(node)

func _suspend_viewport(view: Viewport) -> void:
	var world := view.find_world_3d()
	if world.space == viewport.find_world_3d().space or _suspended_spaces.has(world.space): return
	_suspended_spaces[world.space] = {"world":weakref(world),"active":PhysicsServer3D.space_is_active(world.space)}
	PhysicsServer3D.space_set_active(world.space,false)

func _release_physics() -> void:
	if not _physics_lease: return
	get_tree().node_added.disconnect(_on_viewport_added)
	PhysicsServer3D.set_active(not get_tree().paused)
	for space: RID in _suspended_spaces:
		var state: Dictionary = _suspended_spaces[space]
		if state.world.get_ref() != null: PhysicsServer3D.space_set_active(space,state.active)
	_suspended_spaces.clear()
	_physics_lease = false

func _finished() -> void:
	_sync_physics()
	_sync_observation_input()
	finished.emit()

func stop() -> void:
	if is_instance_valid(stage): stage.stop()
	_sync_observation_input()
	_release_physics()
	if is_instance_valid(viewport):
		PhysicsServer3D.space_set_active(viewport.find_world_3d().space,false)
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	hide()

func _exit_tree() -> void:
	_release_physics()
