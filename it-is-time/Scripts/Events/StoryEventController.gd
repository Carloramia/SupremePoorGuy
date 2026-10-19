extends Node
const CONTENT=preload("res://Scripts/Events/StoryEventContent.gd")
const PRESENTER=preload("res://Scripts/Events/StoryEventPresenter.gd")
const RESOURCES=preload("res://Scripts/Events/StoryEventResources.gd")
const PROFILES=preload("res://Scripts/Events/StoryCreatureProfiles.gd")
const HEX=preload("res://Scripts/Events/HexMapProgress.gd")
var application: Node
var content:=CONTENT.new()
var presenter:=PRESENTER.new()
var resources:=RESOURCES.new()
var profiles:=PROFILES.new()
var active_request: Dictionary={}
var active_site_id:=""
var uncommitted_result: Dictionary={}

func setup(host: Node) -> void:
	application=host
	add_child(presenter); presenter.setup(host)
	presenter.operation_requested.connect(execute)
	resources.item_definitions=profiles.definitions.items.duplicate(true)
	for id: String in ["reward_two_head_wolf","reward_magic_eye_beast"]: resources.monster_presets[id]=profiles.make(id,"template_"+id)
	_register_camps()

func _register_camps() -> void:
	var session=application.session
	var document:=HEX.document()
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://Content/Maps/HexFrontier_20261019/hex_battles.json"))
	for site: Dictionary in document.sites:
		if site.kind!="camp" or str(site.get("battle_map_id","")).is_empty(): continue
		var map: Dictionary={}
		for row: Dictionary in source.maps:
			if row.id==site.battle_map_id: map=row; break
		var ids: Array=[]
		var missing:=""
		for object: Dictionary in map.get("objects",[]):
			if object.type!="enemy": continue
			var species: String=str(object.get("definition_id","") if object.get("definition_id")!=null else object.get("monster_type",""))
			if not application.session.FACTORY.DEFINITIONS.has(species): missing="该地图的真实怪物模板尚未配置："+species; break
			var id: String="authored_"+site.id+"_"+str(ids.size())
			profiles.definitions.profiles[id]={"species":species,"scale":3.0 if object.get("monster_size")=="huge" else 1.5 if object.get("monster_size")=="large" else 1.0}
			for count: int in int(object.get("count",1)): ids.append(id)
		var event_id: String="CAMP_"+site.id
		if ids.is_empty() or not missing.is_empty(): continue
		session.story_events.definitions[event_id]={"id":event_id,"title":site.name,"entries":["camp"],"operations":{"battle":{"kind":"battle","next":"complete","battle":event_id,"reward":event_id}}}
		session.story_events.config.bindings.battles[event_id]={"battle_map_id":site.battle_map_id,"enemy_config_id":site.enemy_config_id,"profiles":ids,"site_id":site.id}
		session.story_events.config.bindings.rewards[event_id]={"magic":20,"runes":[],"relics":[]}

func arrived(site: Dictionary) -> void:
	if not application.story_presentation_safe(): return
	active_site_id=site.id
	if site.id=="layout_summoning_hut": application.ui._open_ritual(); return
	var entries:=content.bindings_for_site(site.id)
	var actual:=entries.filter(func(b):return not b.auxiliary and not application.session.story_event_view(b.event_id).get("completed",false))
	if site.id==profiles.definitions.defense_site_id:
		var defense: Dictionary=application.session.story_event_view("QST_SIDE_002_001")
		if defense.get("stage")=="active" and not defense.get("defense_won",false): _open("QST_SIDE_002_001","defense_target",site.id); return
	if site.kind=="town": _city_menu(site,actual); return
	if not actual.is_empty(): _open(actual[0].event_id,actual[0].entrance,site.id); return
	if site.kind=="camp": _camp_menu(site); return
	application.ui._modal(str(site.name),func(body):
		var screen: Control=application.ui._text_screen(body,"此处的探索已经结束。")
		application.ui._btn(screen.get_node("%Commands"),"返回地图",func(): application.ui._close_modal()))

