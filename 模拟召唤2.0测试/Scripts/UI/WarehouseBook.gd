extends VBoxContainer
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
const Entry = preload("res://Scenes/UI/Components/WarehouseEntry.tscn")
signal changed
signal notice(text: String)
signal term_requested(title: String, content: String)
var state
var filter := "warehouse"
var selected_id := ""
var initial_id := ""
var shown_ids: Array = []
var reading_scroll := 0
var has_setup := false

func setup(model, starting_filter: String, remembered_id: String) -> void:
	state = model
	filter = starting_filter
	selected_id = remembered_id
	for pair in [["Warehouse","warehouse"],["Team","team"],["All",""]]:
		get_node("%"+pair[0]).pressed.connect(func():
			filter = pair[1]
			refresh())
	%Advanced.toggled.connect(func(value): %Filters.visible = value)
	%Search.text_changed.connect(func(_value): refresh())
	%Sort.item_selected.connect(func(_index): refresh())
	%TierFilter.item_selected.connect(func(_index): refresh())
	%ShapeFilter.item_selected.connect(func(_index): refresh())
	%MutationFilter.item_selected.connect(func(_index): refresh())
	%ClearFilters.pressed.connect(func():
		%Search.text = ""
		%TierFilter.select(0)
		%ShapeFilter.select(0)
		%MutationFilter.select(0)
		refresh())
	%Move.pressed.connect(_move)
	%SaveName.pressed.connect(func():
		if state.rename_monster(selected_id,%NameInput.text):
			changed.emit()
			refresh()
		else:
			notice.emit(state.last_error if not state.last_error.is_empty() else "名称不能为空"))
	has_setup = true
	refresh()

func refresh() -> void:
	if not has_setup:
		return
	var saved_scroll: int = %LeftScroll.scroll_vertical
	%Summary.text = "持有 %d 只　·　出战 %d 只　·　队位 %d / %d（试验上限）" % [state.monsters().size(),state.monsters("team").size(),state.occupied_slots(),state.TEAM_LIMIT]
	%Warehouse.text = "未编队 %d" % state.monsters("warehouse").size()
	%Team.text = "已编队 %d" % state.monsters("team").size()
	%All.text = "全部 %d" % state.monsters().size()
	var units: Array = []
	for unit in state.monsters(filter):
		if not %Search.text.strip_edges().is_empty() and not %Search.text.strip_edges().to_lower() in unit.name.to_lower():
			continue
		if %TierFilter.selected > 0 and int(unit.tier) != %TierFilter.selected:
			continue
		if %ShapeFilter.selected > 0 and unit.form != ["","人形","兽形","蛇形"][%ShapeFilter.selected]:
			continue
		if %MutationFilter.selected == 1 and unit.mutation_sources.is_empty():
			continue
		if %MutationFilter.selected == 2 and not unit.mutation_sources.is_empty():
			continue
		units.append(unit)
	units.sort_custom(func(a,b):
		if %Sort.selected == 1 and a.tier != b.tier:
			return int(a.tier)>int(b.tier)
		if %Sort.selected == 2 and a.name != b.name:
			return a.name.naturalnocasecmp_to(b.name)<0
		# Compare numeric batch serials, not lexical IDs (batch_10 vs batch_9).
		var a_batch := int(str(a.batch_id).trim_prefix("batch_"))
		var b_batch := int(str(b.batch_id).trim_prefix("batch_"))
		return a_batch>b_batch if a_batch != b_batch else a.id.naturalnocasecmp_to(b.id)<0)
	shown_ids.clear()
	for child in %Cards.get_children():
		%Cards.remove_child(child)
		child.queue_free()
	for unit in units:
		shown_ids.append(unit.id)
	if selected_id not in shown_ids:
		selected_id = str(shown_ids[0]) if not shown_ids.is_empty() else ""
	for unit in units:
		var row := Entry.instantiate()
		%Cards.add_child(row)
		row.get_node("%Portrait").form = unit.form
		row.get_node("%Portrait").tint = Color(unit.color)
		row.get_node("%Name").text = unit.name
		row.get_node("%Hint").text = "%s · %d段 · %s\n%s · %s" % [unit.form,unit.tier,slot_text(unit),"已编队" if unit.position=="team" else "待安置" if unit.position=="pending" else "未编队","畸变体" if not unit.mutation_sources.is_empty() else " / ".join(unit.traits).left(22)]
		row.button_pressed = unit.id==selected_id
		row.pressed.connect(func():
			selected_id = unit.id
			%RightScroll.scroll_vertical = 0
			refresh())
	%Empty.visible = units.is_empty()
	%Empty.text = "没有符合筛选条件的妖兽。可清除条件。" if not state.monsters().is_empty() else "名册为空。先到召唤法典召唤妖兽。"
	%ResultCount.text = "筛选结果 %d 只 · 左选右显 · 图像为概念示意" % units.size()
	%LeftScroll.set_deferred("scroll_vertical",saved_scroll)
	_show_selected()

