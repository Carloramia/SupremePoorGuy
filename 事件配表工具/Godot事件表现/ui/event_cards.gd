extends RefCounted
## Content layouts only: choices and receipts; no node transitions or reward writes.
const UI := preload("res://ui/layout_theme.gd")
const RUNE_ICON := preload("res://ui/rune_icon.gd")

static func choice_grid(options: Array, select: Callable, bind_hint: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	for option in options:
		var card := UI.panel(UI.PANEL)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		card.add_child(column)
		var heading := UI.label(str(option.get("title", option.text)), 23)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(heading)
		var well := UI.panel(UI.WELL, 10)
		var summary := UI.label(str(option.get("summary", "选择后继续此分支")), 18, UI.MUTED)
		well.add_child(summary)
		column.add_child(well)
		var tags := UI.label(str(option.get("tag", "对话分支 · 无消耗")), 15, UI.MUTED)
		tags.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(tags)
		var action := UI.button(str(option.get("action", "选择")), true)
		column.add_child(action)
		action.pressed.connect(select.bind(str(option.id)))
		bind_hint.call(action, str(option.get("title", option.text)), [{"title": "分支说明", "text": str(option.get("summary", "选择后仅显示此分支，不会重写已读记录。"))}])
	return grid

static func reward_summary(node: Dictionary, confirmed: bool, message: String, bind_hint: Callable) -> PanelContainer:
	var card := UI.panel(UI.PANEL, 16)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	var heading := UI.label(str(node.get("title", "事件奖励")), 25)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	var items := UI.panel(UI.WELL)
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(items)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	items.add_child(left)
	left.add_child(UI.label("解锁内容", 17, UI.MUTED))
	var runes := GridContainer.new()
	runes.columns = 2
	runes.add_theme_constant_override("h_separation", 8)
	left.add_child(runes)
	var resources := UI.panel(UI.WELL)
	resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(resources)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	resources.add_child(right)
	right.add_child(UI.label("资源奖励", 17, UI.MUTED))
	for reward in node.get("rewards", []):
		if str(reward.type) == "rune":
			var content := UI.button(str(reward.get("label", reward.id)).split(" · ")[0])
			content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			runes.add_child(content)
			bind_hint.call(content, content.text, [{"title": "符文效果", "text": str(reward.get("label", ""))}])
		else:
			right.add_child(UI.label(str(reward.get("label", reward.id)), 28))
	right.add_child(UI.label("已加入背包" if confirmed else "点击下方按钮领取", 16, UI.MUTED))
	column.add_child(HSeparator.new())
	column.add_child(UI.label(message if not message.is_empty() else ("奖励已发放" if confirmed else "预览奖励 · 尚未发放"), 16, UI.MUTED))
	return card