func _city_menu(site: Dictionary, entries: Array) -> void:
	for binding: Dictionary in content.bindings_for_site(site.id,"on_game_time"):
		var state: Dictionary=application.session.story_event_view(binding.event_id)
		if not state.get("completed",false) and (state.get("triggered",false) or binding.event_id in application.session.ready_story_events(true)): entries.append(binding)
	application.ui._modal(str(site.name),func(body):
		var screen: Control=application.ui._text_screen(body,"选择要拜访的地点。")
		var commands: Node=screen.get_node("%Commands")
		for binding: Dictionary in entries:
			var id: String=binding.event_id; var entrance: String=binding.entrance
			if id=="QST_GRASS_012" and application.session.story_event_view(id).get("stage")!="await_enchanter": continue
			application.ui._btn(commands,application.session.story_event_view(id).title,func(): application.ui._close_modal(false); _open(id,entrance,site.id))
		if site.id=="layout_foster_town" and application.session.story_event_view("QST_SIDE_001_001").get("completed",false):
			application.ui._btn(commands,"图书馆 · 罗瓦",func(): application.ui._close_modal(false); _greeting())
		application.ui._btn(commands,"返回地图",func(): application.ui._close_modal()),"story_city")

func _greeting() -> void:
	application.ui._modal("罗瓦",func(body):
		var screen: Control=application.ui._text_screen(body,"怎么了，大英雄？")
		application.ui._btn(screen.get_node("%Commands"),"离开",func(): application.ui._close_modal()),"story_event")

func _open(id: String, entrance: String, site_id: String) -> void:
	if not application.session.record_story_arrival(id,entrance,"hex_frontier_20261019",site_id): application.ui._notice(application.session.last_error); return
	active_site_id=site_id
	presenter.open(id,entrance)

func _camp_menu(site: Dictionary) -> void:
	var id: String="CAMP_"+site.id
	if not application.session.story_events.definitions.has(id): application.ui._notice("此战场的怪物模板尚未接入。"); return
	var done: bool=application.session.story_event_view(id).get("completed",false)
	application.ui._modal(str(site.name),func(body):
		var screen: Control=application.ui._text_screen(body,"该地点已经清理。" if done else "确认使用当前出战队伍进入此战场？")
		var commands: Node=screen.get_node("%Commands")
		if not done:
			var button: Button=application.ui._btn(commands,"进入战斗",func():
				application.ui._close_modal(false)
				var opened: Dictionary=application.open_story_event(id,"camp")
				if not opened.ok: application.ui._notice(opened.error); return
				var result: Dictionary=application.session.story_event_action(id,"battle",opened.event.conversation)
				if result.ok: active_site_id=site.id; execute(result.request)
				else: application.ui._notice(result.error))
			button.disabled=application.session.monsters("team").is_empty()
			button.tooltip_text="需要先安排出战怪物。" if button.disabled else ""
		application.ui._btn(commands,"返回地图",func(): application.ui._close_modal()),"story_camp")

func _receipt(r: Dictionary, outcome: String="success") -> Dictionary:
	return {"request_id":r.request_id,"event_id":r.event_id,"stage":r.stage,"branch":r.branch,"kind":r.kind,"outcome":outcome,"committed":true}

func execute(request: Dictionary) -> void:
	if application.phase!="world": application.ui._notice("当前阶段无法执行事件操作。"); return
	var r: Dictionary=application.session.pending_story_request(request.event_id)
	if r.is_empty() or r.request_id!=request.request_id: application.ui._notice("事件请求已经失效。"); return
	if r.kind in ["battle","spectator"]:
		_start_battle(r)
		return
	if not application.session.commit_story_receipt(_receipt(r),resources.apply): application.ui._notice(application.session.last_error); return
	application.ui.rules.import_layout(application.session.data.layout)
	var next: Dictionary=application.session.pending_story_request(r.event_id)
	if not next.is_empty(): execute(next); return
	if r.event_id.begins_with("CAMP_"):
		application.ui._close_all(); return
	var state: Dictionary=application.session.story_event_view(r.event_id)
	var sequence: String="purchased" if r.kind=="purchase" else "success" if r.event_id=="QST_GRASS_010" else "wood" if r.event_id=="QST_GRASS_017" and r.branch=="wood" else ""
	if state.completed and sequence.is_empty(): application.ui._close_all(); return
	presenter.event_id=r.event_id; presenter.conversation=state.conversation
	presenter.pages=content.dialogue(r.event_id,state,sequence); presenter.page_index=0
	application.ui._close_all(); presenter._show()

