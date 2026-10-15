@tool
extends EditorInspectorPlugin

const EDIT = preload("res://addons/weapon_workshop/grip_edit.gd")
var plugin: EditorPlugin

func _can_handle(object: Object) -> bool:
	return EDIT.is_weapon(object) or EDIT.weapon_for_marker(object) != null

func _parse_property(object: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_string: String, _usage: int, _wide: bool) -> bool:
	return EDIT.is_weapon(object) and name in ["grip_point_count","active_grip_point"]

func _parse_begin(object: Object) -> void:
	var panel := VBoxContainer.new()
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var weapon := object as Node3D if EDIT.is_weapon(object) else EDIT.weapon_for_marker(object)
	if not EDIT.is_weapon(object):
		var index := int(object.get_meta(EDIT.INDEX))
		var arm_label := Label.new()
		arm_label.text = "吸附 Arm（角色内名称 / 路径）"
		panel.add_child(arm_label)
		var arm := LineEdit.new()
		arm.placeholder_text = "例如 Arm_L；辅助点留空不绑定"
		arm.tooltip_text = "相对于装备角色根节点，如 GeneratedParts/Arm_L；单独填写 Arm_L 会按唯一同名部位匹配。"
		var paths: Array = weapon.get("grip_point_arm_paths")
		arm.text = str(paths[index]) if index < paths.size() else ""
		panel.add_child(arm)
		var assign := Button.new()
		assign.text = "应用吸附 Arm 到持握点 %d" % (index+1)
		assign.pressed.connect(func(): status.text = plugin.edit_weapon_grips(weapon,&"arm",index,NodePath(arm.text.strip_edges())))
		arm.text_submitted.connect(func(_text: String): assign.pressed.emit())
		panel.add_child(assign)
		var settings := Button.new()
		settings.text = "编辑吸附参数（启用 / 力度 / 阻尼 / 旋转）"
		settings.pressed.connect(func():
			var data: Array = weapon.get("grip_point_settings")
			if index >= data.size() or data[index] == null:
				status.text = plugin.edit_weapon_grips(weapon,&"sync")
				data = weapon.get("grip_point_settings")
			if index < data.size(): plugin.get_editor_interface().edit_resource(data[index]))
		panel.add_child(settings)
		var button := Button.new()
		button.text = "读取此 Marker 到持握点 %d" % (index+1)
		button.pressed.connect(func(): status.text = plugin.edit_weapon_grips(weapon,&"read",index))
		panel.add_child(button)
	else:
		var title := Label.new()
		title.text = "物品多点持握"
		panel.add_child(title)
		var count := SpinBox.new()
		count.min_value = 0
		count.max_value = 32
		count.allow_greater = true
		count.step = 1
		count.prefix = "数量："
		count.value = int(weapon.get("grip_point_count"))
		count.tooltip_text = "0 沿用原 Attachment 参数；1 或更多为每个持握点创建 Marker3D。"
		panel.add_child(count)
		var active := SpinBox.new()
		active.min_value = 1
		active.max_value = maxf(count.value,1)
		active.step = 1
		active.prefix = "主持握点："
		active.value = int(weapon.get("active_grip_point"))+1
		active.editable = count.value > 0
		panel.add_child(active)
		count.value_changed.connect(func(value: float):
			status.text = plugin.edit_weapon_grips(weapon,&"count",int(value))
			active.set_value_no_signal(clampf(active.value,1,maxf(value,1)))
			active.max_value = maxf(value,1)
			active.editable = value > 0)
		active.value_changed.connect(func(value: float): status.text = plugin.edit_weapon_grips(weapon,&"select",int(value)-1))
		var sync := Button.new()
		sync.text = "生成/同步持握点 Marker"
		sync.pressed.connect(func(): status.text = plugin.edit_weapon_grips(weapon,&"sync"))
		panel.add_child(sync)
		var read := Button.new()
		read.text = "读取所有 Marker 到持握参数"
		read.pressed.connect(func(): status.text = plugin.edit_weapon_grips(weapon,&"read"))
		panel.add_child(read)
		status.text = "主点刚性绑定；其余启用且指定 Arm 的点同时追踪。移动 Marker 后点击读取按钮。"
	panel.add_child(status)
	add_custom_control(panel)
