@tool
extends Control
const Library = preload("res://Modules/PaperUI/TA/PresetLibrary.gd")
const Binding = preload("res://Modules/PaperUI/TA/ShaderSkinBinding.gd")
const SlotsScene = preload("res://Modules/PaperUI/Scenes/UI/Components/UISkinSlots.tscn")
const ButtonScene = preload("res://Modules/PaperUI/Scenes/UI/Components/ActionButton.tscn")
const PageScene = preload("res://Modules/PaperUI/Scenes/UI/Components/LooseLeafPage.tscn")
const PortraitScene = preload("res://Modules/PaperUI/Scenes/UI/Components/MonsterPortrait.tscn")
const BookScene = preload("res://Modules/PaperUI/Scenes/UI/Components/SummonBookButton.tscn")
const ThemeResource = preload("res://Modules/PaperUI/Assets/UI/PaperRelief/PaperReliefTheme.tres")
@export_enum("轻", "中", "强") var strength := 1:
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
var specimens: Array[Control] = []
var binders: Array[Node] = []
var presets: Array[Resource] = []
var buttons: Array[Button] = []
var columns: Control
var status: Label
var clicks := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeResource
	if not Engine.is_editor_hint():
		get_window().content_scale_size = Vector2i(1280, 720)
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_build_header()
	_rebuild()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), [Color("#e6dfce"), Color("#29342e"), Color("#52664b")][background_mode])
	if background_mode == 2:
		for y in range(108, 720, 40):
			for x in range(0, 1280, 45):
				var p := Vector2(x + y % 17, y)
				draw_colored_polygon(PackedVector2Array([p, p + Vector2(34, -10), p + Vector2(49, 16), p + Vector2(15, 30)]), Color(0.2, 0.28 + sin(x + y) * 0.05, 0.2, 0.35))
		for i in 6:
			draw_polyline(PackedVector2Array([Vector2(50 + i * 220, 720), Vector2(140 + i * 200, 440), Vector2(40 + i * 235, 108)]), Color("#ad9b73"), 3.0, true)

func _label(parent: Node, text_value: String, position_value: Vector2, font_size: int, color := Color("#302f2b")) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_header() -> void:
	var header := ColorRect.new()
	header.color = Color("#f3edde")
	header.size = Vector2(1280, 94)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	_label(header, "原生 UI · Shader 五组对照", Vector2(26, 12), 27)
	_label(header, "0.7.12 / VisualSkin 插槽 / 文字与点击区独立", Vector2(28, 52), 16)
	var level := OptionButton.new()
	level.name = "Strength"
	level.position = Vector2(586, 25)
	level.size = Vector2(144, 45)
	for text_value in ["轻 · Light", "中 · Medium", "强 · Strong"]:
		level.add_item(text_value)
	level.select(strength)
	level.item_selected.connect(func(index): strength = index)
	header.add_child(level)
	var bg := OptionButton.new()
	bg.name = "Background"
	bg.position = Vector2(750, 25)
	bg.size = Vector2(170, 45)
	for text_value in ["浅纸背景", "深色背景", "复杂地图"]:
		bg.add_item(text_value)
	bg.select(background_mode)
	bg.item_selected.connect(func(index): background_mode = index)
	header.add_child(bg)
	status = _label(header, "点击按钮 / Tab 查看焦点", Vector2(947, 38), 16)

