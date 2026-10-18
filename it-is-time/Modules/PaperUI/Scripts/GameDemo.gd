extends Control
const L10N = preload("res://Scripts/Localization/GameText.gd")
## Flow controller only. Visual structure belongs to Scenes/UI and Assets/UI.
@export var animate_panels := true
signal location_interaction_requested(location_id: String, kind: String)
signal scene_requested(kind: String, location_id: String)
signal party_changed(monster_ids: Array)
const MapCurtain = preload("res://Modules/PaperUI/Scenes/UI/Components/WorldView.tscn")
const LeafContent = preload("res://Modules/PaperUI/Assets/UI/PaperRelief/Styles/LeafContent.tres")
const PaperTear = preload("res://Modules/PaperUI/Scripts/UI/PaperTear.gd")
const State = preload("res://Modules/PaperUI/Scripts/PrototypeState.gd")
const Experiment = preload("res://Modules/PaperUI/Scripts/SummonExperiment.gd")
const Rules = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
const ActionButton = preload("res://Modules/PaperUI/Scenes/UI/Components/ActionButton.tscn")
const StatButton = preload("res://Modules/PaperUI/Scenes/UI/Components/StatButton.tscn")
const RelicButton = preload("res://Modules/PaperUI/Scenes/UI/Components/RelicButton.tscn")
const RelicReference = preload("res://Modules/PaperUI/Scenes/UI/Components/RelicReferenceRow.tscn")
const RuneReference = preload("res://Modules/PaperUI/Scenes/UI/Components/RuneReferenceRow.tscn")
const ActiveRune = preload("res://Modules/PaperUI/Scenes/UI/Components/ActiveRuneRow.tscn")
const RitualPanel = preload("res://Modules/PaperUI/Scenes/UI/Screens/RitualPanel.tscn")
const MonsterNote = preload("res://Modules/PaperUI/Scenes/UI/Components/MonsterNote.tscn")
const MonsterCard = preload("res://Modules/PaperUI/Scenes/UI/Components/MonsterCard.tscn")
const ResultCard = preload("res://Modules/PaperUI/Scenes/UI/Components/MonsterResultCard.tscn")
const MonsterDetail = preload("res://Modules/PaperUI/Scenes/UI/Screens/MonsterDetail.tscn")
const ResultsPanel = preload("res://Modules/PaperUI/Scenes/UI/Screens/ResultsPanel.tscn")
const WarehousePanel = preload("res://Modules/PaperUI/Scenes/UI/Screens/WarehousePanel.tscn")
const TextPanel = preload("res://Modules/PaperUI/Scenes/UI/Screens/TextPanel.tscn")
const EventPanel = preload("res://Modules/PaperUI/Scenes/UI/Screens/EventPanel.tscn")
const TasksPanel = preload("res://Modules/PaperUI/Scenes/UI/Screens/TasksPanel.tscn")
var state = State.new()
var rules = Rules.new()
var route := "main"
var location := "grassland"
var return_route := "world"
var root_layout: VBoxContainer
var base: MarginContainer
var main_content: HBoxContainer
var sidebar: VBoxContainer
var party_panel: PanelContainer
var view
var header: Label
var status: Label
var actions: HFlowContainer
var overlay: ColorRect
var board_motion
var modal_stack: Array[Dictionary] = []
var modal_backdrop: TextureRect
var modal_box: VBoxContainer
var modal_title: Label
var close_button: Button
var modal_scroll: ScrollContainer
var modal_feedback: Label
var modal_dialog_style: StyleBox
var ritual_columns: HBoxContainer
var ritual_left_scroll: ScrollContainer
var ritual_right_scroll: ScrollContainer
var board
var ritual_page: Control
var ritual_summary: Label
var active_list: VBoxContainer
var summon_button: Button
var warehouse_page: Control
var selected_monster := ""
var warehouse_filter := "warehouse"
var form_filters: Array[String] = []
var rune_fold_open := true
var relic_fold_open := false
var day := 1
var weather := "未接入"
var next_event_time := "未接入"
var curtain_tween: Tween
var outgoing_page: Control
var curtain_snapshot: Control
var curtain_busy := false
var page_tween: Tween
var main_menu: Control
const LOCATION_NAMES = {"grassland":"草原 · 荒原兽群", "forest":"森林 · 蛛树守卫", "desert":"沙漠 · 沙丘遗迹"}
const LOCATION_TAGS = {"grassland":"【草原】【干旱】", "forest":"【森林】【潮湿】", "desert":"【沙漠】【沙】"}
const EVENTS = {"traveler":{"has_followup":false}}
const TERMS = {"生命":"可承受伤害的总量。本版本仅展示，不模拟真实战斗。", "攻击":"普通攻击的基础强度。当前为测试数值。", "护甲":"抵抗攻击的能力。真实减伤公式由战斗模块接入。", "移速":"移动速度。当前仅作为怪物属性展示。", "灼烧":"攻击留下持续余火；当前仅展示能力说明。", "相邻":"两个蜂窝共享一条边。停用符文仍占格，删除才释放。"}

func _ready() -> void:
	get_window().min_size = Vector2i(1120,680)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	_update_motion_status()
	state.load_save()
	rules.import_layout(state.data.layout)
	_build()
	resized.connect(_resize_event)
	_show("main")

func _build() -> void:
	main_menu = %MainMenu
	main_menu.get_node("%Start").pressed.connect(func(): _confirm("开始新游戏？","开始新的正式会话；当前进度保存为备份。",_start_new))
	main_menu.get_node("%Continue").disabled = not state.has_save() and state.data.pending.is_empty()
	main_menu.get_node("%Continue").pressed.connect(func():
		_show("world")
		if not state.data.pending.is_empty():
			_resume_pending())
	main_menu.get_node("%Settings").pressed.connect(_settings)
	base = %AppShell
	root_layout = base.get_node("%Layout")
	main_content = base.get_node("%MainContent")
	party_panel = base.get_node("%PartySidebar")
	sidebar = party_panel.get_node("%Members")
	party_panel.get_node("%Manage").pressed.connect(func(): _warehouse())
	header = base.get_node("%Header")
	status = base.get_node("%Status")
	actions = base.get_node("%Actions")
	base.get_node("%Settings").pressed.connect(_settings)
	base.get_node("%Navigation").action_requested.connect(_navigation_requested)
	view = base.get_node("%WorldView")
	view.location_clicked.connect(_location_clicked)
	view.ritual_requested.connect(_open_ritual)
	view.eruption_finished.connect(_eruption_done)
	overlay = %ModalHost
	board_motion = overlay.get_node("%BoardMotion")
	board_motion.enabled = animate_panels
	board_motion.completed.connect(_motion_completed)
	modal_dialog_style = overlay.get_node("BoardMotion/MotionRoot/Margin/Panel").get_theme_stylebox("panel")
	modal_box = overlay.get_node("%Body")
	modal_title = overlay.get_node("%Title")
	modal_scroll = overlay.get_node("%Scroll")
	modal_feedback = overlay.get_node("%Feedback")
	close_button = overlay.get_node("%Close")
	close_button.pressed.connect(_close_modal)
	modal_backdrop = %ModalBackdrop
	overlay.hide()