func _show_selected() -> void:
	var unit: Dictionary = state.monster_by_id(selected_id)
	%Detail.visible = not unit.is_empty()
	%NoSelection.visible = unit.is_empty()
	%Commands.visible = not unit.is_empty()
	if unit.is_empty():
		return
	var detail: Control = %Detail
	detail.get_node("%Portrait").form = unit.form
	detail.get_node("%Portrait").tint = Color(unit.color)
	detail.get_node("%Name").text = unit.name
	detail.get_node("%Identity").text = "%s · %d段 · %s\n%s · %s" % [unit.form,unit.tier,mode_text(unit.mode),slot_text(unit),"已编队" if unit.position=="team" else "未编队"]
	detail.get_node("%PreviewHint").text = "形态概念示意 · 尺度标签 ×%.2f\n尚未接入该个体的3D外观或畸变资产" % unit.visual_scale
	detail.get_node("%Stats").text = "生命 %d　攻击 %d　护甲 %d\n攻击周期 %.2f 秒　移速 %.1f" % [unit.hp,unit.attack,unit.armor,unit.interval,unit.speed]
	detail.get_node("%Parts").text = "部位耐久提案（未接入实战）\n头部 %d　核心 %d　肢体 %d\n总生命与部位耐久分开记录；当前没有战损状态。" % [unit.part_hp["头部"],unit.part_hp["核心"],unit.part_hp["肢体"]]
	detail.get_node("%Contributions").text = "生成基值：生命 %d / 攻击 %d / 护甲 %d\n上方为符文、结构与奇物作用后的固定数值。改名、编队和浏览不会重新抽取。" % [unit.base_stats.hp,unit.base_stats.attack,unit.base_stats.armor]
	var source_names: Array[String] = []
	for rune in unit.source_layout.placed:
		source_names.append(Rules.definition(rune.runeId).name+("（停用）" if not rune.enabled else ""))
	var relic_names: Array[String] = []
	for relic in unit.source_layout.placedRelics:
		relic_names.append(Rules.definition(relic.relicId,true).name)
	detail.get_node("%Source").text = "召唤记录\n地点：%s　投入：%d魔力　法阵：%d格\n符文：%s\n奇物：%s\n时间：%s\n%s" % [{"grassland":"草原","forest":"森林","desert":"沙漠"}.get(unit.source_location,unit.source_location),unit.source_cost,Rules.cells(int(unit.source_layout.stage)).size()," / ".join(source_names)," / ".join(relic_names) if not relic_names.is_empty() else "无",unit.created_at,"缩小群体不可回收。" if not unit.recoverable else "仅胜利时本场战死的本体回收%d魔力；尚未接入战斗回执。" % (unit.tier-1)]
	var mutation_names: Array[String] = []
	for id in unit.mutation_sources:
		mutation_names.append(Rules.definition(id).name)
	detail.get_node("%Mutation").visible = not mutation_names.is_empty()
	detail.get_node("%Mutation").text = "畸变来源：%s\n成功放大重复符文的方向；具体强化见能力。全部倍率为试验值。" % " / ".join(mutation_names)
	var trait_box: VBoxContainer = detail.get_node("%Traits")
	for child in trait_box.get_children():
		trait_box.remove_child(child)
		child.queue_free()
	for ability in unit.abilities:
		var button := Button.new()
		button.text = "%s ×%d%s" % [ability.name,ability.copies," · 畸变" if ability.mutated else ""]
		button.pressed.connect(func(): term_requested.emit(ability.name,ability.description+"\n重复 %d枚；效果放大 ×%.1f\n%s" % [ability.copies,ability.amplification,_effect_text(unit,ability.rune_id)]))
		trait_box.add_child(button)
	if unit.mode=="multiply":
		var info := Label.new()
		info.text = "分身接口：每本体入场 %d 分身，属性50%%，只继承普攻；分身不可回收。当前未接入实战。" % unit.clone_count
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		trait_box.add_child(info)
	%NameInput.text = unit.name
	var to_team: bool = unit.position != "team"
	%Move.text = "整组加入编队" if to_team and unit.mode=="tiny" else "整组撤回仓库" if unit.mode=="tiny" else "加入编队" if to_team else "撤回仓库"
	%Move.disabled = to_team and not state.can_join(unit.id)
	%MoveHint.text = "加入后队位 %d → %d / %d%s" % [state.occupied_slots(),state.slots_after_join(unit.id),state.TEAM_LIMIT,"；队位不足，请撤回其他单位" if %Move.disabled else ""] if to_team else "当前出战；撤回保留该个体的固定属性。"

