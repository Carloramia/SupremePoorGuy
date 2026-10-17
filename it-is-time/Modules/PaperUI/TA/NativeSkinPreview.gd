extends "res://Modules/PaperUI/Scripts/UI/SkinPreview.gd"
const Library = preload("res://Modules/PaperUI/TA/PresetLibrary.gd")
const Binding = preload("res://Modules/PaperUI/TA/ShaderSkinBinding.gd")
var binder: Node
var strength := 1
var mode := 4
var background := 1
var status: Label

func _ready() -> void:
	super._ready()
	binder = Binding.new()
	binder.target_root = NodePath("..")
	add_child(binder)
	binder.rescan()
	# Test illustration only: the upstream reference is an opaque concept photo.
	# Keep the existing illustration Control and its anchors, sizes and input.
	%Portrait.get_node("Artwork").texture = preload("res://Modules/PaperUI/TA/Assets/monster.svg")
	get_node("Margin/Layout/PreviewPaper/Contents/Instructions").text = "1/2/3 轻中强；Q/W/E/R/T 原始/S1/S2/S3/组合；B 切换背景。\n测试纹理只进入现有 VisualSkin，文字和点击区保持独立。"
	status = Label.new()
	status.position = Vector2(580, 36)
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_color", Color("#eee3cc"))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	_apply(true)
	status.text = "中 · 组合"

func select_preset(level: int, effect: int) -> void:
	strength = level
	mode = effect
	preview_preset = Library.variant(strength, mode)
	_apply(true)
	status.text = "%s · %s" % [["轻", "中", "强"][strength], ["原始素材", "仅 S1", "仅 S2", "仅 S3", "组合"][mode]]

func _apply(active: bool) -> void:
	if binder != null:
		if active:
			binder.apply_preset(preview_preset)
		else:
			binder.restore()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_1, KEY_2, KEY_3]:
		select_preset(event.keycode - KEY_1, mode)
	elif event.keycode in [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T]:
		select_preset(strength, [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T].find(event.keycode))
	elif event.keycode == KEY_B:
		background = (background + 1) % 3
		$Background.color = [Color("#e6dfce"), Color("#282e29"), Color("#56674c")][background]