func _navigation_requested(action: String) -> void:
	match action:
		"tasks": _tasks()
		"summon": _open_ritual()
		"warehouse": _warehouse()
		"party": _warehouse("team")
		"world": _show("world")
		"dictionary": _book()
		"help": _help()

func _show(next: String) -> void:
	var previous := route
	route = next
	main_menu.visible = next == "main"
	base.visible = next != "main"
	_clear(actions)
	base.get_node("%Navigation").present_context(next == "battle",animate_panels)
	_refresh_sidebar()
	var falling_map := previous == "battle" and next == "world" and animate_panels and DisplayServer.get_name() != "headless"
	view.configure("battle" if falling_map else ("world" if next in ["main","world"] else "battle"),location,state.monsters("team"))
	view.set_unavailable_events(_completed_final_events())
	match next:
		"main":
			_btn(actions,"ui.154dead50beb",func(): _show("world"))
			if not state.data.pending.is_empty():
				_btn(actions,"ui.c4b1cd8242b2",_resume_pending)
			L10N.bind(status,&"text","ui.be1fff2a8108")
		"world":
			L10N.bind(status,&"text","ui.938678639212")
		"battle":
			L10N.bind(status,&"text",func(): return L10N.text(LOCATION_NAMES.get(location,location)+"  "+LOCATION_TAGS.get(location,"")+L10N.text("ui.53c374037c07")))
		"eruption":
			view.erupt()
			_btn(actions,"ui.63ccfb01fdfc",func(): view.skip_eruption())
			L10N.bind(status,&"text","ui.0d6a567ed2c0")
	actions.visible = actions.get_child_count() > 0
	main_content.visible = not _has_page_root()
	status.visible = next != "main" and not _has_page_root()
	_update_header()
	if previous != next and next == "battle":
		_curtain(true)
	elif previous == "battle" and next == "world":
		_curtain(false)
	if is_instance_valid(overlay) and overlay.visible:
		_block_base(base,true)

func _update_header() -> void:
	L10N.bind(header,&"text",func(): return L10N.text(L10N.text("ui.8492901895ca") % [LOCATION_NAMES.get(location,location),day,state.data.magic,next_event_time]))
	L10N.bind(header,&"tooltip_text","ui.3c1e43e814e3")

func _refresh_sidebar() -> void:
	_clear(sidebar)
	L10N.bind(party_panel.get_node("%Count"),&"text",func(): return L10N.text(L10N.text("ui.2dd805a57885") % [state.occupied_slots(),state.monsters("team").size()] if state.monsters("team").any(func(m): return m.has("mode")) else L10N.text("ui.79133e67d708") % state.monsters("team").size()))
	party_panel.get_node("%Empty").visible = state.monsters("team").is_empty()
	L10N.bind(party_panel.get_node("%StorageCount"),&"text",func(): return L10N.text(L10N.text("ui.c3c19bd51260") % state.monsters("warehouse").size()))
	for monster in state.monsters("team"):
		var b := _btn(sidebar,func(): return L10N.creature_name(monster),func(): _detail(monster.id))
		L10N.bind(b,&"tooltip_text",func(): return L10N.text(L10N.text("ui.bed813ff8615") % [monster.hp,monster.attack,monster.armor," / ".join(monster.traits.map(func(value): return L10N.text(value)))]))
	if is_instance_valid(overlay) and overlay.visible:
		_block_base(sidebar,true)

func _location_clicked(id: String, kind: String) -> void:
	if curtain_busy or route not in ["main","world"] or not modal_stack.is_empty():
		return
	location_interaction_requested.emit(id,kind)
	if kind == "event":
		_open_event(id)
	else:
		location = id
		view.hide_location_hint()
		scene_requested.emit("battle",id)
		_show("battle")

func _completed_final_events() -> Array:
	var ids: Array = []
	for id in EVENTS:
		if not EVENTS[id].has_followup and "event_"+id in state.data.completed:
			ids.append(id)
	return ids

func _open_event(id: String) -> void:
	if id in _completed_final_events():
		view.set_unavailable_events(_completed_final_events())
		_notice("ui.a2b695380784")
		return
	_modal("旅人手记",func(body):
		var page := EventPanel.instantiate()
		body.add_child(page)
		L10N.bind(page.get_node("%Description"),&"text","ui.31a5ee649fa0")
		var claim := _btn(page.get_node("%Commands"),"ui.c4c7bf26e766",func():
			if state.claim_once("event_"+id,20):
				_close_all()
				_show("world")
				L10N.bind(status,&"text","ui.03bd4cf5fe4e")
			else:
				_notice(func(): return L10N.text(state.last_error)))
		claim.disabled = "event_"+id in state.data.completed
		L10N.bind(claim,&"tooltip_text",func(): return L10N.text(L10N.text("ui.4f7a55e18781") if claim.disabled else L10N.text("ui.c9f1d8752b85"))),"event")

func _skip_battle() -> void:
	_modal("战斗胜利",func(body):
		var page := _text_screen(body,func(): return L10N.text(LOCATION_NAMES.get(location,location)+L10N.text("ui.fde172be0ca4")))
		var received: bool = "battle_"+location in state.data.completed
		_btn(page.get_node("%Commands"),func(): return L10N.text(L10N.text("ui.a479d4fcd248") if received else L10N.text("ui.666ed22cde42")),func():
			if received or state.claim_once("battle_"+location,20):
				_close_all()
				_show("world")
				L10N.bind(status,&"text",func(): return L10N.text(L10N.text("ui.75e0b3321897") if received else L10N.text("ui.0b1a6d931377")))
			else:
				_notice(func(): return L10N.text(state.last_error))))

func _open_ritual() -> void:
	if curtain_busy:
		return
	if not state.data.pending.is_empty():
		_resume_pending()
		return
	_modal("六相召唤阵　·　"+LOCATION_TAGS.get(location,""),_build_ritual)