func _rebuild() -> void:
	if columns != null:
		remove_child(columns)
		columns.queue_free()
	specimens.clear()
	binders.clear()
	presets.clear()
	buttons.clear()
	for selector in find_children("*", "OptionButton", true, false):
		selector.select(strength if selector.name == "Strength" else background_mode)
	columns = Control.new()
	columns.position = Vector2(24, 109)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(columns)
	var titles := ["原始素材", "仅 S1 · 笔触", "仅 S2 · 白底", "仅 S3 · 纸面", "S1 + S2 + S3"]
	var captions := ["同图 / 关闭效果", "提按与局部断墨", "完整主体外轮廓", "颗粒和局部毛边", "同一中强度预设"]
	captions[4] = ["轻", "中", "强"][strength] + "强度 / 单件可覆盖"
	for index in 5:
		var preset := Library.variant(strength, index)
		presets.append(preset)
		var col := Control.new()
		col.name = ["Original", "S1", "S2", "S3", "Combined"][index]
		col.position = Vector2(index * 249, 0)
		col.size = Vector2(236, 578)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		columns.add_child(col)
		specimens.append(col)
		var title_bg := ColorRect.new()
		title_bg.size = Vector2(236, 100)
		title_bg.color = Color("#f1ebdc")
		title_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(title_bg)
		_label(col, titles[index], Vector2(10, 1), 21)
		_label(col, captions[index], Vector2(10, 31), 14, Color("#646b5d"))
		_separator(col, Vector2(10, 61), 214, preset)
		_separator(col, Vector2(10, 81), 94, preset)
		var page := PageScene.instantiate() as PanelContainer
		page.name = "Page"
		page.position = Vector2(6, 114)
		page.size = Vector2(224, 98)
		col.add_child(page)
		var body := Label.new()
		body.name = "Body"
		body.text = "远行补给\n生命 128 / 240\n正文与数值独立"
		body.add_theme_font_size_override("font_size", 18)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(body)
		_art(col, "Badge", preload("res://Modules/PaperUI/TA/Assets/badge.svg"), Vector2(18, 231), Vector2(78, 87))
		var book := BookScene.instantiate() as Button
		book.name = "Book"
		book.position = Vector2(134, 227)
		book.size = Vector2(90, 96)
		col.add_child(book)
		_label(col, "异形徽章", Vector2(18, 322), 14, Color("#eee7d6") if background_mode else Color("#646b5d"))
		var portrait := PortraitScene.instantiate() as Control
		portrait.name = "Portrait"
		portrait.position = Vector2(30, 350)
		portrait.size = Vector2(176, 126)
		col.add_child(portrait)
		portrait.get_node("Artwork").texture = preload("res://Modules/PaperUI/TA/Assets/monster.svg")
		var button := ButtonScene.instantiate() as Button
		button.name = "Action"
		button.position = Vector2(6, 486)
		button.size = Vector2(224, 42)
		button.text = "召唤 · 120"
		button.pressed.connect(func(): clicks += 1; status.text = "原生按钮已响应 %d 次" % clicks)
		col.add_child(button)
		buttons.append(button)
		var disabled_button := ButtonScene.instantiate() as Button
		disabled_button.name = "Disabled"
		disabled_button.position = Vector2(6, 535)
		disabled_button.size = Vector2(224, 42)
		disabled_button.text = "禁用 · 120"
		disabled_button.disabled = true
		col.add_child(disabled_button)
		var binder := Binding.new()
		binder.name = "ShaderBinding"
		col.add_child(binder)
		binder.rescan()
		binder.apply_preset(preset)
		binders.append(binder)
	_label(columns, "按钮与纸页使用上游原组件；恢复验证在 NativeSkinPreview；五列基础素材完全一致。", Vector2(8, 587), 14, Color("#e5dfce") if background_mode else Color("#646b5d"))

func _separator(parent: Node, position_value: Vector2, width: float, preset: Resource) -> void:
	var line := NinePatchRect.new()
	line.position = position_value
	line.size = Vector2(width, 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.texture = preload("res://Modules/PaperUI/TA/Assets/separator.svg")
	line.patch_margin_left = 4
	line.patch_margin_right = 4
	line.material = preset.outline_material.duplicate()
	line.material.set_shader_parameter("ui_size_px", line.size)
	line.material.set_shader_parameter("ui_seed", preset.stable_seed)
	parent.add_child(line)

func _art(parent: Node, name_value: String, texture: Texture2D, position_value: Vector2, extent: Vector2) -> void:
	var host := Control.new()
	host.name = name_value
	host.position = position_value
	host.size = extent
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(host)
	var art := TextureRect.new()
	art.name = "Artwork"
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var slots := SlotsScene.instantiate()
	slots.surface_target = NodePath("__none__")
	slots.illustration_targets.assign([NodePath("Artwork")])
	host.add_child(slots)
