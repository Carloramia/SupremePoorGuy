@tool
extends Control
const Paper = preload("res://ui_module/shader_lab/components/paper_surface.gd")
const Ink = preload("res://ui_module/shader_lab/components/ink_path.gd")
const Cutout = preload("res://ui_module/shader_lab/components/paper_cutout.gd")
const PaperButton = preload("res://ui_module/shader_lab/components/PaperButton.tscn")
const Presets = [
	preload("res://ui_module/shader_lab/presets/light.tres"),
	preload("res://ui_module/shader_lab/presets/medium.tres"),
	preload("res://ui_module/shader_lab/presets/strong.tres")
]
const Assets = [
	preload("res://ui_module/shader_lab/assets/badge.svg"),
	preload("res://ui_module/shader_lab/assets/book.svg"),
	preload("res://ui_module/shader_lab/assets/monster.svg")
]
@export_enum("轻", "中（默认）", "强") var strength := 1:
	set(value):
		strength = value
		if is_node_ready():
			_rebuild()
@export_enum("浅纸底", "深色底", "复杂地图") var background_mode := 0:
	set(value):
		background_mode = value
		queue_redraw()
		if is_node_ready():
			_rebuild()
var profiles: Array[Resource] = []
var buttons: Array[Button] = []
var columns: Control
var status: Label
var activation_count := 0

func _ready() -> void:
	if not Engine.is_editor_hint():
		get_window().content_scale_size = Vector2i(1280, 720)
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_toolbar()
	_rebuild()

func _draw() -> void:
	var bg := [Color("#e7e0ce"), Color("#303c38"), Color("#536550")][background_mode] as Color
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	if background_mode == 2:
		for y in range(125, 700, 38):
			for x in range(0, 1280, 45):
				var p := Vector2(x + (y % 3) * 13, y)
				draw_colored_polygon(PackedVector2Array([p, p + Vector2(38, -13), p + Vector2(50, 18), p + Vector2(14, 30)]), Color(0.24, 0.35 + sin(x + y) * 0.06, 0.27, 0.5))
		for i in 7:
			draw_polyline(PackedVector2Array([Vector2(i * 205, 720), Vector2(i * 190 + 100, 420), Vector2(i * 180 + 40, 130)]), Color("#aa9d78"), 3.0, true)

func _label(parent: Node, text_value: String, pos: Vector2, font_size: int, color: Color = Color("#343930")) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_toolbar() -> void:
	var header := ColorRect.new()
	header.color = Color("#f4eedf")
	header.size = Vector2(1280, 120)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	_label(header, "纸上笔触 / UI 材质实验台", Vector2(28, 12), 27)
	_label(header, "同一套素材 · 五组对照 · 独立文字层", Vector2(29, 50), 14, Color("#6c7263"))
	var strength_select := OptionButton.new()
	strength_select.name = "Strength"
	strength_select.position = Vector2(500, 20)
	strength_select.size = Vector2(150, 36)
	for item in ["轻 · Light", "中 · Medium", "强 · Strong"]:
		strength_select.add_item(item)
	strength_select.select(strength)
	strength_select.item_selected.connect(func(index): strength = index)
	header.add_child(strength_select)
	var background_select := OptionButton.new()
	background_select.name = "Background"
	background_select.position = Vector2(667, 20)
	background_select.size = Vector2(156, 36)
	for item in ["浅纸背景", "深色背景", "复杂地图背景"]:
		background_select.add_item(item)
	background_select.select(background_mode)
	background_select.item_selected.connect(func(index): background_mode = index)
	header.add_child(background_select)
	status = _label(header, "点击按钮测试 · Tab 切换焦点", Vector2(853, 29), 14)
	var controls := [["线宽", "line_width", 0.5, 8.0], ["白边", "backing_width", 0.0, 16.0], ["颗粒", "paper_grain", 0.0, 0.3], ["毛边", "edge_size", 0.0, 5.0]]
	for i in controls.size():
		var spec: Array = controls[i]
		_label(header, spec[0], Vector2(30 + i * 305, 87), 14)
		var slider := HSlider.new()
		slider.name = spec[1]
		slider.position = Vector2(74 + i * 305, 88)
		slider.size = Vector2(213, 18)
		slider.min_value = spec[2]
		slider.max_value = spec[3]
		slider.step = 0.01
		slider.value = Presets[strength].get(spec[1])
		var param: String = spec[1]
		slider.value_changed.connect(func(value):
			for profile in profiles:
				profile.set(param, value)
			if param == "paper_grain":
				for profile in profiles:
					profile.pigment_grain = value * 0.75
		)
		header.add_child(slider)