func _build_ritual(body: VBoxContainer) -> void:
	var page := RitualPanel.instantiate()
	body.add_child(page)
	ritual_page = page
	page.get_node("%Upgrade").pressed.connect(_upgrade_stage)
	page.get_node("%Upgrade").disabled = rules.stage >= 4
	page.get_node("%Examples").item_selected.connect(_load_example)
	page.get_node("%TrialInfo").pressed.connect(func(): _term("召唤规则与配方",Experiment.trial_notes()+"\n\n定向配方：甲片(-2,0)→(-1,0)，血脉(-1,1)→(0,1)→(1,1)，锐牙(0,-1)→(0,0)→(1,-1)，骨骰(1,0)(2,0)。允许整体平移、旋转和镜像；不能有额外笔画。"))
	close_button = page.get_node("%PageBack")
	close_button.pressed.connect(_close_modal)
	L10N.bind(page.get_node("%PageTitle"),&"tooltip_text",func(): return L10N.text(L10N.text("ui.1e1c21856d33")+LOCATION_TAGS.get(location,"")))
	ritual_columns = page.get_node("%Columns")
	ritual_left_scroll = page.get_node("%LeftScroll")
	ritual_right_scroll = page.get_node("%RightScroll")
	active_list = page.get_node("%ActiveList")
	page.get_node("%RuneTab").pressed.connect(func(): _fold(page.get_node("%References"),true))
	page.get_node("%RelicTab").pressed.connect(func(): _fold(page.get_node("%Relics"),false))
	# Keep exactly one reference page open, including after nested explanations.
	rune_fold_open = not relic_fold_open
	page.get_node("%References").visible = rune_fold_open
	page.get_node("%Relics").visible = relic_fold_open
	var context: RichTextLabel = page.get_node("%Context")
	L10N.bind(context,&"text",func(): return L10N.text(L10N.text("ui.116803817809") % [LOCATION_NAMES.get(location,location).split(" · ")[0],weather,LOCATION_TAGS.get(location,"")]))
	context.meta_hover_started.connect(func(meta):
		L10N.bind(context,&"tooltip_text",func(): return L10N.text({"地区":LOCATION_TAGS.get(location,""),"天气":L10N.text("ui.f275a950ca23"),"形态":L10N.text("ui.6c0cc8aeb11b"),"词条":L10N.text("ui.7ff366d4f703")}.get(str(meta),""))))
	context.meta_hover_ended.connect(func(_meta): L10N.bind(context,&"tooltip_text",""))
	board = page.get_node("%Board")
	board.rules = rules
	board.changed.connect(_refresh_ritual)
	board.notice.connect(_notice)
	for relic in Rules.RELICS:
		if relic.id not in state.known_references(true):
			continue
		var row := RelicReference.instantiate()
		row.get_node("%Preview").preview_path = relic.cells
		var tile: Button = row.get_node("%Open")
		tile.relic_id = relic.id
		L10N.bind(tile,&"text",func(): return L10N.text(L10N.text(relic.name)+L10N.text("ui.d733b9a0768f") % relic.cells.size()+{"tide-pump":L10N.text("ui.9f5549d5e61b"),"prism-heart":L10N.text("ui.6059872c31e7"),"bone-die":L10N.text("ui.3bdc5285d10a")}.get(relic.id,L10N.text(relic.effect))))
		L10N.bind(tile,&"tooltip_text",func(): return L10N.text(L10N.text(relic.effect)))
		tile.pressed.connect(func():
			board.selected_relic = relic.id
			board.queue_redraw()
			_notice(func(): return L10N.text(L10N.text("ui.3b2ee82dd97c")+L10N.text(relic.name)+L10N.text("ui.b98433038799"))))
		page.get_node("%Relics").add_child(row)
	for rune in Rules.RUNES:
		if rune.id not in state.known_references():
			continue
		var row := RuneReference.instantiate()
		row.get_node("%Preview").preview_path = rune.cells
		L10N.bind(row.get_node("%Open"),&"tooltip_text",func(): return L10N.text(L10N.text(rune.effect)+"\n"+L10N.text(rune.detail)))
		L10N.bind(row.get_node("%Open"),&"text",func(): return L10N.text(L10N.text(rune.name)+L10N.text("ui.d733b9a0768f") % rune.cells.size()+L10N.text(rune.effect)))
		L10N.bind(row.get_node("%Effect"),&"text",func(): return L10N.text(L10N.text(rune.effect)))
		row.get_node("%Open").pressed.connect(func(): _term(rune.name,rune.effect+"\n"+rune.detail))
		page.get_node("%References").add_child(row)
	# Both tabs share one width budget, including the permanently reserved gutter.
	# Hidden reference pages still supply their own content minimum sizes.
	var reference_width := maxf(page.get_node("%References").get_combined_minimum_size().x,page.get_node("%Relics").get_combined_minimum_size().x)
	var gutter: float = ritual_right_scroll.get_v_scroll_bar().get_combined_minimum_size().x+ritual_right_scroll.get_theme_constant("scrollbar_v_separation")
	ritual_right_scroll.custom_minimum_size.x = maxf(235.0,reference_width+gutter)
	ritual_summary = page.get_node("%Summary")
	summon_button = page.get_node("%Summon")
	summon_button.pressed.connect(_summon)
	page.get_node("%Commit").pressed.connect(_commit_rune)
	page.get_node("%Undo").pressed.connect(_undo_rune)
	page.get_node("%Cancel").pressed.connect(_cancel_rune)
	page.get_node("%Freehand").toggled.connect(func(value): board.freehand = value)
	page.get_node("%Save").pressed.connect(func():
		_notice(func(): return L10N.text(L10N.text("ui.e60c1253782c") if state.save_layout(rules.export_layout()) else state.last_error)))
	page.get_node("%Clear").pressed.connect(func(): _confirm("清空当前法阵？","删除所有符文、奇物和草稿；已保存的布局不会改变，直到再次保存。",func():
		rules.import_layout({"version":3,"stage":state.data.array_stage,"placed":[],"placedRelics":[]})
		_close_modal()))
	_refresh_ritual()

func _commit_rune() -> void:
	if not rules.commit():
		_notice("ui.463877f8b871")
	_refresh_ritual()

func _undo_rune() -> void:
	if not rules.draft.is_empty():
		rules.draft.pop_back()
	_refresh_ritual()

func _cancel_rune() -> void:
	rules.draft.clear()
	board.selected_relic = ""
	_refresh_ritual()

