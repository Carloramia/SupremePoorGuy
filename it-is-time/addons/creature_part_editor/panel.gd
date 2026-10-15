@tool
extends VBoxContainer

const EDIT = preload("res://addons/creature_part_editor/part_edit.gd")
var body: PhysicalBodyPart3D
var plugin: EditorPlugin
var picker: EditorResourcePicker
var multiplier: SpinBox
var status: Label
var initial_multiplier: float
var displayed_multiplier: float

func setup(target: PhysicalBodyPart3D, editor_plugin: EditorPlugin) -> void:
	body = target
	plugin = editor_plugin
	var current := EDIT.context(body)
	var title := Label.new()
	title.text = "生成部件编辑"
	add_child(title)
	var identity := Label.new()
	identity.text = "PartKey: " + str(current.key)
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(identity)
	var scene_label := Label.new()
	scene_label.text = "物理部件引用（.tscn）"
	add_child(scene_label)
	picker = EditorResourcePicker.new()
	picker.base_type = "PackedScene"
	picker.edited_resource = current.scene
	add_child(picker)
	var size_label := Label.new()
	size_label.text = "等比尺寸倍率"
	add_child(size_label)
	multiplier = SpinBox.new()
	multiplier.min_value = 0.01
	multiplier.max_value = 100.0
	multiplier.allow_greater = true
	multiplier.step = 0.01
	initial_multiplier = current.multiplier
	multiplier.value = initial_multiplier
	displayed_multiplier = multiplier.value
	add_child(multiplier)
	var apply := Button.new()
	apply.text = "应用修改并记入生成器"
	apply.pressed.connect(_apply)
	add_child(apply)
	status = Label.new()
	status.text = "保留部件位置和关节。纸片厚度仍由 PartWidth 控制。\n应用后启用手动布局；请保存场景。"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	add_child(HSeparator.new())

func _apply() -> void:
	multiplier.apply()
	if not is_instance_valid(body) or not body.is_inside_tree(): return
	var error: String = plugin.apply_part(body, picker.edited_resource as PackedScene, requested_multiplier())
	if not error.is_empty(): status.text = error

func requested_multiplier() -> float:
	# Showing a rounded value must not silently round the saved calibration on Apply.
	return initial_multiplier if is_equal_approx(multiplier.value, displayed_multiplier) else multiplier.value
