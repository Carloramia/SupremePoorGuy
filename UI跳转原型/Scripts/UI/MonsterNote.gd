extends Button
signal selection_requested(monster_id: String)
var monster_id := ""
var caption := ""
func _ready() -> void:
	pressed.connect(func(): selection_requested.emit(monster_id))
func present(id: String, title: String, form: String, position_label: String, hint: String) -> void:
	monster_id = id
	set_meta("monster_id",id)
	caption = title+"\n"+form+" · "+position_label
	tooltip_text = hint
	set_selected(false)
func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)
	text = ("▸ " if selected else "")+caption
