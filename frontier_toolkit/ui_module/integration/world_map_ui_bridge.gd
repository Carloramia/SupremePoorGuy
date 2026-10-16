class_name WorldMapUIBridge
extends CanvasLayer
## Composes modules without changing the world's movement/interaction code.
@export var world_map_path: NodePath = NodePath("..")
@export var session_save_path := "user://ui_module_session.json"
var world: WorldMapController
var app: GameUI
var _owns_pause := false
var _previous_ui_visibility: Dictionary = {}
var _last_feedback := ""

func _ready() -> void:
	layer = 15
	world = get_node(world_map_path) as WorldMapController
	if not world:
		push_error("WorldMapUIBridge requires a WorldMapController host")
		return
	if not world.is_initialized:
		await world.initialized
	app = preload("res://ui_module/demo/UIModuleDemo.tscn").instantiate()
	app.embedded_world = true
	app.session_save_path = session_save_path
	app.context_provider = current_context
	app.blocking_changed.connect(_blocking_changed)
	app.map_command_requested.connect(_map_command)
	add_child(app)
	for control_name in ["MapHeader","MapToolbar","MapFeedback"]:
		var control := world.ui.get_node_or_null("Root/"+control_name) as Control
		if control:
			_previous_ui_visibility[control] = control.visible
			control.hide()
	world.world_map_paused.connect(_host_paused)
	world.world_map_resumed.connect(_host_resumed)
	app.set_external_blocked(world.paused and not _owns_pause)

func _process(_delta: float) -> void:
	if app and is_instance_valid(app) and not app.is_blocking() and world.ui.feedback.text != _last_feedback:
		_last_feedback = world.ui.feedback.text
		if not _last_feedback.is_empty():
			app.status.text = _last_feedback

func current_context() -> Dictionary:
	var point := world.to_local(world.player.global_position)
	var hex := HexMath.world_to_axial(point,world.definition.hex_size)
	var cell: Dictionary = world.grid.cells.get(hex,{})
	var terrain := str(cell.get("terrain","grass"))
	var biome: String = {"forest":"forest","desert":"desert","sand":"desert"}.get(terrain,"grassland")
	return {"map_id":String(world.definition.map_id),"hex":[hex.x,hex.y],"position":[point.x,point.y],"terrain":terrain,"biome":biome,"display_name":"%s · Hex (%d, %d)" % [world.definition.display_name,hex.x,hex.y]}

func _blocking_changed(blocked: bool) -> void:
	if blocked:
		if not world.paused:
			_owns_pause = true
			world.set_world_map_paused(true)
		world.ui.tooltip.hide()
		world.ui.feedback.hide()
		world.ui.save_button.disabled = true
		world.ui.load_button.disabled = true
	elif _owns_pause:
		_owns_pause = false
		# A location interaction may have taken ownership through an external API.
		if world.interaction.active_location == null:
			world.set_world_map_paused(false)
		world.ui.save_button.disabled = world.interaction.active_location != null
		world.ui.load_button.disabled = world.interaction.active_location != null

func _host_paused() -> void:
	if app and not _owns_pause:
		app.set_external_blocked(true)

func _host_resumed() -> void:
	if not app:
		return
	app.set_external_blocked(false)
	# Protect an open UI even if an external host attempts to resume travel.
	if app.is_blocking():
		_blocking_changed(true)

func _map_command(command: StringName) -> void:
	if app.is_blocking() or world.paused:
		return
	match command:
		&"save": world.save_world_map()
		&"load": world.load_world_map()
		&"focus": world.focus_on_player()
		&"debug":
			world.terrain.show_hex_debug = not world.terrain.show_hex_debug
			get_tree().debug_navigation_hint = world.terrain.show_hex_debug

func _exit_tree() -> void:
	if is_instance_valid(world) and world.is_inside_tree():
		if _owns_pause and world.interaction.active_location == null:
			world.set_world_map_paused(false)
		if is_instance_valid(world.ui):
			world.ui.save_button.disabled = world.interaction.active_location != null
			world.ui.load_button.disabled = world.interaction.active_location != null
		for control in _previous_ui_visibility:
			if is_instance_valid(control):
				control.visible = _previous_ui_visibility[control]
