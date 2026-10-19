extends Node
## Existing paper UI is reused; this adapter owns no currency, inventory or file writes.
const SERVICE = preload("res://Scripts/Events/StoryService.gd")
const CATALOG = preload("res://Scripts/Events/StoryCatalog.gd")
const PANEL = preload("res://Modules/PaperUI/Scenes/UI/Screens/EventPanel.tscn")
var application: Node
var _automatic_elapsed := 0.0
var _selection: Array[String] = []
var _automatic_shown: Dictionary = {}
var _story_panel: Control

func reset_for_new_game() -> void:
	_automatic_shown.clear()
	_automatic_elapsed=0.0

func _ready() -> void: process_mode=Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	_automatic_elapsed+=delta
	if _automatic_elapsed<0.25: return
	_automatic_elapsed=0.0
	if application.phase!="world" or not is_instance_valid(application.delivery_map) or not application.ui.modal_stack.is_empty() or application.ui.curtain_busy: return
	if application.delivery_map.runtime.busy: return
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console!=null and console.is_console_open(): return
	var data: Dictionary = application.session.data
	var opening := SERVICE.entry(data,SERVICE.OPENING)
	if not opening.is_empty() and not opening.completed:
		open_event(SERVICE.OPENING,opening.context)
		return
	for id: String in data.get("story_events",{}).get("entries",{}):
		var current := SERVICE.entry(data,id)
		if current.get("resume",false) and not current.completed:
			open_event(id,current.context)
			return
	if SERVICE.due(data) and not _automatic_shown.has(SERVICE.GHOST):
		var bindings: Array = CATALOG.bindings(SERVICE.GHOST,application.session.delivery_version())
		if bindings.is_empty(): return
		var binding: Dictionary = bindings[0].duplicate(true)
		binding.trigger_mode="on_game_time"
		open_event(SERVICE.GHOST,binding)
		if not SERVICE.entry(application.session.data,SERVICE.GHOST).is_empty(): _automatic_shown[SERVICE.GHOST]=true

func location_events(source_id: String) -> Array:
	var rows: Array = []
	var data: Dictionary = application.session.data
	for id: String in CATALOG.flows():
		if id in ["AUX_GRASS_FOSTER","AUX_GRASS_SALGERT",SERVICE.OPENING]: continue
		if SERVICE.entry(data,id).get("completed",false): continue
		for binding: Dictionary in CATALOG.bindings(id,application.session.delivery_version(),application.session.event_parameters()):
			if binding.source_id!=source_id: continue
			var probe := data.duplicate(true)
			var error := SERVICE.open(probe,id,binding,application.session.event_parameters())
			# Locked follow-up city options must not reveal future stages prematurely.
			if id==SERVICE.GHOST and not SERVICE.due(data): continue
			if id=="QST_GRASS_012" and binding.entry_role=="return_city_enchanter" and not SERVICE.entry(data,id).get("flags",{}).get("await_enchanter",false): continue
			if id=="AUX_GRASS_ROVA" and not error.is_empty(): continue
			rows.append({"id":id,"context":binding,"error":error,"label":{"library":"图书馆","city_center":"城中心","engine_merchant":"购买扩充引擎","engine_ghost":"外行魔法师","return_city_enchanter":"寻找附魔魔法师","rova":"罗瓦"}.get(binding.entry_role,CATALOG.title(id))})
	return rows

func show_location(object: Dictionary) -> bool:
	var rows := location_events(str(object.id))
	if rows.is_empty(): return false
	var ui: Control = application.ui
	ui._modal(str(object.name),func(body):
		var panel := PANEL.instantiate()
		body.add_child(panel)
		panel.get_node("%Description").text="请选择要交谈或调查的事项。"
		for row: Dictionary in rows:
			var button: Button = ui._btn(panel.get_node("%Commands"),row.label,func():
				ui._close_all()
				open_event(row.id,row.context))
			button.disabled=not row.error.is_empty()
			button.tooltip_text=row.error
		ui._btn(panel.get_node("%Commands"),"返回地图",func():ui._close_modal()),"event")
	return true