func _refresh_ritual() -> void:
	if not is_instance_valid(active_list) or not is_instance_valid(board):
		return
	_clear(active_list)
	var cost := 0
	var count := 0
	for item in rules.placed:
		cost += item.cells.size()
		if item.enabled:
			count += 1
		var row := ActiveRune.instantiate()
		var d := Rules.definition(item.runeId)
		var toggle: CheckButton = row.get_node("%Toggle")
		L10N.bind(toggle,&"text",func(): return L10N.text(L10N.text(d.name)))
		toggle.button_pressed = item.enabled
		toggle.toggled.connect(func(value):
			item.enabled = value
			_refresh_ritual())
		row.get_node("%Remove").pressed.connect(func():
			rules.remove(item.uid)
			_refresh_ritual())
		active_list.add_child(row)
	for item in rules.relics:
		var d := Rules.definition(item.relicId,true)
		_btn(active_list,func(): return L10N.text(L10N.text("ui.6a0a313797a0")+L10N.text(d.name)),func():
			rules.remove(item.uid)
			_refresh_ritual())
	var preview := Experiment.preview(rules)
	L10N.bind(ritual_summary,&"text",func(): return L10N.text(L10N.text("ui.86a4ba85300a") % [rules.stage,Rules.cells(rules.stage).size(),state.data.magic,preview.cost,preview.tier,preview.count,preview.total_slots,rules.draft.size()]))
	L10N.bind(summon_button,&"text",func(): return L10N.text(L10N.text("ui.19812bd6781a") % [preview.count,L10N.text("ui.0d64a436c66f") if preview.mode=="ultra" else L10N.text("ui.b3ad05dff665") if preview.mode=="special" else ""]))
	summon_button.disabled = count == 0 or not rules.draft.is_empty() or preview.cost > state.data.magic or not preview.error.is_empty()
	L10N.bind(summon_button,&"tooltip_text",func(): return L10N.text(preview.error if not preview.error.is_empty() else L10N.text("ui.4ebd772c41b8")))
	var risk: Label = ritual_page.get_node("%Risk")
	risk.visible = not preview.sources.is_empty()
	var sources: Array[String] = []
	for source in preview.sources:
		sources.append(L10N.text("ui.6b5e79d1fa5d") % [source.name,source.count,source.threshold,source.chance*100])
	L10N.bind(risk,&"text",func(): return L10N.text(L10N.text("ui.67135d760d3c") % [preview.mutation_chance*100,preview.failure_chance*100]))
	L10N.bind(risk,&"tooltip_text",func(): return L10N.text("\n".join(sources)+"\n"+Experiment.trial_notes()))

	L10N.bind(ritual_summary,&"tooltip_text",func(): return L10N.text(L10N.text("ui.6e0a2332db30")+Experiment.trial_notes()))
	board.queue_redraw()


func _summon() -> void:
	var preview := Experiment.preview(rules)
	if not preview.sources.is_empty():
		_confirm("确认风险召唤",L10N.text("ui.0f991fbdea2b") % [preview.cost,preview.count,preview.failure_chance*100],_perform_summon)
	else:
		_perform_summon()

func _resume_pending() -> void:
	location = state.data.pending_location
	return_route = state.data.pending_return
	_show("eruption")

func _eruption_done() -> void:
	if route != "eruption":
		return
	_show(return_route if return_route in ["world","battle"] else "world")
	_results()

func _results() -> void:
	_modal("召唤完成　·　安置你的妖兽",func(body):
		var page := ResultsPanel.instantiate()
		body.add_child(page)
		var report: Dictionary = state.data.last_summon
		L10N.bind(page.get_node("Hint"),&"text",func(): return L10N.text(L10N.text("ui.6bbe4f572f54") % [report.get("attempted",state.data.pending.size()),report.get("succeeded",state.data.pending.size()),report.get("failed",0),report.get("cost",0)]))
		L10N.bind(page.get_node("%Empty"),&"text",func(): return L10N.text(L10N.text("ui.7aa496de9021") if report.get("succeeded",-1)==0 else L10N.text("ui.bfe1b464fe6f")))
		var index := 0
		for id in state.data.pending.duplicate():
			_monster_card(page.get_node("%Cards"),state.monster_by_id(id),true)
			var card: Control = page.get_node("%Cards").get_child(index)
			L10N.bind(card,&"tooltip_text",func(): return L10N.text(_monster_hint(state.monster_by_id(id))))
			if animate_panels:
				card.modulate.a = 0
				card.create_tween().tween_property(card,"modulate:a",1.0,0.25).set_delay(index*0.18)
			index += 1
		page.get_node("%Empty").visible = state.data.pending.is_empty()
		page.get_node("%StoreAll").pressed.connect(func():
			if state.store_pending():
				_close_all()
				_show(route)
			else:
				_notice(func(): return L10N.text(state.last_error))))

func _warehouse(filter: String = "warehouse") -> void:
	if curtain_busy:
		return
	warehouse_filter = filter
	_modal("妖兽仓库　/　出战队列",_build_warehouse)

func _build_warehouse(body: VBoxContainer) -> void:
	warehouse_page = WarehousePanel.instantiate()
	body.add_child(warehouse_page)
	close_button = warehouse_page.get_node("%PageBack")
	warehouse_page.back_requested.connect(_close_modal)
	warehouse_page.position_filter_requested.connect(func(position_id):
		warehouse_filter = "" if warehouse_filter == position_id else position_id
		_refresh_warehouse_filters())
	warehouse_page.form_filter_requested.connect(func(form, enabled):
		if enabled and form not in form_filters:
			form_filters.append(form)
		elif not enabled:
			form_filters.erase(form)
		_refresh_warehouse_filters())
	warehouse_page.clear_filters_requested.connect(func():
		warehouse_filter = ""
		form_filters.clear()
		_refresh_warehouse_filters())
	_refresh_warehouse_filters(false)

func _refresh_warehouse_filters(animate := true) -> void:
	warehouse_page.present_filters(warehouse_filter,form_filters,{"warehouse":state.monsters("warehouse").size(),"team":state.monsters("team").size()},animate and animate_panels)
	_clear(warehouse_page.get_node("%Cards"))
	var visible_units: Array = []
	for monster in state.monsters(warehouse_filter):
		if not form_filters.is_empty() and monster.form not in form_filters:
			continue
		visible_units.append(monster)
		var note := MonsterNote.instantiate()
		warehouse_page.get_node("%Cards").add_child(note)
		note.present(monster.id,func(): return L10N.creature_name(monster),monster.form,{"team":"出战","warehouse":"仓库","pending":"待安置"}[monster.position],func(): return _monster_hint(monster))
		note.selection_requested.connect(_select_monster)
	warehouse_page.get_node("%Empty").visible = visible_units.is_empty()
	if not visible_units.is_empty():
		if not selected_monster in visible_units.map(func(m): return m.id):
			selected_monster = visible_units[0].id
		_select_monster(selected_monster)
	else:
		selected_monster = ""
		_clear(warehouse_page.get_node("%DetailBody"))
		_clear(warehouse_page.get_node("%DetailCommands"))
		var hint := Label.new()
		L10N.bind(hint,&"text","ui.a3b422931894")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warehouse_page.get_node("%DetailBody").add_child(hint)