func _start_battle(r: Dictionary) -> void:
	var left: Array=[]; var right: Array=[]; var battle_config: Dictionary={}
	if r.operation.kind=="bet":
		battle_config=r.plan.rosters.one
		left=profiles.roster(r.plan.rosters.one,r.battle_id+"_one")
		right=profiles.roster(r.plan.rosters.two,r.battle_id+"_two")
	elif r.kind=="spectator":
		battle_config=r.plan.battle
		left=profiles.roster(battle_config.other_side,r.battle_id+"_one")
		right=profiles.roster(battle_config,r.battle_id+"_two")
	else:
		battle_config=r.plan.battle
		left=application.session.monsters("team").duplicate(true)
		right=profiles.roster(battle_config,r.battle_id+"_two")
	if left.is_empty() or right.is_empty(): application.ui._notice("双方实际阵容不完整，未开始战斗。"); return
	if r.plan.has("frozen_rosters"):
		left=r.plan.frozen_rosters.left.duplicate(true); right=r.plan.frozen_rosters.right.duplicate(true)
	else:
		if not application.session.freeze_story_rosters(r,left,right): application.ui._notice(application.session.last_error); return
		r=application.session.pending_story_request(r.event_id)
	active_request=r.duplicate(true)
	active_site_id=r.plan.get("source_site_id",active_site_id)
	if r.event_id.begins_with("CAMP_"): active_site_id=r.plan.battle.site_id
	application.start_story_battle(r,{"battle_map_id":battle_config.battle_map_id,"mode":"spectator" if r.kind=="spectator" else "player"},left,right)

func battle_finished(result: Dictionary) -> void:
	var r:=active_request
	if r.is_empty() or r.battle_id!=result.battle_id: return
	uncommitted_result=result.duplicate(true)
	application.phase="settlement"
	application.refresh_input_gate()
	var receipt:=_receipt(r,result.outcome)
	receipt["battle_id"]=result.battle_id
	if result.has("winner"): receipt["winner"]=result.winner
	if not application.session.commit_story_battle(receipt,result,active_site_id):
		application.ui._modal("结算保存失败",func(body):
			var screen: Control=application.ui._text_screen(body,application.session.last_error)
			application.ui._btn(screen.get_node("%Commands"),"重试保存",func():battle_finished(result)))
		return
	uncommitted_result={}
	application.phase="settlement"
	application.refresh_input_gate()
	application.ui._close_all()
	application.ui._modal("战斗结算",func(body):
		var label: String={"victory":"胜利","defeat":"失败","draw":"平局","retreat":"撤退","load_failed":"载入失败","interrupted":"中止"}.get(result.outcome,result.outcome)
		var screen: Control=application.ui._text_screen(body,"结果："+label+"\n确认后返回大地图并提交本阶段奖励。")
		application.ui._btn(screen.get_node("%Commands"),"返回大地图",func():
			application.finish_story_battle()
			active_request={}
			_after_battle(r,result)),"story_settlement")
	application.ui.close_button.disabled=true

func _after_battle(r: Dictionary, result: Dictionary) -> void:
	var sequence: String=""
	if result.outcome=="victory":
		sequence="victory" if r.event_id in ["QST_GRASS_011","QST_GRASS_016"] else "direct_victory" if r.event_id=="QST_GRASS_012" else ""
	if r.kind=="spectator": sequence="settled" if r.operation.kind=="bet" else "spectator_end"
	var pages:=content.dialogue(r.event_id,application.session.story_event_view(r.event_id),sequence) if not sequence.is_empty() else []
	var next: Dictionary=application.session.pending_story_request(r.event_id)
	if pages.is_empty():
		if not next.is_empty(): execute(next)
		return
	_result_page(r.event_id,pages,0,next)

func _result_page(id: String, pages: Array, index: int, next: Dictionary) -> void:
	var page: Dictionary=pages[index]
	application.ui._modal(application.session.story_event_view(id).title,func(body):
		var screen: Control=application.ui._text_screen(body,(page.speaker+"：\n" if not page.speaker.is_empty() else "")+page.text)
		application.ui._btn(screen.get_node("%Commands"),"继续" if index<pages.size()-1 else "确认",func():
			application.ui._close_modal(false)
			if index<pages.size()-1: _result_page(id,pages,index+1,next)
			elif not next.is_empty(): execute(next)),"story_result")

func resume_pending() -> void:
	for id: String in application.session.data.get("story_events",{}).get("entries",{}):
		var request: Dictionary=application.session.pending_story_request(id)
		if request.is_empty(): continue
		application.ui._modal("继续未完成的事件",func(body):
			var screen: Control=application.ui._text_screen(body,"已有保存的事件请求，阵容、消耗与奖励不会重新抽取。")
			application.ui._btn(screen.get_node("%Commands"),"继续",func():application.ui._close_modal(false);execute(request))
			application.ui._btn(screen.get_node("%Commands"),"稍后",func():application.ui._close_modal()),"story_resume")
		return
