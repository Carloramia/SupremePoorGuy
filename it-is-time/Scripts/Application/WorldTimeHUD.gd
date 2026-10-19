extends PanelContainer
## Artwork can be assigned here, or the whole scene replaced on GameRoot.
const L10N = preload("res://Scripts/Localization/GameText.gd")
@export var background_texture: Texture2D
@export var time_icon: Texture2D
@export var travel_icon: Texture2D
@export var display_font: Font
@export_range(12, 48) var font_size := 20
@export var text_color := Color("eee5d2")
var session: RefCounted

func _ready() -> void:
	$Background.texture = background_texture
	$Background.visible = background_texture != null
	for row: String in ["Time", "Travel"]:
		var icon: TextureRect = get_node("Margin/Rows/" + row + "/Icon")
		icon.texture = time_icon if row == "Time" else travel_icon
		icon.visible = icon.texture != null
		var label: Label = get_node("Margin/Rows/" + row + "/Value")
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", text_color)
		if display_font != null: label.add_theme_font_override("font", display_font)
	refresh()

func bind_session(value: RefCounted) -> void:
	if session != null:
		session.world_time_changed.disconnect(refresh)
		session.changed.disconnect(refresh)
	session = value
	session.world_time_changed.connect(refresh)
	session.changed.connect(refresh)
	refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready(): refresh()

func refresh() -> void:
	if not is_node_ready() or session == null: return
	var status: Dictionary = session.world_time_status()
	$Margin/Rows/Time/Value.text = L10N.text("第 {day} 天 · {time}", {"day":status.day, "time":"%02d:%02d" % [status.hour, status.minute]})
	$Margin/Rows/Travel/Value.text = L10N.text("旅行速度 {speed} 单位/时", {"speed":"%.0f" % status.travel_speed})
	tooltip_text = L10N.text("移动按实际路程结算时间；停留和浏览菜单不耗时。")