func _select_monster(id: String) -> void:
	selected_monster = id
	for note in warehouse_page.get_node("%Cards").get_children():
		note.set_selected(note.monster_id == id)
	var parent := warehouse_page.get_node("%DetailBody")
	_clear(parent)
	_clear(warehouse_page.get_node("%DetailCommands"))
	_fill_detail(parent,id)
	var monster: Dictionary = state.monster_by_id(id)
	var move := _btn(warehouse_page.get_node("%DetailCommands"),func(): return L10N.text(L10N.text("ui.373cba3cd228") if monster.position == "team" else L10N.text("ui.b47e187ba5be")),func():
		if state.move_monster(id,"warehouse" if monster.position == "team" else "team"):
			_notify_party()
			_render_modal()
		else:
			_notice(func(): return L10N.text(state.last_error)))
	move.disabled = monster.position != "team" and not state.can_join(monster.id)
	_btn(warehouse_page.get_node("%DetailCommands"),"ui.a709f287f5df",func(): _confirm("回收怪物？","永久移除这只怪物，不返还魔力。",func(): _recycle_monster(id)))

func _notify_party() -> void:
	party_changed.emit(state.monsters("team").map(func(m): return m.id))
	_refresh_sidebar()
	_update_header()

func _recycle_monster(id: String) -> void:
	# Return from confirmation before deletion so the original note can tear away.
	_close_modal(false)
	var target: Control
	if is_instance_valid(warehouse_page):
		for card in warehouse_page.get_node("%Cards").get_children():
			if card.get_meta("monster_id","") == id:
				target = card
				break
	if not state.recycle_monster(id):
		_notice(func(): return L10N.text(state.last_error))
		return
	_notify_party()
	if animate_panels and is_instance_valid(target):
		_block_base(warehouse_page,true)
		var fragments := PaperTear.new()
		fragments.position = target.global_position - overlay.global_position
		fragments.size = target.size
		overlay.add_child(fragments)
		target.modulate.a = 0
		fragments.finished.connect(func():
			if not modal_stack.is_empty() and modal_stack.back().title.begins_with("妖兽仓库"):
				_render_modal())
		fragments.play()
	else:
		_render_modal()

func _monster_hint(monster: Dictionary) -> String:
	return L10N.text("ui.73360541c042") % [L10N.creature_name(monster),monster.hp,monster.attack,monster.armor,monster.speed," / ".join(monster.traits.map(func(value): return L10N.text(value)))]

func _monster_card(parent: Node, monster: Dictionary, result_card: bool) -> void:
	var card := ResultCard.instantiate() if result_card else MonsterCard.instantiate()
	parent.add_child(card)
	card.get_node("%Portrait").form = monster.form
	card.get_node("%Portrait").tint = Color(monster.color)
	L10N.bind(card.get_node("%Name"),&"text",func(): return L10N.creature_name(monster))
	L10N.bind(card.get_node("%State"),&"text",func(): return L10N.text("%s　·　%s" % [L10N.text(monster.form),{"pending":L10N.text("ui.23a93c3ee12d"),"warehouse":L10N.text("ui.89b2ecbe1f09"),"team":L10N.text("ui.a7caf88fcaa9")}[monster.position]]))
	for pair in [["生命",monster.hp],["攻击",monster.attack],["护甲",monster.armor],["移速",monster.speed]]:
		_btn(card.get_node("%Stats"),func(): return L10N.text("%s %s" % [L10N.text(pair[0]),pair[1]]),func(): _term(pair[0],TERMS[pair[0]]),StatButton)
	for ability_name in monster.traits:
		_btn(card.get_node("%Traits"),func(): return L10N.text("【%s】" % L10N.text(ability_name)),func(): _trait(ability_name))
	card.get_node("%Detail").pressed.connect(func(): _detail(monster.id))
	var to_team: bool = monster.position != "team"
	var move: Button = card.get_node("%Move")
	L10N.bind(move,&"text",func(): return L10N.text(L10N.text("ui.b47e187ba5be") if to_team else L10N.text("ui.373cba3cd228")))
	move.pressed.connect(func():
		if state.move_monster(monster.id,"team" if to_team else "warehouse"):
			var ids: Array = []
			for m in state.monsters("team"):
				ids.append(m.id)
			party_changed.emit(ids)
			_refresh_sidebar()
			_update_header()
			if route == "battle":
				_show("battle")
			if result_card:
				_close_modal(false)
				_results()
			else:
				_render_modal()
		else:
			_notice(func(): return L10N.text(state.last_error)))
	move.disabled = to_team and not state.can_join(monster.id)
	L10N.bind(move,&"tooltip_text",func(): return L10N.text(L10N.text("ui.fd89e6d30452") if move.disabled else ""))
	if result_card:
		L10N.bind(card.get_node("%State"),&"text",func(): return L10N.text(L10N.text("ui.cb6f26a8d65f") % [L10N.text(monster.form),int(monster.get("tier",1)),L10N.text("ui.4277e3fec978") if not monster.get("mutation_sources",[]).is_empty() else L10N.text("ui.de907d10df98"),L10N.text("ui.3baa3dbc6639") if monster.get("mode", "normal")=="tiny" else L10N.text("ui.abea6c28c2ea") % int(monster.get("slots",1))]))
		card.get_node("%Store").pressed.connect(func():
			if state.move_monster(monster.id,"warehouse"):
				_close_modal(false)
				_results()
			else:
				_notice(func(): return L10N.text(state.last_error)))

func _detail(id: String) -> void:
	_modal("妖兽详情",func(body): _fill_detail(body,id))

func _fill_detail(body: VBoxContainer, id: String) -> void:
	var monster := state.monster_by_id(id)
	var page := MonsterDetail.instantiate()
	body.add_child(page)
	page.get_node("%Portrait").form = monster.form
	page.get_node("%Portrait").tint = Color(monster.color)
	L10N.bind(page.get_node("%Name"),&"text",func(): return L10N.creature_name(monster))
	var base_stats := func(): return L10N.text(L10N.text("ui.dfae243744a3") % [monster.hp,monster.attack,monster.armor,monster.speed])
	L10N.bind(page.get_node("%Stats"),&"text",base_stats)
	L10N.bind(page.get_node("%Stats"),&"tooltip_text",func(): return L10N.text(L10N.text("ui.6181ed6f9734")+LOCATION_NAMES.get(monster.get("source_location","grassland"),L10N.text("ui.2e4e2c2dd17a"))))
	if monster.has("mode") and not modal_stack.is_empty() and modal_stack[0].title.begins_with("召唤完成"):
		var sources: Array[String] = []
		for source in monster.mutation_sources:
			sources.append(Rules.definition(source).name)
		L10N.bind(page.get_node("%Stats"),&"text",func(): return String(base_stats.call())+L10N.text("ui.e9da5a00414b") % [monster.tier,monster.interval,{"normal":"普通","giant":"巨化","ultra":"超巨化","multiply":"增殖","tiny":"缩小","special":"定向"}.get(monster.mode,monster.mode),"同批整组占 1 队位" if monster.mode=="tiny" else L10N.text("ui.abea6c28c2ea") % monster.slots,"、".join(sources) if not sources.is_empty() else "无",monster.clone_count,monster.source_cost,monster.part_hp["头部"],monster.part_hp["核心"],monster.part_hp["肢体"]])
	var name_input: LineEdit = page.get_node("%NameInput")
	name_input.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	L10N.bind(name_input,&"placeholder_text",name_input.placeholder_text)
	name_input.text = monster.name
	page.get_node("%Save").pressed.connect(func():
		if state.rename_monster(id,name_input.text):
			_refresh_sidebar()
			_render_modal()
		else:
			_notice(func(): return L10N.text(state.last_error if not state.last_error.is_empty() else L10N.text("ui.e83654164a44"))))
	for ability_name in monster.traits:
		_btn(page.get_node("%Traits"),func(): return L10N.text("【%s】" % L10N.text(ability_name)),func(): _trait(ability_name))