func _rebuild() -> void:
	if columns != null:
		remove_child(columns)
		columns.queue_free()
	profiles.clear()
	buttons.clear()
	# Match toolbar values to the newly selected preset without emitting changes.
	for slider in find_children("*", "HSlider", false, false):
		slider.set_value_no_signal(Presets[strength].get(slider.name))
	for selector in find_children("*", "OptionButton", false, false):
		selector.select(strength if selector.name == "Strength" else background_mode)
	columns = Control.new()
	columns.name = "Comparisons"
	columns.position = Vector2(24, 141)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(columns)
	var titles := ["原始", "仅 S1 · 手绘线", "仅 S2 · 白底", "仅 S3 · 颗粒毛边", "S1 + S2 + S3"]
	var captions := ["基础线条 / 原图", "提按 · 复笔 · 局部断墨", "完整剪影 / 连续纸底", "低对比颗粒 / 局部边缘", ["轻", "中", "强"][strength] + "强度 / 可逐件替换"]
	for index in 5:
		var profile := Presets[strength].duplicate() as Resource
		profile.s1_enabled = index == 1 or index == 4
		profile.s2_enabled = index == 2 or index == 4
		profile.s3_enabled = index == 3 or index == 4
		profiles.append(profile)
		var col := Control.new()
		col.name = ["Original", "S1", "S2", "S3", "Combined"][index]
		col.position = Vector2(index * 249, 0)
		col.size = Vector2(236, 549)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		columns.add_child(col)
		var backing := ColorRect.new()
		backing.color = Color(0.96, 0.95, 0.9, 0.89)
		backing.size = Vector2(236, 105)
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(backing)
		_label(col, titles[index], Vector2(12, 4), 19)
		_label(col, captions[index], Vector2(12, 32), 12, Color("#737466"))
		_ink(col, Vector2(9, 70), Vector2(216, 12), profile, 1)
		_ink(col, Vector2(9, 88), Vector2(100, 12), profile, 1)
		var panel := Paper.new()
		panel.name = "PaperPanel"
		panel.position = Vector2(6, 115)
		panel.size = Vector2(224, 91)
		panel.profile = profile
		panel.paper_color = Color("#e8ddbf")
		col.add_child(panel)
		_ink(col, panel.position, panel.size, profile, 0)
		_label(col, "远行补给", Vector2(23, 125), 19)
		_label(col, "生命 128 / 240   魔力 +16", Vector2(23, 156), 13)
		_label(col, "纸面、边框与文字独立", Vector2(23, 178), 12)
		for art_index in 2:
			var icon := Cutout.new()
			icon.name = ["Badge", "Book"][art_index]
			icon.position = Vector2(20 + 118 * art_index, 226)
			icon.size = Vector2(77, 83)
			icon.texture = Assets[art_index]
			icon.profile = profile
			col.add_child(icon)
		# Same authored badge centerline is used by S1, independently of art fill.
		var badge_outline := _ink(col, Vector2(20, 226), Vector2(77, 83), profile, 2)
		badge_outline.path = PackedVector2Array([Vector2(.5,.063), Vector2(.86,.18), Vector2(.84,.54), Vector2(.72,.75), Vector2(.51,.92), Vector2(.26,.78), Vector2(.16,.54), Vector2(.13,.19)])
		badge_outline.closed = true
		badge_outline.allow_repeat = false
		var caption_color := Color("#ece9db") if background_mode else Color("#696e60")
		_label(col, "异形徽章", Vector2(24, 314), 12, caption_color)
		_label(col, "书本入口", Vector2(143, 314), 12, caption_color)
		var portrait := Cutout.new()
		portrait.name = "MonsterPortrait"
		portrait.position = Vector2(32, 345)
		portrait.size = Vector2(172, 143)
		portrait.texture = Assets[2]
		portrait.profile = profile
		col.add_child(portrait)
		var button := PaperButton.instantiate() as Button
		button.name = "ActionButton"
		button.position = Vector2(7, 505)
		button.size = Vector2(222, 42)
		button.profile = profile
		button.pressed.connect(func():
			activation_count += 1
			status.text = "已响应 %d 次 · 点击区保持原尺寸" % activation_count
		)
		col.add_child(button)
		buttons.append(button)
	# Separate state specimens use same preset and keep the same stable seed.
	_label(columns, "状态试验：悬停／按下／禁用／Tab 焦点均使用同一稳定种子；所有材质层忽略鼠标输入。", Vector2(7, 554), 13, Color("#777d68") if background_mode == 0 else Color("#e5e0cb"))

func _ink(parent: Node, pos: Vector2, extent: Vector2, profile: Resource, shape: int) -> Control:
	var ink := Ink.new()
	ink.position = pos
	ink.size = extent
	ink.profile = profile
	ink.shape = shape
	parent.add_child(ink)
	return ink