func open_event(id: String, context: Dictionary) -> void:
	var ui: Control = application.ui
	if application.phase!="world": return
	if context.get("trigger_mode","interact")=="interact":
		var object: Dictionary = application.MAP_CATALOG.location(context.get("source_id",""))
		var error: String = application.delivery_map.runtime.interaction_error(object)
		if not error.is_empty(): ui._notice(error); return
	if not application.session.open_story_event(id,context): ui._notice(application.session.last_error); return
	application.trace_map_event("event_started",{"event_id":id,"source_id":context.get("source_id","")})
	_present(id)

func _present(id: String) -> void:
	var ui: Control = application.ui
	var current := SERVICE.entry(application.session.data,id)
	if current.completed:
		if not ui.modal_stack.is_empty() and ui.modal_stack.back().get("kind")=="story": ui._close_modal(false)
		ui.close_button.disabled=false
		application.trace_map_event("event_completed",{"event_id":id})
		application.delivery_map.sync_party()
		application.delivery_map._refresh_objects()
		ui._update_header()
		if id==SERVICE.OPENING: application._enable_world_tasks()
		return
	# Ordinary continuation keeps the same sheet, Label and ScrollContainer alive.
	if not ui.modal_stack.is_empty() and ui.modal_stack.back().get("event_id")==id and ui.modal_stack.back().get("kind")=="story" and is_instance_valid(_story_panel) and _story_panel.is_inside_tree():
		_refresh_story_panel(_story_panel,id)
		return
	if not ui.modal_stack.is_empty() and ui.modal_stack.back().get("kind")=="story": ui._close_modal(false)
	ui._modal(CATALOG.title(id),func(body):
		var panel := PANEL.instantiate()
		body.add_child(panel)
		_story_panel=panel
		_refresh_story_panel(panel,id)
		# Opening cannot be dismissed as completion. Settings and save/return still work.
		ui.close_button.disabled=id==SERVICE.OPENING,"story")
	ui.modal_stack.back()["event_id"]=id
	ui.close_button.disabled=id==SERVICE.OPENING

func _refresh_story_panel(panel: Control, id: String) -> void:
	var ui: Control = application.ui
	var current := SERVICE.entry(application.session.data,id)
	var revision: int = int(current.revision)
	var node: Dictionary = CATALOG.definition(id).nodes[current.node]
	var content: Label = panel.get_node("%Description")
	var previous_text: String = content.text
	var commands: Node = panel.get_node("%Commands")
	ui._clear(commands)
	var paragraphs: Array = node.get("paragraphs",[])
	content.text=SERVICE.prose(application.session.data,id)
	if content.text.is_empty(): content.text="请选择下一步。"
	if node.type=="dialogue":
		ui._btn(commands,"继续" if int(current.cursor)+1<paragraphs.size() else "阅读完成",func():_choose(id,"next",revision))
	elif node.type in ["action","choice"]:
		if id==SERVICE.BET: content.text+="\n\n第%d轮，本金%d魔力；获胜总返还为本金的2倍。" % [int(current.flags.get("settled_rounds",0))+1,[10,20,50,100][mini(3,int(current.flags.get("settled_rounds",0)))]]
		var options: Array = node.get("options",[])
		if node.type=="action": options=[{"id":"confirm","label":node.label,"action":node.action}]
		for option: Dictionary in options:
			var error := SERVICE.action_error(application.session.data,id,option.get("action",{}),application.session.event_parameters())
			var button: Button = ui._btn(commands,option.label,func():
				if option.get("action",{}).get("op")=="close": ui._close_modal(false); return
				if option.get("action",{}).get("op")=="sacrifice": _select_sacrifice(id,option,revision); return
				_choose(id,option.id,revision))
			button.disabled=not error.is_empty()
			button.tooltip_text=error
			if not error.is_empty(): content.text+="\n\n"+str(option.label)+"："+error
	else:
		content.text+="\n\n"+str(node.get("message","此步骤尚待配置。"))
		ui._btn(commands,"返回地图",func():ui._close_modal(false))
	if content.text!=previous_text: _scroll_to_latest(panel)