func _book() -> void:
	_modal("符文辞典",func(body):
		var page := _text_screen(body,"ui.a78e12998f1a")
		for rune in Rules.LEGACY_RUNES:
			_btn(page.get_node("%Commands"),func(): return L10N.text(L10N.text(rune.name)+" / "+L10N.text(rune.effect)),func(): _term(rune.name,rune.detail))
		for term in TERMS:
			_btn(page.get_node("%Terms"),func(): return L10N.text(term),func(): _term(term,TERMS[term])))

func _trait(name_text: String) -> void:
	for rune in Rules.RUNES + Rules.LEGACY_RUNES:
		if rune.name == name_text:
			_term(name_text,rune.effect+"\n"+rune.detail+"\n\n当前为召唤结果标签，真实战斗效果由战斗组接入。")
			return

func _term(title: String, content: String) -> void:
	_modal(title,func(body):
		var page := _text_screen(body,func(): return L10N.prose(content))
		for term in TERMS:
			if term != title and term in content:
				_btn(page.get_node("%Terms"),func(): return L10N.text(L10N.text("ui.f528e1124175")+term),func(): _term(term,TERMS[term])))

func _help() -> void:
	_term("旅途指南","大地图上点击战斗或事件图标。右下角书本打开召唤法典。\n召唤：照符文书在相邻蜂窝描画，刻入后点击确认召唤。\n喷涌结束后，将妖兽加入出战队列或仓库。队列最多 6 只。\n战斗场景中先管理队伍，再跳过战斗并领取测试奖励。\n\nEsc 返回最上层。法阵内 Esc 优先取消笔画；Enter 刻入，Backspace 撤回。\n怪物与奖励自动保存在此独立原型的用户目录，不读取正式项目存档。")

func _confirm(title: String, text: String, callback: Callable) -> void:
	_modal(title,func(body):
		var page := _text_screen(body,func(): return L10N.text(text))
		_btn(page.get_node("%Commands"),"ui.36f33adaf094",callback))

func _modal(title: String, builder: Callable, kind := "dialog") -> void:
	view.hide_location_hint()
	var first := modal_stack.is_empty()
	if first and (title.begins_with("六相召唤阵") or title.begins_with("妖兽仓库")):
		_capture_outgoing()
	# Keep the already rendered parent page behind nested explanations. Rebuilding
	# this shared modal host otherwise removes the book and exposes an empty base.
	var backdrop: Texture2D = _capture_modal_backdrop() if not first else null
	modal_stack.append({"title":title,"build":builder,"kind":kind,"backdrop":backdrop})
	_render_modal()
	if first:
		board_motion.reveal()
		if title.begins_with("六相召唤阵") or title.begins_with("妖兽仓库"):
			_slide_outgoing()

func _has_page_root() -> bool:
	return not modal_stack.is_empty() and (modal_stack[0].title.begins_with("六相召唤阵") or modal_stack[0].title.begins_with("妖兽仓库") or modal_stack[0].title.begins_with("召唤完成"))

func _capture_modal_backdrop() -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var frame := get_viewport().get_texture().get_image()
	var region := Rect2i(overlay.get_global_rect()).intersection(Rect2i(Vector2i.ZERO,frame.get_size()))
	return ImageTexture.create_from_image(frame.get_region(region)) if region.has_area() else null

func _resize_event() -> void:
	if modal_stack.is_empty() or modal_stack.back().get("kind", "dialog") not in ["event","tasks"]:
		return
	var margin: MarginContainer = overlay.get_node("BoardMotion/MotionRoot/Margin")
	var side := maxi(48,int(size.x * (0.12 if modal_stack.back().kind == "tasks" else 0.1)))
	margin.add_theme_constant_override("margin_left",side)
	margin.add_theme_constant_override("margin_right",side)

func _render_modal() -> void:
	board_motion.snap()
	close_button = overlay.get_node("%Close")
	_clear(modal_box)
	overlay.visible = not modal_stack.is_empty()
	var page_root := _has_page_root()
	modal_backdrop.texture = null if modal_stack.is_empty() else modal_stack.back().get("backdrop")
	modal_backdrop.visible = modal_backdrop.texture != null
	main_content.visible = not page_root
	status.visible = not page_root and route != "main"
	_block_base(base,overlay.visible)
	if modal_stack.is_empty():
		return
	var ritual: bool = modal_stack.back().title.begins_with("六相召唤阵")
	var warehouse: bool = modal_stack.back().title.begins_with("妖兽仓库")
	var results: bool = modal_stack.back().title.begins_with("召唤完成")
	var event: bool = modal_stack.back().get("kind", "dialog") == "event"
	var tasks: bool = modal_stack.back().get("kind", "dialog") == "tasks"
	var reading := event or tasks
	L10N.bind(close_button,&"text",func(): return L10N.text(L10N.text("ui.95f69693f3c1") if event else (L10N.text("ui.977d03d89573") if tasks else L10N.text("ui.67a940be6b93"))))
	var content_page := ritual or warehouse or results
	var fixed_content := content_page or reading
	board_motion.horizontal = content_page
	var separate_leaves := ritual or warehouse
	modal_title.get_parent().visible = not separate_leaves
	var dialog_style := modal_dialog_style
	if not separate_leaves:
		dialog_style = modal_dialog_style.duplicate()
		dialog_style.content_margin_top = 32.0
	overlay.get_node("BoardMotion/MotionRoot/Margin/Panel").add_theme_stylebox_override("panel",LeafContent if separate_leaves else dialog_style)
	overlay.get_node("BoardMotion/MotionRoot/Margin/BoardSurface").visible = not separate_leaves
	modal_title.add_theme_color_override("font_color",Color("eee3cf") if separate_leaves else Color("27231f"))
	var margin: MarginContainer = overlay.get_node("BoardMotion/MotionRoot/Margin")
	var event_side := maxi(48,int(size.x * (0.12 if tasks else 0.1)))
	margin.add_theme_constant_override("margin_left",event_side if reading else (20 if separate_leaves else (26 if content_page else 260)))
	margin.add_theme_constant_override("margin_right",event_side if reading else (20 if separate_leaves else (26 if content_page else 260)))
	margin.add_theme_constant_override("margin_top",24 if reading or separate_leaves else (12 if content_page else 100))
	margin.add_theme_constant_override("margin_bottom",32 if reading else (12 if content_page else 150))
	modal_feedback.custom_minimum_size.y = 24 if reading or separate_leaves else 50
	modal_feedback.max_lines_visible = 1 if reading or separate_leaves else 2
	overlay.color.a = 0.0 if content_page else 0.65
	modal_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if fixed_content else ScrollContainer.SCROLL_MODE_RESERVE
	modal_box.size_flags_vertical = Control.SIZE_EXPAND_FILL if fixed_content else Control.SIZE_FILL
	modal_scroll.scroll_vertical = 0
	L10N.bind(modal_feedback,&"text",func(): return L10N.text(""))
	L10N.bind(modal_title,&"text",modal_stack.back().title)
	modal_stack.back().build.call(modal_box)
	close_button.grab_focus()

