extends Control
## Flow controller only. Visual structure belongs to Scenes/UI and Assets/UI.
@export var animate_panels := true
signal location_interaction_requested(location_id: String, kind: String)
signal scene_requested(kind: String, location_id: String)
signal party_changed(monster_ids: Array)
const Experiment = preload("res://Scripts/SummonExperiment.gd")
const State = preload("res://Scripts/PrototypeState.gd")
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
const ActionButton = preload("res://Scenes/UI/Components/ActionButton.tscn")
const StatButton = preload("res://Scenes/UI/Components/StatButton.tscn")
const RelicButton = preload("res://Scenes/UI/Components/RelicButton.tscn")
const RuneReference = preload("res://Scenes/UI/Components/RuneReferenceRow.tscn")
const ActiveRune = preload("res://Scenes/UI/Components/ActiveRuneRow.tscn")
const RitualPanel = preload("res://Scenes/UI/Screens/RitualPanel.tscn")
const MonsterCard = preload("res://Scenes/UI/Components/MonsterCard.tscn")
const ResultCard = preload("res://Scenes/UI/Components/MonsterResultCard.tscn")
const MonsterDetail = preload("res://Scenes/UI/Screens/MonsterDetail.tscn")
const ResultsPanel = preload("res://Scenes/UI/Screens/ResultsPanel.tscn")
const WarehouseBook = preload("res://Scripts/UI/WarehouseBook.gd")
const WarehousePanel = preload("res://Scenes/UI/Screens/WarehousePanel.tscn")
const TextPanel = preload("res://Scenes/UI/Screens/TextPanel.tscn")
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
var modal_box: VBoxContainer
var modal_title: Label
var close_button: Button
var modal_scroll: ScrollContainer
var modal_feedback: Label
var ritual_columns: HBoxContainer
var ritual_left_scroll: ScrollContainer
var ritual_right_scroll: ScrollContainer
var board
var ritual_summary: Label
var active_list: VBoxContainer
var warehouse_page
var warehouse_selected_id := ""
var ritual_page: Control
var summon_button: Button
const LOCATION_NAMES = {"grassland":"草原 · 荒原兽群", "forest":"森林 · 蛛树守卫", "desert":"沙漠 · 沙丘遗迹"}
const LOCATION_TAGS = {"grassland":"【草原】【干旱】", "forest":"【森林】【潮湿】", "desert":"【沙漠】【沙】"}
const TERMS = {"生命":"可承受伤害的总量。本版本仅展示，不模拟真实战斗。", "攻击":"普通攻击的基础强度。当前为测试数值。", "护甲":"抵抗攻击的能力。真实减伤公式由战斗模块接入。", "移速":"移动速度。当前仅作为怪物属性展示。", "灼烧":"攻击留下持续余火；当前仅展示能力说明。", "相邻":"两个蜂窝共享一条边。停用符文仍占格，删除才释放。"}

func _ready() -> void:
	state.load_save()
	rules.import_layout(state.data.layout)
	_build()
	_show("main")

func _build() -> void:
	base = %AppShell
	root_layout = base.get_node("%Layout")
	main_content = base.get_node("%MainContent")
	party_panel = base.get_node("%PartySidebar")
	sidebar = party_panel.get_node("%Members")
	party_panel.get_node("%Manage").pressed.connect(func(): _warehouse())
	header = base.get_node("%Header")
	status = base.get_node("%Status")
	actions = base.get_node("%Actions")
	base.get_node("%Warehouse").pressed.connect(func(): _warehouse())
	base.get_node("%Party").pressed.connect(func(): _warehouse("team"))
	base.get_node("%Dictionary").pressed.connect(_book)
	base.get_node("%Help").pressed.connect(_help)
	view = base.get_node("%WorldView")
	view.location_clicked.connect(_location_clicked)
	view.ritual_requested.connect(_open_ritual)
	view.eruption_finished.connect(_eruption_done)
	overlay = %ModalHost
	board_motion = overlay.get_node("%BoardMotion")
	board_motion.enabled = animate_panels
	board_motion.completed.connect(_motion_completed)
	modal_box = overlay.get_node("%Body")
	modal_title = overlay.get_node("%Title")
	modal_scroll = overlay.get_node("%Scroll")
	modal_feedback = overlay.get_node("%Feedback")
	close_button = overlay.get_node("%Close")
	close_button.pressed.connect(_close_modal)
	overlay.hide()

