@tool
extends VBoxContainer

const LAYOUT = preload("res://Scripts/Items/WeaponLayout.gd")
const BUILDER = preload("res://Scripts/Items/WeaponCellBuilder.gd")
const CANVAS = preload("res://addons/weapon_workshop/workshop_canvas.gd")
var editor_plugin: EditorPlugin
var layout: WeaponLayout = LAYOUT.new()
var canvas: Control
var viewport: SubViewport
var camera: Camera3D
var preview: RigidBody3D
var status: Label
var name_field: LineEdit
var holder_field: LineEdit
var rotation_field: SpinBox
var visual_field: OptionButton
var material_field: OptionButton
var materials: Array[Resource] = []
var dialog: FileDialog
var _file_mode := ""
var _history: Array[Resource] = []
var _redo: Array[Resource] = []
var _syncing := false

func button(row: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(action)
	row.add_child(control)
	return control

func _ready() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	button(toolbar,"新建",_new_layout)
	button(toolbar,"撤销",_undo)
	button(toolbar,"重做",_redo_edit)
	button(toolbar,"打开布局",func(): _choose_file("open"))
	button(toolbar,"保存布局",func(): _choose_file("layout"))
	button(toolbar,"生成武器场景",func(): _choose_file("scene"))
	var tools := HBoxContainer.new()
	add_child(tools)
	var modes := OptionButton.new()
	for text: String in ["绘制材料","擦除材料","放置握持点"]: modes.add_item(text)
	modes.item_selected.connect(func(index: int): canvas.mode = index)
	tools.add_child(modes)
	material_field = OptionButton.new()
	material_field.tooltip_text = "选择整把武器使用的材料；尺寸、厚度和重量读取对应的材料资源。"
	tools.add_child(material_field)
	_refresh_materials()
	material_field.item_selected.connect(_select_material)
	button(tools,"刷新材料",_refresh_materials)
	visual_field = OptionButton.new()
	for text: String in ["Sprite","Mesh","Sprite + Mesh"]: visual_field.add_item(text)
	tools.add_child(visual_field)
	visual_field.item_selected.connect(func(index: int):
		if _syncing: return
		_remember()
		layout.sprite_visible = index != 1
		layout.mesh_visible = index != 0
		_refresh_preview())
	rotation_field = SpinBox.new()
	rotation_field.min_value = -36000
	rotation_field.max_value = 36000
	rotation_field.step = 1
	rotation_field.suffix = "°"
	tools.add_child(rotation_field)
	rotation_field.value_changed.connect(func(value: float):
		if _syncing: return
		_remember()
		layout.rotation_radians = deg_to_rad(value)
		_refresh_preview())
	var fields := HBoxContainer.new()
	add_child(fields)
	var name_label := Label.new(); name_label.text = "名称"; fields.add_child(name_label)
	name_field = LineEdit.new(); name_field.custom_minimum_size.x = 160; fields.add_child(name_field)
	name_field.text_submitted.connect(func(text: String): _remember(); layout.display_name = text; _refresh_preview())
	name_field.focus_exited.connect(func():
		if name_field.text != layout.display_name: _remember(); layout.display_name = name_field.text; _refresh_preview())
	var holder_label := Label.new(); holder_label.text = "持握部位"; fields.add_child(holder_label)
	holder_field = LineEdit.new(); holder_field.custom_minimum_size.x = 110; fields.add_child(holder_field)
	holder_field.text_submitted.connect(func(text: String): _remember(); layout.holder_name = StringName(text))
	holder_field.focus_exited.connect(func():
		if holder_field.text != str(layout.holder_name): _remember(); layout.holder_name = StringName(holder_field.text))
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	canvas = CANVAS.new()
	canvas.custom_minimum_size = Vector2(450,240)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.layout = layout
	canvas.edit_started.connect(_remember)
	canvas.edited.connect(_refresh_preview)
	split.add_child(canvas)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(260,240)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.stretch = true
	split.add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(360,300)
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	viewport.add_child(camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12,0.13,0.15)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30,-30,0)
	viewport.add_child(light)
	status = Label.new()
	add_child(status)
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.size = Vector2i(850,600)
	dialog.file_selected.connect(_file_selected)
	add_child(dialog)
	_sync_controls()
	_refresh_preview()

func _remember() -> void:
	_history.append(layout.duplicate(true))
	if _history.size() > 100: _history.pop_front()
	_redo.clear()

func _undo() -> void:
	if _history.is_empty(): return
	_redo.append(layout.duplicate(true))
	layout = _history.pop_back()
	_sync_controls(); _refresh_preview()

func _redo_edit() -> void:
	if _redo.is_empty(): return
	_history.append(layout.duplicate(true))
	layout = _redo.pop_back()
	_sync_controls(); _refresh_preview()