func _close_modal(store_results: bool = true) -> void:
	if modal_stack.is_empty():
		return
	if store_results and modal_stack.back().title.begins_with("召唤完成") and not state.data.pending.is_empty():
		if not state.store_pending():
			_notice(func(): return L10N.text(state.last_error))
			return
	modal_stack.pop_back()
	if modal_stack.is_empty() and store_results and animate_panels:
		if board_motion.horizontal:
			main_content.show()
			status.visible = route != "main"
		board_motion.dismiss()
	else:
		_render_modal()
	_refresh_sidebar()
	_update_header()
	if route == "battle":
		_show("battle")

func _close_all() -> void:
	modal_stack.clear()
	_render_modal()

func _motion_completed(kind: String) -> void:
	if kind == "exit" and modal_stack.is_empty():
		_render_modal()
	elif kind == "enter" and not modal_stack.is_empty():
		close_button.grab_focus()

func _block_base(node: Node, blocked: bool) -> void:
	if node.name == "Settings":
		return
	if node is Button:
		if blocked and not node.has_meta("prior_disabled"):
			node.set_meta("prior_disabled",node.disabled)
			node.disabled = true
		elif not blocked and node.has_meta("prior_disabled"):
			node.disabled = node.get_meta("prior_disabled")
			node.remove_meta("prior_disabled")
	for child in node.get_children():
		_block_base(child,blocked)

func _unhandled_key_input(event: InputEvent) -> void:
	if board_motion.busy:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if not modal_stack.is_empty() and modal_stack.back().title.begins_with("六相召唤阵"):
		if event.keycode == KEY_BACKSPACE:
			_undo_rune()
		elif event.keycode == KEY_ENTER:
			_commit_rune()
		elif event.keycode == KEY_ESCAPE and (not rules.draft.is_empty() or not board.selected_relic.is_empty()):
			_cancel_rune()
		elif event.keycode == KEY_ESCAPE:
			_close_modal()
		else:
			return
	elif event.keycode == KEY_ESCAPE:
		_close_modal()
	else:
		return
	get_viewport().set_input_as_handled()

func _notice(text: Variant) -> void:
	L10N.bind(status,&"text",text)
	if not modal_stack.is_empty():
		L10N.bind(modal_feedback,&"text",text)

func _text_screen(parent: Node, text: Variant) -> VBoxContainer:
	var page := TextPanel.instantiate()
	parent.add_child(page)
	L10N.bind(page.get_node("%Description"),&"text",text)
	return page

func _btn(parent: Node, text: Variant, callback: Callable, component: PackedScene = ActionButton) -> Button:
	var button := component.instantiate()
	L10N.bind(button,&"text",text)
	if component == ActionButton:
		button.theme_type_variation = &"SecondaryButton"
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _tasks() -> void:
	var done: bool = "event_traveler" in state.data.completed
	var summoned: bool = int(state.data.serial) > 0
	var team_count: int = state.monsters("team").size()
	_modal("旅途待办",func(body):
		var page := TasksPanel.instantiate()
		body.add_child(page)
		page.present_tasks([
			{"title":"旅人手记","description":"已收下手记中的魔力结晶。" if done else "阅读旅人留下的手记，收下魔力结晶。","done":done,"action":"event"},
			{"title":"完成一次召唤","description":"已完成首次召唤。" if summoned else "在召唤阵刻入符文，召唤你的妖兽。","done":summoned,"action":"summon"},
			{"title":"准备出战队伍","description":L10N.text("ui.222af74d3be3") % [team_count,State.TEAM_LIMIT],"done":team_count>0,"action":"party"}
		])
		page.action_requested.connect(_task_action),"tasks")

func _task_action(action: String) -> void:
	_close_all()
	match action:
		"event": _open_event("traveler")
		"summon": _open_ritual()
		"party": _warehouse("team")

func _settings() -> void:
	if board_motion.busy:
		return
	_modal("设置 / 保存 / 退出",func(body):
		var page := _text_screen(body,"ui.22bb36ae7f50")
		var toggle := _btn(page.get_node("%Commands"),func(): return L10N.text(L10N.text("ui.c66e646390a9") if animate_panels else L10N.text("ui.6827b4782982")),func():
			animate_panels = not animate_panels
			board_motion.enabled = animate_panels
			_update_motion_status()
			_render_modal())
		L10N.bind(toggle,&"tooltip_text","ui.a78503e1696e")
		var resolution := OptionButton.new()
		resolution.name = "WindowSize"
		resolution.custom_minimum_size.y = 42
		L10N.bind(resolution,&"tooltip_text","ui.df26663efad4")
		var presets: Array[Vector2i] = [Vector2i(1120,680),Vector2i(1280,720),Vector2i(1440,810),Vector2i(1600,900),Vector2i(1920,1080)]
		for preset in presets:
			resolution.add_item(L10N.text("ui.1b5462d24a94") % [preset.x,preset.y])
		resolution.select(presets.find(get_window().size))
		resolution.item_selected.connect(func(index):
			var area := DisplayServer.screen_get_usable_rect()
			var desired := presets[index]
			if area.size.x > 0 and area.size.y > 0:
				desired = desired.min(Vector2i(maxi(1120,area.size.x-32),maxi(680,area.size.y-64)))
			get_window().mode = Window.MODE_WINDOWED
			get_window().size = desired)
		page.get_node("%Commands").add_child(resolution)
		_btn(page.get_node("%Commands"),"ui.a3030bf8f16d",func(): _notice(func(): return L10N.text(L10N.text("ui.1bd91a7d0c53") if state.save() else state.last_error)))
		_btn(page.get_node("%Commands"),"ui.dbc0fe120d31",func(): _confirm("退出游戏？","退出前保存本原型进度。",func():
			if state.save():
				get_tree().quit()
			else:
				_notice(func(): return L10N.text(state.last_error)))))