func _show(next: String) -> void:
	route = next
	_clear(actions)
	_refresh_sidebar()
	view.configure("world" if next in ["main","world"] else "battle",location,state.monsters("team"))
	match next:
		"main":
			_btn(actions,"进入旅途",func(): _show("world"))
			if not state.data.pending.is_empty():
				_btn(actions,"安置上次召唤",_resume_pending)
			status.text = "涌现　|　编织法阵，召唤你的妖兽。"
		"world":
			_btn(actions,"当前地点 · "+LOCATION_NAMES[location],func(): _term("当前地点",LOCATION_TAGS[location]+"\n召唤按实际所在地点计算，不随查看远处地点变化。"))
			status.text = "选择地图上的地点；右下角的书本可打开召唤法典。"
		"battle":
			_btn(actions,"绘制召唤阵",_open_ritual)
			_btn(actions,"管理出战队列",func(): _warehouse("team"))
			var skip := _btn(actions,"跳过战斗",_skip_battle)
			skip.disabled = state.monsters("team").is_empty()
			skip.tooltip_text = "请先至少加入一只出战怪物" if skip.disabled else "测试模式：直接取得胜利"
			_btn(actions,"返回大地图",func(): _show("world"))
			status.text = LOCATION_NAMES[location]+"  "+LOCATION_TAGS[location]+"　|　先管理队伍，再进行战斗。"
		"eruption":
			view.erupt()
			_btn(actions,"跳过召唤演出",func(): view.skip_eruption())
			status.text = "法阵喷涌 · 妖兽正在显形"
	_update_header()
	if is_instance_valid(overlay) and overlay.visible:
		_block_base(base,true)

func _update_header() -> void:
	header.text = "涌现　/　魔力 %d　 ·　出战 %d只 · 队位 %d / %d · 试验0.6" % [state.data.magic,state.monsters("team").size(),state.occupied_slots(),State.TEAM_LIMIT]

func _refresh_sidebar() -> void:
	_clear(sidebar)
	party_panel.get_node("%Count").text = "%d只 · %d/%d队位" % [state.monsters("team").size(),state.occupied_slots(),State.TEAM_LIMIT]
	party_panel.get_node("%Empty").visible = state.monsters("team").is_empty()
	party_panel.get_node("%StorageCount").text = "仓库 %d 只" % state.monsters("warehouse").size()
	for monster in state.monsters("team"):
		var b := _btn(sidebar,monster.name,func(): _detail(monster.id))
		b.tooltip_text = "生命 %d · 攻击 %d · 护甲 %d\n%s" % [monster.hp,monster.attack,monster.armor," / ".join(monster.traits)]
	if is_instance_valid(overlay) and overlay.visible:
		_block_base(sidebar,true)

func _location_clicked(id: String, kind: String) -> void:
	if route not in ["main","world"] or not modal_stack.is_empty():
		return
	location_interaction_requested.emit(id,kind)
	if kind == "event":
		_open_event(id)
	else:
		_modal("战斗地点",func(body):
			var page := _text_screen(body,LOCATION_NAMES[id]+"\n"+LOCATION_TAGS[id]+"\n守卫：3 只未知妖兽\n进入后可管理队伍、召唤，随后跳过战斗。")
			_btn(page.get_node("%Commands"),"进入战斗场景",func():
				location = id
				_close_all()
				scene_requested.emit("battle",id)
				_show("battle")))

func _open_event(id: String) -> void:
	_modal("旅人手记",func(body):
		var page := _text_screen(body,"草叶间压着一册被雨水浸湿的手记。\n\n“阵中的笔画并非装饰。让每条线找到它的位置，力量便会自行成形。”\n\n你收起夹在书页中的魔力结晶。")
		var claim := _btn(page.get_node("%Commands"),"收下结晶 · 魔力 +20",func():
			if state.claim_once("event_"+id,20):
				_close_all()
				_show("world")
				status.text = "已获得 20 魔力，旅人手记已记录。"
			else:
				_notice(state.last_error))
		claim.disabled = "event_"+id in state.data.completed
		claim.tooltip_text = "已读 · 奖励已领取" if claim.disabled else "领取一次性测试奖励")

