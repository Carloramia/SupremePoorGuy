class_name GameUI
extends "res://ui_module/prototype/Scripts/GameDemo.gd"
## Native UI façade. One session owns ritual, pending results, warehouse and party.
signal blocking_changed(blocked: bool)
signal map_command_requested(command: StringName)
signal summon_committed(monster_ids: Array, context: Dictionary)

@export var embedded_world := false
@export var session_save_path := "user://ui_module_session.json"
var context: Dictionary = {}
var context_provider: Callable
var external_blocked := false
var _blocking := false
var _return_focus: WeakRef

func _ready() -> void:
	state.save_path = session_save_path
	super._ready()

func _build() -> void:
	super._build()
	if embedded_world:
		$Background.hide()
		view.hosted_world = true
		view.summon_book.get_node("Caption").add_theme_color_override("font_color",Color("f0e3c8"))
		# Empty regions let clicks reach the actual WorldMapController.
		for control in [self, base, root_layout, main_content, view.get_parent(), view]:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _show(next: String) -> void:
	if not embedded_world:
		super._show(next)
		return
	# The host alone owns travel, location interactions and combat.
	route = "eruption" if next == "eruption" else "world"
	_clear(actions)
	_refresh_sidebar()
	view.configure("world",location,state.monsters("team"))
	if route == "eruption":
		view.erupt()
		_btn(actions,"跳过召唤演出",func(): view.skip_eruption())
		status.text = "妖兽已保存 · 演出可跳过，结果不会重抽。"
	else:
		_btn(actions,"保存地图",func(): map_command_requested.emit(&"save"))
		_btn(actions,"读取地图",func(): map_command_requested.emit(&"load"))
		_btn(actions,"跟随旅人",func(): map_command_requested.emit(&"focus"))
		_btn(actions,"地图调试",func(): map_command_requested.emit(&"debug"))
		if not state.data.pending.is_empty():
			_btn(actions,"安置上次召唤",_resume_pending)
		status.text = "左键移动 / 地点　·　右键拖动　·　滚轮缩放　·　右下角书本召唤（测试规则）"
	_update_header()
	for command in actions.get_children():
		if command is Button:
			command.theme_type_variation = &"PrimaryButton"
	_block_base(base, external_blocked or overlay.visible or route == "eruption")
	# The skip control remains interactive while the map is frozen.
	if route == "eruption":
		_block_base(actions, false)
	_sync_blocking()

func _location_clicked(id: String, kind: String) -> void:
	if not embedded_world:
		super._location_clicked(id,kind)

func _skip_battle() -> void:
	if not embedded_world:
		super._skip_battle()

func open_summon(place: Dictionary = {}) -> bool:
	if external_blocked or is_blocking():
		return false
	set_location_context(place)
	_open_ritual()
	return true

func open_warehouse() -> bool:
	if external_blocked or is_blocking():
		return false
	_warehouse()
	return true

func open_party() -> bool:
	if external_blocked or is_blocking():
		return false
	_warehouse("team")
	return true

func set_location_context(place: Dictionary) -> void:
	context = place.duplicate(true)
	var biome := str(context.get("biome","grassland"))
	location = biome if LOCATION_NAMES.has(biome) else "grassland"

func _open_ritual() -> void:
	if external_blocked or board_motion.busy or route == "eruption":
		return
	if embedded_world and context_provider.is_valid():
		set_location_context(context_provider.call())
	super._open_ritual()

func _build_ritual(body: VBoxContainer) -> void:
	super._build_ritual(body)
	if embedded_world:
		modal_title.text = "六相召唤阵 · %s" % context.get("display_name",LOCATION_NAMES[location])

func _warehouse(filter: String = "warehouse") -> void:
	if external_blocked or board_motion.busy or route == "eruption":
		return
	super._warehouse(filter)

func _modal(title: String, builder: Callable) -> void:
	if external_blocked:
		return
	if modal_stack.is_empty():
		var focus := get_viewport().gui_get_focus_owner()
		_return_focus = weakref(focus) if focus else null
	super._modal(title,builder)
	_sync_blocking()

func _render_modal() -> void:
	super._render_modal()
	if external_blocked:
		_block_base(base,true)
	_sync_blocking()
	if not overlay.visible:
		_restore_focus()

func _close_modal(store_results: bool = true) -> void:
	if board_motion.busy:
		return
	super._close_modal(store_results)
	_sync_blocking()

func _summon() -> void:
	if board_motion.busy or route == "eruption":
		return
	state.summon_context = context.duplicate(true)
	var previous_serial: int = state.data.serial
	super._summon()
	if int(state.data.serial) != previous_serial:
		summon_committed.emit(state.data.pending.duplicate(),context.duplicate(true))
	_sync_blocking()

func _resume_pending() -> void:
	if external_blocked:
		return
	set_location_context(state.data.get("pending_context",{}))
	super._resume_pending()

func is_blocking() -> bool:
	return is_instance_valid(overlay) and (overlay.visible or route == "eruption")

func set_external_blocked(value: bool) -> void:
	external_blocked = value
	if is_instance_valid(base):
		_block_base(base,value or is_blocking())

func _sync_blocking() -> void:
	var value := is_blocking()
	if value != _blocking:
		_blocking = value
		blocking_changed.emit(value)

func _restore_focus() -> void:
	var restored := false
	if _return_focus:
		var control = _return_focus.get_ref()
		if is_instance_valid(control) and control.is_visible_in_tree() and not (control is BaseButton and control.disabled):
			control.grab_focus()
			restored = true
		_return_focus = null
	if not restored and is_instance_valid(view) and view.summon_book.is_visible_in_tree() and not view.summon_book.disabled:
		view.summon_book.grab_focus()

func _help() -> void:
	if not embedded_world:
		super._help()
		return
	_term("旅途指南","左键在真实大地图移动，抵达已选地点后打开交互；右键拖动、滚轮缩放。\n右下角书本直接打开召唤；照符文小图连线，Enter刻入，Backspace撤回，Esc取消草稿或逐层返回。\n召唤结果可加入出战或入库，队列上限6只；仓库支持详情、改名与属性说明。\n\n当前使用原型测试扣费和生成规则，纸雕素材为原型素材。战斗与事件仍由地图原有模块负责。UI进度单独保存，不修改地图存档。")