func _new_layout() -> void:
	_remember()
	layout = LAYOUT.new()
	canvas.offset = Vector2.ZERO
	canvas.zoom = 1.0
	_sync_controls(); _refresh_preview()

func _refresh_materials() -> void:
	materials.clear(); material_field.clear()
	_collect_materials("res://Resources/Materials")
	for resource: Resource in materials: material_field.add_item(resource.display_name)
	if not materials.is_empty():
		for index: int in range(materials.size()):
			if materials[index].resource_path == layout.material.resource_path: material_field.select(index)

func _collect_materials(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		if file.get_extension() != "tres": continue
		var resource := load(path.path_join(file))
		if resource is SampleMaterial: materials.append(resource)
	for directory: String in DirAccess.get_directories_at(path): _collect_materials(path.path_join(directory))

func _select_material(index: int) -> void:
	if _syncing: return
	_remember()
	layout.material = materials[index]
	_refresh_preview()

func _sync_controls() -> void:
	_syncing = true
	canvas.layout = layout
	name_field.text = layout.display_name
	holder_field.text = str(layout.holder_name)
	rotation_field.value = rad_to_deg(layout.rotation_radians)
	visual_field.select(2 if layout.sprite_visible and layout.mesh_visible else (1 if layout.mesh_visible else 0))
	_refresh_materials()
	_syncing = false

func _refresh_preview() -> void:
	canvas.layout = layout
	canvas.queue_redraw()
	if is_instance_valid(preview): preview.free()
	if layout.material == null or layout.material.get_display_texture() == null: status.text = "请选择带有贴图的材料。"; return
	preview = BUILDER.build_layout(layout,false)
	preview.freeze = true
	preview.collision_layer = 0
	preview.collision_mask = 0
	viewport.add_child(preview)
	preview.rotation.z = layout.rotation_radians
	if layout.attachment_is_set:
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = layout.material.cell_size*0.12
		sphere.height = sphere.radius*2
		var appearance := StandardMaterial3D.new()
		appearance.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		appearance.albedo_color = Color.CYAN
		sphere.material = appearance
		marker.mesh = sphere
		marker.position = layout.attachment_local()+Vector3(0,0,layout.material.collision_thickness)
		preview.add_child(marker)
	var span := Vector2.ONE
	for cell: Vector2i in layout.cells: span = span.max((Vector2(cell)-layout.center()).abs()*2+Vector2.ONE)
	camera.size = maxf(span.length()*layout.material.cell_size*1.3,1.0)
	camera.position = Vector3(0,0,camera.size*2)
	status.text = "左键绘制/放握持点；右键擦除；中键拖动；滚轮缩放。%d 格，重量 %.3f，握持点 %s" % [layout.cells.size(),preview.mass,str(layout.attachment) if layout.attachment_is_set else "未设置"]

func _choose_file(mode: String) -> void:
	_file_mode = mode
	if mode == "scene" and not layout.validation_error().is_empty(): status.text = layout.validation_error(); return
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if mode == "open" else FileDialog.FILE_MODE_SAVE_FILE
	dialog.filters = PackedStringArray(["*.tscn ; Weapon Scene"] if mode == "scene" else ["*.tres ; Weapon Layout"])
	dialog.current_dir = "res://Resources" if mode != "scene" else "res://Scenes/Items"
	dialog.current_file = "" if mode == "open" else layout.display_name+(".tscn" if mode == "scene" else ".tres")
	dialog.popup_centered()

func save_layout(path: String) -> Error:
	return ResourceSaver.save(layout,path)

func export_scene(path: String) -> Error:
	if not layout.validation_error().is_empty(): return ERR_INVALID_DATA
	# Bake a snapshot: later layout/material edits must not silently desynchronize
	# the exported weapon's metadata from its saved visual/collision geometry.
	var snapshot: WeaponLayout = layout.duplicate(true)
	snapshot.resource_path = ""
	snapshot.material.resource_path = ""
	var weapon := BUILDER.build_layout(snapshot,true)
	weapon.rotation.z = layout.rotation_radians
	var packed := PackedScene.new()
	var error := packed.pack(weapon)
	weapon.free()
	return ResourceSaver.save(packed,path) if error == OK else error

func _file_selected(path: String) -> void:
	if _file_mode == "open":
		var resource := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not resource is WeaponLayout: status.text = "请选择 WeaponLayout 类型的布局资源。"; return
		_remember(); layout = resource.duplicate(true)
		_sync_controls(); _refresh_preview()
		return
	var error := export_scene(path) if _file_mode == "scene" else save_layout(path)
	status.text = ("已保存："+path) if error == OK else ("保存失败："+error_string(error))
	if error == OK and editor_plugin != null: editor_plugin.refresh_files()
