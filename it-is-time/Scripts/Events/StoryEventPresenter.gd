extends Node
## Uses the existing paper screen; explicit page completion precedes choices.
signal operation_requested(request: Dictionary)
const CONTENT = preload("res://Scripts/Events/StoryEventContent.gd")
var application: Node
var content := CONTENT.new()
var event_id := ""
var conversation := ""
var pages: Array = []
var page_index := 0
var selected_monsters: Array = []

func setup(host: Node) -> void:
	application = host
	host.story_event_entry_ready.connect(open)
	host.story_event_due.connect(_due)

func _due(ids: Array) -> void:
	if ids.is_empty() or not application.story_presentation_safe(): return
	var id: String = ids[0]
	open(id,"tree" if id=="QST_GRASS_002" else "ghost")

func open(id: String, entrance: String) -> void:
	var result: Dictionary = application.open_story_event(id,entrance)
	if not result.ok: application.ui._notice(result.error); return
	event_id = id
	conversation = result.event.conversation
	selected_monsters.clear()
	pages = content.dialogue(id,result.event)
	page_index = 0
	_show()

func _show() -> void:
	var state: Dictionary = application.session.story_event_view(event_id)
	var text := ""
	if page_index<pages.size():
		var page: Dictionary = pages[page_index]
		text = (page.speaker+"：\n" if not page.speaker.is_empty() else "")+page.text
	application.ui._modal(state.title,func(body):
		var screen: Control = application.ui._text_screen(body,text)
		var commands: Node = screen.get_node("%Commands")
		if page_index<pages.size()-1:
			application.ui._btn(commands,"继续",func(): page_index+=1; _replace())
		else:
			var request: Dictionary = application.session.pending_story_request(event_id)
			if not request.is_empty():
				application.ui._btn(commands,"继续未完成的操作",func(): _dispatch(request))
			else:
				for branch: String in state.branches:
					var button: Button = application.ui._btn(commands,content.branch_label(event_id,branch,state),_choose.bind(branch))
					button.name = "StoryChoice_"+branch
					if branch not in ["first","second","third"]:
						var probe: Dictionary = application.session.story_events.act(application.session.data.duplicate(true),event_id,branch,conversation)
						button.disabled = not probe.ok
						button.tooltip_text = probe.get("error","")
		application.ui._btn(commands,"离开",_leave),"story_event")

func _replace() -> void:
	application.ui._close_modal(false)
	_show()

func _leave() -> void:
	if application.session.pending_story_request(event_id).is_empty():
		application.session.story_event_action(event_id,"leave",conversation)
	application.ui._close_modal(false)

func _choose(branch: String) -> void:
	if branch in ["first","second","third"]:
		_select_sacrifice(branch)
		return
	var result: Dictionary = application.session.story_event_action(event_id,branch,conversation)
	if not result.ok: application.ui._notice(result.error); return
	if branch=="away": application.ui._close_modal(false); return
	if result.has("request"):
		_dispatch(result.request)
		return
	var state: Dictionary = application.session.story_event_view(event_id)
	if state.get("completed",false): application.ui._close_modal(false); return
	pages = content.dialogue(event_id,state,branch if branch in ["funny","kind"] else "")
	page_index = 0
	_replace()

func _select_sacrifice(branch: String) -> void:
	application.ui._close_modal(false)
	application.ui._modal("选择献祭怪物",func(body):
		var screen: Control = application.ui._text_screen(body,"请选择本次献祭的怪物。确认后将永久消耗；献祭后必须至少保留一只。")
		var commands: Node = screen.get_node("%Commands")
		for monster: Dictionary in application.session.monsters():
			if monster.position not in ["team","warehouse"]: continue
			var instance_id: String = monster.id
			var button: Button = application.ui._btn(commands,("✓ " if instance_id in selected_monsters else "")+str(monster.name),func():
				if instance_id in selected_monsters: selected_monsters.erase(instance_id)
				else: selected_monsters.append(instance_id)
				_select_sacrifice(branch))
			button.name = "Sacrifice_"+instance_id
		var payload := {"monster_ids":selected_monsters.duplicate(),"confirmed":true}
		var probe: Dictionary = application.session.story_events.act(application.session.data.duplicate(true),event_id,branch,conversation,payload)
		var confirm: Button = application.ui._btn(commands,"确认永久献祭",func():
			var result: Dictionary = application.session.story_event_action(event_id,branch,conversation,payload)
			if result.ok: _dispatch(result.request)
			else: application.ui._notice(result.error))
		confirm.disabled = not probe.ok
		confirm.tooltip_text = probe.get("error","")
		application.ui._btn(commands,"取消",func(): selected_monsters.clear(); _replace()),"story_event")

func _dispatch(request: Dictionary) -> void:
	if operation_requested.get_connections().is_empty():
		application.ui._notice("此事件的正式操作服务尚未接入，已保留当前请求。")
		return
	operation_requested.emit(request.duplicate(true))
