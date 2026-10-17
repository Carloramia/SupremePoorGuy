extends SceneTree
const ButtonScene = preload("res://Scenes/UI/Components/ActionButton.tscn")
const LeafScene = preload("res://Scenes/UI/Components/LooseLeafPage.tscn")
const NoteScene = preload("res://Scenes/UI/Components/MonsterNote.tscn")
const WarehouseScene = preload("res://Scenes/UI/Screens/WarehousePanel.tscn")
const ShellScene = preload("res://Scenes/UI/Components/AppShell.tscn")
const SkinPreset = preload("res://Scripts/UI/UISkinPreset.gd")
var checks := 0
var failures := 0
var events: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("COMPONENT CONTRACT: "+label)
func settle() -> void:
	for i in 8:
		await process_frame
func run() -> void:
	var shell = ShellScene.instantiate()
	root.add_child(shell)
	var nav = shell.get_node("%Navigation")
	nav.action_requested.connect(func(action): events.append(action))
	for pair in [["Tasks","tasks"],["Summon","summon"],["Warehouse","warehouse"],["Party","party"],["ReturnMap","world"],["Dictionary","dictionary"],["Help","help"]]:
		shell.get_node("%"+pair[0]).pressed.emit()
		check(events.pop_back() == pair[1], "navigation signal "+pair[1])
	nav.present_context(true,false)
	check(shell.get_node("%PartySlot").visible, "navigation presentation without controller")
	var view = WarehouseScene.instantiate()
	root.add_child(view)
	view.position_filter_requested.connect(func(value): events.append(value))
	view.form_filter_requested.connect(func(value,enabled): events.append([value,enabled]))
	view.clear_filters_requested.connect(func(): events.append("clear"))
	view.back_requested.connect(func(): events.append("back"))
	view.get_node("%Warehouse").pressed.emit()
	check(events.pop_back()=="warehouse", "warehouse action emits identity only")
	view.get_node("%Human").set_pressed(true)
	check(events.pop_back()==["人形",true], "form action emits selection only")
	var forms: Array[String] = ["兽形"]
	view.present_filters("team",forms,{"warehouse":12,"team":3},false)
	check(events.is_empty(), "presenting filters never emits business requests")
	check(view.get_node("%TeamCount").text=="3" and view.get_node("%Beast").button_pressed, "counts and flags render independently")
	view.get_node("%All").pressed.emit()
	check(events.pop_back()=="clear", "clear request preserved")
	view.get_node("%PageBack").pressed.emit()
	check(events.pop_back()=="back", "return request preserved")
	var note = NoteScene.instantiate()
	root.add_child(note)
	note.selection_requested.connect(func(id): events.append(id))
	note.present("id-7","示例","人形","仓库","完整说明")
	note.set_selected(true)
	check(events.is_empty() and note.text.begins_with("▸ "), "note presentation does not select through signal")
	note.pressed.emit()
	check(events.pop_back()=="id-7", "note emits stable ID once")
	var button = ButtonScene.instantiate()
	button.text = "文字 123"
	button.size = Vector2(200,60)
	root.add_child(button)
	await settle()
	var slots = button.get_node("VisualSkin")
	var before: Vector2 = button.get_combined_minimum_size()
	var original = button.get_theme_stylebox("normal")
	var preset = SkinPreset.new()
	preset.surface_texture = GradientTexture2D.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform vec2 ui_size_px; uniform int ui_seed; void fragment(){COLOR=texture(TEXTURE,UV)*COLOR;}"
	var material := ShaderMaterial.new()
	material.shader = shader
	preset.surface_material = material
	preset.stable_seed = 73
	slots.local_preset = preset
	await settle()
	check(button.material == null, "text and numbers are not shader targets")
	check(slots.get_node("Surface").visible and slots.get_node("Surface").mouse_filter==Control.MOUSE_FILTER_IGNORE, "surface is separate and cannot intercept input")
	check(slots.get_node("Surface").material != material, "shared material not mutated")
	check(slots.get_node("Surface").material.get_shader_parameter("ui_seed")==73, "stable instance seed forwarded")
	check(slots.get_node("Surface").material.get_shader_parameter("ui_size_px")==button.size, "pixel size provided after layout")
	check(button.get_combined_minimum_size()==before, "skin replacement preserves button dimensions")
	check(button.text=="文字 123", "caption survives material replacement")
	button.pressed.connect(func(): events.append("click"))
	button.pressed.emit()
	check(events.pop_back()=="click", "skinned button remains functional")
	slots.enabled = false
	await settle()
	check(button.get_theme_stylebox("normal")==original and not slots.get_node("Surface").visible, "disable restores original button skin")
	var override := StyleBoxFlat.new()
	button.add_theme_stylebox_override("normal",override)
	slots.refresh()
	check(button.get_theme_stylebox("normal")==override, "inactive hooks preserve editor overrides")
	var leaf = LeafScene.instantiate()
	root.add_child(leaf)
	await settle()
	var paper = leaf.get_node("Paper")
	var old_texture = paper.texture
	var old_region = paper.region_rect
	var skin = leaf.get_node("VisualSkin")
	skin.local_preset = preset
	await settle()
	check(paper.texture==preset.surface_texture and paper.region_rect==Rect2(), "paper replacement uses full new texture")
	check(leaf.material==null and paper.material!=null, "paper shader does not affect page content")
	skin.enabled = false
	await settle()
	check(paper.texture==old_texture and paper.region_rect==old_region and paper.material==null, "paper asset and crop restore")
	for item in [shell,view,note,button,leaf]:
		item.queue_free()
	await process_frame
	print("COMPONENT_CONTRACT_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
