extends PanelContainer
## Extend the paper art with the visual panel edge without changing the list's usable width.
func _ready() -> void:
	sort_children.connect(func(): _fit_paper.call_deferred())
	_fit_paper.call_deferred()

func _fit_paper() -> void:
	var edge := get_theme_stylebox("panel") as StyleBoxFlat
	var paper: Control = $Paper
	var content: Control = $Row
	paper.position = content.position
	paper.size = content.size + Vector2(edge.expand_margin_right, 0)