func _fold(content: Control, rune_tab: bool) -> void:
	var other: Control = content.get_parent().get_node("Relics" if rune_tab else "References")
	var already_open := content.visible and not other.visible
	other.hide()
	other.modulate.a = 1.0
	content.show()
	rune_fold_open = rune_tab
	relic_fold_open = not rune_tab
	# Switching tabs does not move container-managed content or restart its layout.
	var old_tween: Tween = content.get_parent().get_meta("reference_fade") if content.get_parent().has_meta("reference_fade") else null
	if old_tween and old_tween.is_valid():
		old_tween.kill()
	content.modulate.a = 1.0
	if not already_open and animate_panels:
		content.modulate.a = 0.0
		var fade := content.create_tween()
		content.get_parent().set_meta("reference_fade",fade)
		fade.tween_property(content,"modulate:a",1.0,0.2)

func _capture_outgoing() -> void:
	if not animate_panels:
		return
	if page_tween:
		page_tween.kill()
	if is_instance_valid(outgoing_page):
		outgoing_page.queue_free()
	# Freeze the last rendered content. A duplicated container would reflow and lose
	# the hovered/pressed state on its first frame, making A2 change shape or flash.
	var picture := TextureRect.new()
	if DisplayServer.get_name() != "headless":
		var frame := get_viewport().get_texture().get_image()
		var region := Rect2i(main_content.get_global_rect()).intersection(Rect2i(Vector2i.ZERO,frame.get_size()))
		if region.has_area():
			picture.texture = ImageTexture.create_from_image(frame.get_region(region))
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	outgoing_page = picture
	outgoing_page.set_meta("source_mode",view.mode)
	outgoing_page.visible = true
	add_child(outgoing_page)
	outgoing_page.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	outgoing_page.position = main_content.global_position - global_position
	outgoing_page.size = main_content.size
	_ignore_visual_input(outgoing_page)
	outgoing_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(outgoing_page,overlay.get_index())

func _slide_outgoing() -> void:
	if not is_instance_valid(outgoing_page):
		return
	var target := outgoing_page
	var end_x: float = target.position.x + get_viewport_rect().size.x
	page_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	page_tween.tween_property(target,"position:x",end_x,0.45)
	page_tween.tween_callback(target.queue_free)

func _curtain(raising: bool) -> void:
	if curtain_tween:
		curtain_tween.kill()
	if is_instance_valid(curtain_snapshot):
		curtain_snapshot.queue_free()
	curtain_busy = false
	if not animate_panels or DisplayServer.get_name() == "headless":
		if not raising:
			view.configure("world",location,state.monsters("team"))
		return
	# Always lower the real large map, never a capture of the settlement or battlefield.
	curtain_snapshot = MapCurtain.instantiate()
	view.add_child(curtain_snapshot)
	curtain_snapshot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain_snapshot.configure("world",location,[])
	curtain_snapshot.set_unavailable_events(_completed_final_events())
	_ignore_visual_input(curtain_snapshot)
	curtain_snapshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain_snapshot.position.y = 0.0 if raising else -view.size.y
	curtain_busy = true
	_block_base(base,true)
	curtain_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	curtain_tween.tween_property(curtain_snapshot,"position:y",-view.size.y if raising else 0.0,0.5)
	curtain_tween.tween_callback(func():
		if not raising:
			view.configure("world",location,state.monsters("team"))
		curtain_snapshot.hide()
		curtain_busy = false
		_block_base(base,not modal_stack.is_empty()))

func _update_motion_status() -> void:
	get_window().title = "涌现 · UI跳转原型 0.7.12 · " + ("动效开启" if animate_panels else "简化动效")

func _ignore_visual_input(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_ignore_visual_input(child)

func _start_new() -> void:
	var before: Dictionary = state.data.duplicate(true)
	state.reset()
	if not state.save():
		state.data = before
		_notice(func(): return L10N.text(state.last_error))
		return
	rules.import_layout(state.data.layout)
	_close_all()
	_show("world")

func _perform_summon() -> void:
	if state.summon(rules,location,route):
		return_route = route
		_close_all()
		if state.data.pending.is_empty():
			_results()
		else:
			scene_requested.emit("summon",location)
			_show("eruption")
	else:
		_notice(func(): return L10N.text(state.last_error))


func _upgrade_stage() -> void:
	if state.unlock_next_stage(rules.export_layout()):
		rules.stage = state.data.array_stage
		_render_modal()
		_notice(func(): return L10N.text(L10N.text("ui.c82f0b8d483a") % Rules.cells(rules.stage).size()))
	else:
		_notice(func(): return L10N.text(state.last_error))


func _load_example(index: int) -> void:
	if index == 0:
		return
	var minimum_stage: int = [1,1,2,1,3,2,2,2][index]
	if rules.stage < minimum_stage:
		_notice(func(): return L10N.text(L10N.text("ui.c46af0106de4") % Rules.cells(minimum_stage).size()))
		return
	_confirm("载入测试构筑？","将替换当前未保存的符文、奇物与草稿，不扣费。召唤和保存仍需自己确认。",func():
		var sample = Rules.new()
		sample.stage = rules.stage
		if index == 7:
			for item in Experiment.RECIPE.runes:
				for c in item.cells:
					sample.extend(c)
				sample.commit()
			sample.place_relic("bone-die",[1,0])
		else:
			var id: String = ["","health","armor","giant","giant","multiply","tiny"][index]
			var copies: int = 4 if index==2 else 2 if index==4 else 1
			for i in copies:
				if not _place_sample_rune(sample,id):
					_notice("ui.acb765af04be")
					return
		rules.import_layout(sample.export_layout())
		_close_modal()
		_notice("ui.3cf9f3d54567"))


func _place_sample_rune(sample, id: String) -> bool:
	var definition := Rules.definition(id)
	for anchor in Rules.cells(sample.stage):
		for turn in 6:
			var shape := Rules.transformed(definition.cells,turn,false)
			var offset := [int(anchor[0])-int(shape[0][0]),int(anchor[1])-int(shape[0][1])]
			var path := Experiment._shift(shape,offset)
			var valid := true
			for c in path:
				valid = valid and sample.can_use(c)
			if valid:
				for c in path:
					sample.extend(c)
				return sample.commit()
	return false