func _skip_battle() -> void:
	_modal("战斗胜利",func(body):
		var page := _text_screen(body,LOCATION_NAMES[location]+" · 守卫已退去\n\n测试战斗已跳过，不产生虚构战斗统计。\n奖励：魔力 +20")
		var received: bool = "battle_"+location in state.data.completed
		_btn(page.get_node("%Commands"),"返回大地图" if received else "领取奖励并返回",func():
			if received or state.claim_once("battle_"+location,20):
				_close_all()
				_show("world")
				status.text = "已返回大地图。" if received else "胜利奖励：魔力 +20。"
			else:
				_notice(state.last_error)))

func _open_ritual() -> void:
	if not state.data.pending.is_empty():
		_resume_pending()
		return
	_modal("六相召唤阵　·　"+LOCATION_TAGS[location],_build_ritual)

func _build_ritual(body: VBoxContainer) -> void:
	var page := RitualPanel.instantiate()
	body.add_child(page)
	ritual_page = page
	page.get_node("%Upgrade").pressed.connect(_upgrade_stage)
	page.get_node("%Upgrade").disabled = rules.stage>=4
	page.get_node("%Examples").item_selected.connect(_load_example)
	page.get_node("%TrialInfo").pressed.connect(func(): _term("试验参数与定向配方",Experiment.trial_notes()+"\n\n定向配方：甲片(-2,0)→(-1,0)，血脉(-1,1)→(0,1)→(1,1)，锐牙(0,-1)→(0,0)→(1,-1)，骨骰(1,0)(2,0)。只匹配完整配方；允许整体平移/旋转/镜像。\n可使用测试构筑载入查看，无额外笔画。"))
	ritual_columns = page.get_node("%Columns")
	ritual_left_scroll = page.get_node("%LeftScroll")
	ritual_right_scroll = page.get_node("%RightScroll")
	active_list = page.get_node("%ActiveList")
	board = page.get_node("%Board")
	board.rules = rules
	board.changed.connect(_refresh_ritual)
	board.notice.connect(_notice)
	for relic in Rules.RELICS:
		var tile := RelicButton.instantiate()
		tile.relic_id = relic.id
		tile.text = relic.name+" · %d 格" % relic.cells.size()
		tile.tooltip_text = relic.effect
		tile.pressed.connect(func():
			board.selected_relic = relic.id
			board.queue_redraw()
			_notice("已选择 "+relic.name+"，点击空闲蜂窝放置"))
		page.get_node("%Relics").add_child(tile)
	for rune in Rules.RUNES:
		var row := RuneReference.instantiate()
		row.get_node("%Preview").preview_path = rune.cells
		row.get_node("%Open").text = rune.name+" · %d 格" % rune.cells.size()
		row.get_node("%Effect").text = rune.effect
		row.get_node("%Open").pressed.connect(func(): _term(rune.name,rune.effect+"\n"+rune.detail))
		page.get_node("%References").add_child(row)
	ritual_summary = page.get_node("%Summary")
	summon_button = page.get_node("%Summon")
	summon_button.pressed.connect(_summon)
	page.get_node("%Commit").pressed.connect(_commit_rune)
	page.get_node("%Undo").pressed.connect(_undo_rune)
	page.get_node("%Cancel").pressed.connect(_cancel_rune)
	page.get_node("%Freehand").toggled.connect(func(value): board.freehand = value)
	page.get_node("%Save").pressed.connect(func():
		_notice("法阵已保存" if state.save_layout(rules.export_layout()) else state.last_error))
	page.get_node("%Clear").pressed.connect(func(): _confirm("清空当前法阵？","删除所有符文、奇物和草稿；已保存的布局不会改变，直到再次保存。",func():
		rules.import_layout({"version":3,"stage":state.data.array_stage,"placed":[],"placedRelics":[]})
		_close_modal()))
	_refresh_ritual()