func _scroll_to_latest(panel: Control) -> void:
	# Layout is deferred; do not scroll against the old paragraph's height.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(panel) or not panel.is_inside_tree(): return
	var scroll: ScrollContainer = panel.get_node("%DescriptionScroll")
	scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value)

func _choose(id: String, choice: String, revision: int, selected: Array = []) -> void:
	if not application.session.advance_story_event(id,choice,revision,selected):
		application.ui._notice(application.session.last_error)
		application.trace_map_event("event_rejected",{"event_id":id,"reason":application.session.last_error})
		if application.ui.modal_stack.is_empty(): _present(id)
		return
	# The paper is no longer rebuilt on success; clear feedback from a failed retry.
	application.ui._notice("")
	application.trace_map_event("event_advanced",{"event_id":id,"choice":choice})
	application.ui.rules.stage=application.session.data.array_stage
	application.ui._update_header()
	if application.session.data.battle.get("kind")=="story" and application.session.data.battle.get("phase")=="loading":
		application.delivery_map.runtime.restore_snapshot(application.session.delivery_snapshot())
		application._delivery_battle_requested(application.session.data.battle.duplicate(true))
		return
	_present(id)

func _select_sacrifice(id: String, option: Dictionary, revision: int) -> void:
	_selection.clear()
	var ui: Control = application.ui
	ui._modal("确认献祭对象",func(body):
		var panel := PANEL.instantiate()
		body.add_child(panel)
		panel.get_node("%Description").text="将永久消耗选中的怪物。必须满足当前数量要求，且至少保留一只怪物。"
		for unit: Dictionary in SERVICE.candidates(application.session.data,int(option.action.stage)):
			var check := CheckButton.new()
			check.text=str(unit.name)+" · "+str(unit.id)
			panel.get_node("%Commands").add_child(check)
			check.toggled.connect(func(value):
				if value and unit.id not in _selection: _selection.append(unit.id)
				elif not value: _selection.erase(unit.id))
		ui._btn(panel.get_node("%Commands"),"确认永久献祭",func():
			var picked := _selection.duplicate()
			ui._confirm("确认不可逆献祭？","将永久消耗："+"、".join(picked),func():
				ui._close_all()
				_choose(id,option.id,revision,picked)))
		ui._btn(panel.get_node("%Commands"),"取消",func():ui._close_modal(false)),"event")

func task_rows() -> Array:
	var rows: Array = []
	for id: String in application.session.data.get("story_events",{}).get("entries",{}):
		var current := SERVICE.entry(application.session.data,id)
		if current.completed or id.begins_with("AUX_"): continue
		var node: Dictionary = CATALOG.definition(id).nodes[current.node]
		var description: String = node.get("label","返回事件地点继续交谈或处理当前事项。")
		if node.type=="blocked": description="本轮结果待处理，已保存当前进度。"
		elif current.flags.get("await_battle",false): description="等待本次战斗结果。"
		elif current.node=="return" and id=="QST_SIDE_002_001": description="清剿已完成，请返回城主处交付。"
		elif current.node=="waiting" and id=="QST_GRASS_012": description="前往萨尔格特城寻找附魔魔法师。"
		rows.append({"id":"event:"+id,"title":CATALOG.title(id),"description":description,"done":false,"locked":false,"action":"event:"+id})
	return rows

func navigate(id: String) -> void:
	var candidates := CATALOG.bindings(id,application.session.delivery_version(),application.session.event_parameters())
	if candidates.is_empty(): return
	var current := SERVICE.entry(application.session.data,id)
	var source: String = current.get("context",{}).get("source_id",candidates[0].source_id)
	if id=="QST_SIDE_002_001":
		for row: Dictionary in candidates:
			if row.entry_role==("city_center" if current.get("node")=="return" else "clear_target"): source=row.source_id
	if id=="QST_GRASS_012" and current.get("flags",{}).get("await_enchanter",false):
		for binding: Dictionary in candidates:
			if binding.entry_role=="return_city_enchanter": source=binding.source_id
	application.ui._close_all()
	application.delivery_map.request_location(source)
