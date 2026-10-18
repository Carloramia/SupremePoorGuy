extends Button
const L10N = preload("res://Scripts/Localization/GameText.gd")
signal selection_requested(monster_id: String)
var monster_id := ""
var _caption: Callable
func _ready() -> void:
	pressed.connect(func(): selection_requested.emit(monster_id))
func present(id: String, title: Variant, form: String, position_label: String, hint: Variant) -> void:
	monster_id = id
	set_meta("monster_id",id)
	_caption = func(): return String(title.call() if title is Callable else title)+"\n"+L10N.text(form)+" · "+L10N.text(position_label)
	L10N.bind(self,&"tooltip_text",hint)
	set_selected(false)
func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)
	L10N.bind(self,&"text",func(): return ("▸ " if button_pressed else "")+String(_caption.call()))