func _commit_rune() -> void:
	if not rules.commit():
		_notice("笔画尚未形成已知符文，请继续绘制或撤回")
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
		toggle.text = d.name
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
		_btn(active_list,"回收 · "+d.name,func():
			rules.remove(item.uid)
			_refresh_ritual())
	var preview := Experiment.preview(rules)
	ritual_summary.text = "法阵%d阶 · %d格　/　魔力%d　/　消耗%d　/　预计%d段 · %d只 · %d队位\n试验参数；符文与奇物同价。停用收费但不提段。草稿%d格。" % [rules.stage,Rules.cells(rules.stage).size(),state.data.magic,preview.cost,preview.tier,preview.count,preview.total_slots,rules.draft.size()]
	summon_button.text = "确认召唤 · %d只%s" % [preview.count,"超巨化" if preview.mode=="ultra" else "定向" if preview.mode=="special" else ""]
	summon_button.disabled = count == 0 or not rules.draft.is_empty() or preview.cost > state.data.magic or not preview.error.is_empty()
	summon_button.tooltip_text = preview.error if not preview.error.is_empty() else "召唤确认时一次扣费。畸变失败不返费（试验口径）。"
	var risk: Label = ritual_page.get_node("%Risk")
	risk.visible = not preview.sources.is_empty()
	var sources: Array[String] = []
	for source in preview.sources:
		sources.append("%s ×%d / 门槛%d；独立风险%.0f%%" % [source.name,source.count,source.threshold,source.chance*100])
	risk.text = "畸变风险（试验）：%s\n每只分别判断：触发%.0f%%，失败%.0f%%；成功放大对应符文。%s" % [" / ".join(sources),preview.mutation_chance*100,preview.failure_chance*100,"超巨化仅1只占5队位；失败90%，不返费。" if preview.mode=="ultra" else "失败不返费；可部分失败。"]
	risk.tooltip_text = "\n".join(sources)+"\n"+Experiment.trial_notes()

	board.queue_redraw()

func _summon() -> void:
	var preview := Experiment.preview(rules)
	if not preview.sources.is_empty():
		_confirm("确认风险召唤","本次消耗 %d 魔力，尝试 %d 只；每只失败概率 %.0f%%（试验参数）。\n失败不返费；成功可能出现强化对应符文的畸变体。" % [preview.cost,preview.count,preview.failure_chance*100],_perform_summon)
	else:
		_perform_summon()

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
		_notice(state.last_error)

func _upgrade_stage() -> void:
	if state.unlock_next_stage(rules.export_layout()):
		rules.stage = state.data.array_stage
		_render_modal()
		_notice("已模拟剧情/Boss事件，法阵扩至%d格；没有额外消耗魔力。" % Rules.cells(rules.stage).size())
	else:
		_notice(state.last_error)

func _load_example(index: int) -> void:
	if index == 0:
		return
	var minimum_stage: int = [1,1,2,1,3,2,2,2][index]
	if rules.stage < minimum_stage:
		_notice("该测试构筑需要%d格，请先使用模拟剧情解锁按钮。" % Rules.cells(minimum_stage).size())
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
					_notice("测试图形无法放入当前法阵")
					return
		rules.import_layout(sample.export_layout())
		_close_modal()
		_notice("测试构筑已载入，可继续修改或确认召唤。"))

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
		page.get_node("%Hint").text = "尝试%d只 · 成功%d只 · 失败%d只 · 消耗%d魔力\n选择出战或入库；关闭将未安置者入库。试验规则：畸变失败不返费。" % [report.get("attempted",state.data.pending.size()),report.get("succeeded",state.data.pending.size()),report.get("failed",0),report.get("cost",0)]
		for id in state.data.pending.duplicate():
			_monster_card(page.get_node("%Cards"),state.monster_by_id(id),true)
		page.get_node("%Empty").visible = state.data.pending.is_empty()
		page.get_node("%StoreAll").pressed.connect(func():
			if state.store_pending():
				_close_all()
				_show(route)
			else:
				_notice(state.last_error)))