static func slot_text(unit: Dictionary) -> String:
	return "同批每5只占1队位" if unit.mode=="tiny" else "%d队位" % unit.slots

static func mode_text(mode: String) -> String:
	return {"normal":"普通","giant":"巨化","ultra":"超巨化","multiply":"增殖本体","tiny":"缩小群体","special":"定向类别"}.get(mode,mode)

static func _effect_text(unit: Dictionary, id: String) -> String:
	match id:
		"cocoon": return "护盾 %.0f%% 最大生命；共享、10秒、每场一次（战斗接口）" % (unit.effects.shield_ratio*100)
		"burn": return "灼烧每秒 %.0f%% 攻击，持续3秒（战斗接口）" % (unit.effects.burn_ratio*100)
		"feast": return "击杀治疗 %.0f%% 最大生命，每场最多3次（战斗接口）" % (unit.effects.heal_ratio*100)
		"haste": return "实际攻击周期 %.2f 秒（试验最低0.5秒）" % unit.interval
		"giant": return "超巨化：生命×8、攻甲×5；1只占5队位（试验值）。" if unit.mode=="ultra" else "巨化：生命×1.8、攻甲×1.5；每只2队位（试验值）。"
		"multiply": return "本体入场分身数%d，分身为本体50%%属性；不可回收。未接入实战。" % unit.clone_count
		"tiny": return "同批每5只1队位，不可回收；畸变个体更小、基础攻防血为普通缩小体的2倍（试验值）。" if not unit.mutation_sources.is_empty() else "同批每5只1队位，不可回收。"
	return "最终生命 %d / 攻击 %d / 护甲 %d" % [unit.hp,unit.attack,unit.armor]

func _move() -> void:
	var unit: Dictionary = state.monster_by_id(selected_id)
	if unit.is_empty():
		return
	if state.move_monster(selected_id,"warehouse" if unit.position=="team" else "team"):
		changed.emit()
		# Keep selection visible after a transfer even under a position filter.
		filter = ""
		refresh()
	else:
		notice.emit(state.last_error)

func restore_reading_position(left_position: int, right_position: int) -> void:
	# ScrollContainer clamps early assignments before the new detail has been laid out.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree():
		%LeftScroll.scroll_vertical = left_position
		%RightScroll.scroll_vertical = right_position
