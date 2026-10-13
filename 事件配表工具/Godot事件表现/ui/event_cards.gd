extends RefCounted
## Repeated UI instances are editable PackedScenes; this adapter only fills data.
const UI := preload("res://ui/layout_theme.gd")
const CHOICE := preload("res://ui/choice_card.tscn")
const REWARD := preload("res://ui/reward_card.tscn")

static func choice_grid(options: Array, select: Callable, bind_hint: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	for option in options:
		var card := CHOICE.instantiate()
		grid.add_child(card)
		card.get_node("%Heading").text = str(option.get("title", option.text))
		card.get_node("%Summary").text = str(option.get("summary", "选择后继续此分支"))
		card.get_node("%Tags").text = str(option.get("tag", "对话分支 · 无消耗"))
		var action: Button = card.get_node("%Action")
		action.text = str(option.get("action", "选择"))
		action.pressed.connect(select.bind(str(option.id)))
		bind_hint.call(action, str(option.get("title", option.text)), [{"title": "分支说明", "text": str(option.get("summary", "选择后仅显示此分支，不会重写已读记录。"))}])
	return grid

static func reward_summary(node: Dictionary, confirmed: bool, message: String, bind_hint: Callable) -> PanelContainer:
	var card: PanelContainer = REWARD.instantiate()
	card.get_node("%Heading").text = str(node.get("title", "事件奖励"))
	var runes: GridContainer = card.get_node("%Runes")
	var amounts: VBoxContainer = card.get_node("%Amounts")
	for reward in node.get("rewards", []):
		if str(reward.type) == "rune":
			var content := UI.button(str(reward.get("label", reward.id)).split(" · ")[0])
			content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			runes.add_child(content)
			bind_hint.call(content, content.text, [{"title": "符文效果", "text": str(reward.get("label", ""))}])
		else:
			amounts.add_child(UI.label(str(reward.get("label", reward.id)), 28))
	card.get_node("%Status").text = ("模拟确认（不发奖）" if message.begins_with("预览回执") else "已加入背包") if confirmed else "点击下方按钮领取"
	card.get_node("%Message").text = message if not message.is_empty() else ("奖励已发放" if confirmed else "预览奖励 · 尚未发放")
	return card