func _warehouse(filter: String = "warehouse") -> void:
	_modal("妖兽仓库　/　左右书页",func(body):
		var page := WarehousePanel.instantiate()
		body.add_child(page)
		warehouse_page = page
		page.setup(state,filter,warehouse_selected_id)
		page.changed.connect(func():
			warehouse_selected_id = page.selected_id
			_refresh_sidebar()
			_update_header()
			var ids: Array = []
			for unit in state.monsters("team"):
				ids.append(unit.id)
			party_changed.emit(ids))
		page.notice.connect(_notice)
		page.term_requested.connect(func(title,content):
			warehouse_selected_id = page.selected_id
			page.reading_scroll = page.get_node("%RightScroll").scroll_vertical
			modal_stack.back()["selected_id"] = page.selected_id
			modal_stack.back()["reading_scroll"] = page.reading_scroll
			modal_stack.back()["filter"] = page.filter
			modal_stack.back()["search"] = page.get_node("%Search").text
			modal_stack.back()["sort"] = page.get_node("%Sort").selected
			modal_stack.back()["advanced"] = page.get_node("%Advanced").button_pressed
			modal_stack.back()["left_scroll"] = page.get_node("%LeftScroll").scroll_vertical
			modal_stack.back()["filters"] = [page.get_node("%TierFilter").selected,page.get_node("%ShapeFilter").selected,page.get_node("%MutationFilter").selected]
			_term(title,content))
		var entry: Dictionary = modal_stack.back()
		if entry.has("selected_id"):
			page.selected_id = entry.selected_id
			page.filter = entry.filter
			page.get_node("%Search").text = entry.search
			page.get_node("%Sort").select(entry.sort)
			page.get_node("%Advanced").button_pressed = entry.advanced
			for i in 3:
				page.get_node("%"+["TierFilter","ShapeFilter","MutationFilter"][i]).select(entry.filters[i])
			page.refresh()
			page.restore_reading_position(entry.left_scroll,entry.reading_scroll))

func _monster_card(parent: Node, monster: Dictionary, result_card: bool) -> void:
	var card := ResultCard.instantiate() if result_card else MonsterCard.instantiate()
	parent.add_child(card)
	card.get_node("%Portrait").form = monster.form
	card.get_node("%Portrait").tint = Color(monster.color)
	card.get_node("%Name").text = monster.name
	card.get_node("%State").text = "%s · %d段 · %s · %s" % [monster.form,monster.tier,WarehouseBook.slot_text(monster),{"pending":"待安置","warehouse":"仓库","team":"出战"}[monster.position]]
	for pair in [["生命",monster.hp],["攻击",monster.attack],["护甲",monster.armor],["移速",monster.speed]]:
		_btn(card.get_node("%Stats"),"%s %s" % [pair[0],pair[1]],func(): _term(pair[0],TERMS[pair[0]]),StatButton)
	for ability_name in monster.traits:
		_btn(card.get_node("%Traits"),"【%s】" % ability_name,func(): _trait(ability_name))
	card.get_node("%Detail").pressed.connect(func(): _detail(monster.id))
	var to_team: bool = monster.position != "team"
	var move: Button = card.get_node("%Move")
	move.text = "整组出战" if to_team and monster.mode=="tiny" else "整组入库" if monster.mode=="tiny" else "加入出战" if to_team else "撤回仓库"
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
			_notice(state.last_error))
	move.disabled = to_team and not state.can_join(monster.id)
	move.tooltip_text = "队位不足，请先撤回其他妖兽" if move.disabled else ""
	if result_card:
		card.get_node("%Store").pressed.connect(func():
			if state.move_monster(monster.id,"warehouse"):
				_close_modal(false)
				_results()
			else:
				_notice(state.last_error))

func _detail(id: String) -> void:
	_modal("妖兽详情",func(body):
		var monster := state.monster_by_id(id)
		var page := MonsterDetail.instantiate()
		body.add_child(page)
		page.get_node("%Portrait").form = monster.form
		page.get_node("%Portrait").tint = Color(monster.color)
		page.get_node("%Name").text = monster.name
		page.get_node("%Identity").text = "%d段 · %s · %s" % [monster.tier,WarehouseBook.mode_text(monster.mode),WarehouseBook.slot_text(monster)]
		page.get_node("%Parts").text = "部位耐久提案：头部%d / 核心%d / 肢体%d；尚未接入战损。" % [monster.part_hp["头部"],monster.part_hp["核心"],monster.part_hp["肢体"]]
		page.get_node("%Contributions").text = "召唤后属性固定，不能永久成长。"
		page.get_node("%Source").text = "缩小群体不可回收。" if not monster.recoverable else "胜利时本场战死本体回收%d魔力（战斗接口尚未接入）。" % (monster.tier-1)
		page.get_node("%Stats").text = "生命 %d　攻击 %d　护甲 %d\n攻击周期 %.2f秒　移速 %.1f\n来源：%s · 投入%d魔力" % [monster.hp,monster.attack,monster.armor,monster.interval,monster.speed,LOCATION_NAMES.get(monster.get("source_location","grassland"),"未知地点"),monster.source_cost]
		var name_input: LineEdit = page.get_node("%NameInput")
		name_input.text = monster.name
		page.get_node("%Save").pressed.connect(func():
			if state.rename_monster(id,name_input.text):
				_refresh_sidebar()
				_render_modal()
			else:
				_notice(state.last_error if not state.last_error.is_empty() else "名称不能为空"))
		for ability_name in monster.traits:
			_btn(page.get_node("%Traits"),"【%s】 查看特性说明" % ability_name,func(): _trait(ability_name)))

