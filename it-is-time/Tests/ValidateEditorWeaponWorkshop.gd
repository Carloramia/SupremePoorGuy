extends SceneTree
const PANEL = preload("res://addons/weapon_workshop/workshop_panel.gd")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func mouse(canvas: Control, button: MouseButton, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	canvas._gui_input(event)
func run() -> void:
	var panel := PANEL.new()
	panel.size = Vector2(1000,450)
	root.add_child(panel)
	await process_frame
	var canvas: Control = panel.canvas
	var at: Vector2 = canvas.grid_to_screen(Vector2(2,3))
	mouse(canvas,MOUSE_BUTTON_LEFT,true,at)
	mouse(canvas,MOUSE_BUTTON_LEFT,false,at)
	check(panel.layout.cells == [Vector2i(2,3)],"Canvas left click must paint a grid cell")
	panel._undo()
	check(panel.layout.cells.is_empty(),"Undo must restore the previous layout")
	panel._redo_edit()
	check(panel.layout.cells.size() == 1,"Redo must restore the painted cell")
	canvas.mode = 2
	var grip := Vector2(1.23,2.76)
	var material_position: Vector2 = canvas.grid_to_screen(Vector2(2,3))
	mouse(canvas,MOUSE_BUTTON_LEFT,true,canvas.grid_to_screen(grip))
	mouse(canvas,MOUSE_BUTTON_LEFT,false,canvas.grid_to_screen(grip))
	check(panel.layout.attachment.distance_to(grip) < 0.0001,"Grip point must be continuous and unsnapped")
	check(canvas.grid_to_screen(Vector2(2,3)).distance_to(material_position) < 0.001,"Changing grip must not move materials")
	panel.rotation_field.value = 37
	panel.visual_field.item_selected.emit(1)
	panel.layout.cells.append(Vector2i(3,3))
	panel.layout.cells.append(Vector2i(3,4))
	panel._refresh_preview()
	check(panel.preview.get_child_count() == 10,"3D preview must contain per-cell visuals/colliders plus grip marker")
	var grip_screen: Vector2 = canvas.grid_to_screen(grip)
	mouse(canvas,MOUSE_BUTTON_WHEEL_UP,true,grip_screen)
	check(canvas.grid_to_screen(grip).distance_to(grip_screen) < 0.001,"Zoom must preserve the point under the mouse")
	var directory := "res://.godot/weapon_workshop_validation"
	DirAccess.make_dir_recursive_absolute(directory)
	var layout_path := directory.path_join("layout.tres")
	var scene_path := directory.path_join("weapon.tscn")
	check(panel.save_layout(layout_path) == OK,"Layout save must succeed")
	var restored := ResourceLoader.load(layout_path,"",ResourceLoader.CACHE_MODE_IGNORE) as WeaponLayout
	check(restored != null and restored.cells == panel.layout.cells and restored.attachment == panel.layout.attachment,"Layout reload must preserve cells and grip")
	check(panel.export_scene(scene_path) == OK,"Scene export must succeed")
	# Resaving the working layout must not modify an already exported weapon.
	panel.layout.cells.append(Vector2i(99,99))
	panel.save_layout(layout_path)
	var packed := ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var weapon := packed.instantiate() as RigidBody3D
	root.add_child(weapon)
	weapon.freeze = true
	check(weapon is SampleWeapon3D,"Exported weapon must retain the weapon/item inheritance")
	check(weapon.get_child_count() == 9,"Saved scene must retain all generated visual and collision children")
	check(is_equal_approx(weapon.mass,3*restored.material.mass_per_cell),"Saved scene must preserve material mass")
	check(weapon.attachment_local_position.is_equal_approx(restored.attachment_local()),"Export must preserve exact local grip placement")
	check(not weapon.sprite_visible and weapon.mesh_visible,"Export must preserve visual mode")
	if not Engine.is_editor_hint(): check(weapon.get_material_cells() == restored.cells,"Runtime weapon must recover its layout data")
	check(is_equal_approx(weapon.item_rotation,deg_to_rad(37)),"Export must preserve grip rotation")
	if not Engine.is_editor_hint():
		var icon: Texture2D = await weapon.create_item_image()
		check(icon != null,"Exported weapons must support inventory icon generation")
	weapon.free()
	panel.free()
	DirAccess.remove_absolute(scene_path)
	DirAccess.remove_absolute(layout_path)
	print("EDITOR_WEAPON_WORKSHOP_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
