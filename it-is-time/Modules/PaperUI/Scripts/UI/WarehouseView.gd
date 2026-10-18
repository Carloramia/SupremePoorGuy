extends HBoxContainer
const L10N = preload("res://Scripts/Localization/GameText.gd")
signal back_requested
signal position_filter_requested(position_id: String)
signal form_filter_requested(form: String, enabled: bool)
signal clear_filters_requested
func _ready() -> void:
	%PageBack.pressed.connect(func(): back_requested.emit())
	for pair in [["warehouse","Warehouse"],["team","Team"]]:
		get_node("%"+pair[1]).pressed.connect(func(): position_filter_requested.emit(pair[0]))
	for pair in [["人形","Human"],["兽形","Beast"],["蛇形","Serpent"]]:
		get_node("%"+pair[1]).toggled.connect(func(value): form_filter_requested.emit(pair[0],value))
	%All.pressed.connect(func(): clear_filters_requested.emit())
func present_filters(position_id: String, forms: Array[String], counts: Dictionary, animate := true) -> void:
	for pair in [["warehouse","Warehouse"],["team","Team"]]:
		L10N.bind(get_node("%"+pair[1]+"Count"),&"text",func(): return L10N.text(str(counts.get(pair[0],0))))
		get_node("%"+pair[1]).set_active(position_id == pair[0],animate)
	for pair in [["人形","Human"],["兽形","Beast"],["蛇形","Serpent"]]:
		get_node("%"+pair[1]).set_active(pair[0] in forms,animate)
	%All.disabled = position_id.is_empty() and forms.is_empty()