func _book() -> void:
	_modal("符文辞典",func(body):
		var page := _text_screen(body,"试验版：十四枚候选符文全部开放。名称、效果数值与配方尚未定案。")
		for rune in Rules.RUNES:
			_btn(page.get_node("%Commands"),rune.name+" / "+rune.effect,func(): _term(rune.name,rune.detail))
		for term in TERMS:
			_btn(page.get_node("%Terms"),term,func(): _term(term,TERMS[term])))

func _trait(name_text: String) -> void:
	for rune in Rules.RUNES:
		if rune.name == name_text:
			_term(name_text,rune.effect+"\n"+rune.detail+"\n\n属性加成已经用于生成；触发型战斗能力仅保存接口数据，未接入实战。")
			return

func _term(title: String, content: String) -> void:
	_modal(title,func(body):
		var page := _text_screen(body,content)
		for term in TERMS:
			if term != title and term in content:
				_btn(page.get_node("%Terms"),"解释 · "+term,func(): _term(term,TERMS[term])))

func _help() -> void:
	_term("旅途指南","大地图上点击战斗或事件图标。右下角书本打开召唤法典。\n召唤：照符文书在相邻蜂窝描画，刻入后点击确认召唤。\n喷涌结束后，将妖兽加入出战队列或仓库。队列试验上限6队位；巨化2位、超巨化5位、缩小同批整组1位。\n战斗场景中先管理队伍，再跳过战斗并领取测试奖励。\n\nEsc 返回最上层。法阵内 Esc 优先取消笔画；Enter 刻入，Backspace 撤回。\n怪物与奖励自动保存在此独立原型的用户目录，不读取正式项目存档。")

func _confirm(title: String, text: String, callback: Callable) -> void:
	_modal(title,func(body):
		var page := _text_screen(body,text)
		_btn(page.get_node("%Commands"),"确认",callback))

func _modal(title: String, builder: Callable) -> void:
	var first := modal_stack.is_empty()
	modal_stack.append({"title":title,"build":builder})
	_render_modal()
	if first:
		board_motion.reveal()

func _render_modal() -> void:
	board_motion.snap()
	_clear(modal_box)
	overlay.visible = not modal_stack.is_empty()
	_block_base(base,overlay.visible)
	if modal_stack.is_empty():
		return
	var ritual: bool = modal_stack.back().title.begins_with("六相召唤阵") or modal_stack.back().title.begins_with("妖兽仓库")
	modal_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if ritual else ScrollContainer.SCROLL_MODE_AUTO
	modal_box.size_flags_vertical = Control.SIZE_EXPAND_FILL if ritual else Control.SIZE_FILL
	modal_scroll.scroll_vertical = 0
	modal_feedback.text = ""
	modal_title.text = modal_stack.back().title
	modal_stack.back().build.call(modal_box)
	close_button.grab_focus()

func _close_modal(store_results: bool = true) -> void:
	if modal_stack.is_empty():
		return
	if store_results and modal_stack.back().title.begins_with("召唤完成") and not state.data.pending.is_empty():
		if not state.store_pending():
			_notice(state.last_error)
			return
	if is_instance_valid(warehouse_page) and modal_stack.back().title.begins_with("妖兽仓库"):
		warehouse_selected_id = warehouse_page.selected_id
	modal_stack.pop_back()
	if modal_stack.is_empty() and store_results and animate_panels:
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

func _notice(text: String) -> void:
	status.text = text
	if not modal_stack.is_empty():
		modal_feedback.text = text

func _text_screen(parent: Node, text: String) -> VBoxContainer:
	var page := TextPanel.instantiate()
	parent.add_child(page)
	page.get_node("%Description").text = text
	return page

func _btn(parent: Node, text: String, callback: Callable, component: PackedScene = ActionButton) -> Button:
	var button := component.instantiate()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
