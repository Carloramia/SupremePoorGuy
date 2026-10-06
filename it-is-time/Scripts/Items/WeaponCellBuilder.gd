@tool
extends RefCounted

## Shared editor/runtime geometry, independent of gameplay and editor state.
static func add_cell(body: Node3D, cell: Vector2i, at: Vector3, material_data: Resource, show_sprite: bool, show_mesh: bool, save_owned: bool = false) -> void:
	var texture: Texture2D = material_data.get_display_texture()
	var size := Vector3(material_data.cell_size,material_data.cell_size,material_data.collision_thickness)
	var sprite := Sprite3D.new()
	sprite.name = "Material_%d_%d" % [cell.x,cell.y]
	sprite.texture = texture
	sprite.pixel_size = material_data.cell_size/maxf(texture.get_width(),1.0)
	sprite.position = at
	sprite.visible = show_sprite
	body.add_child(sprite)
	var mesh := MeshInstance3D.new()
	mesh.name = "MaterialMesh_%d_%d" % [cell.x,cell.y]
	var box := BoxMesh.new()
	box.size = size
	var appearance := StandardMaterial3D.new()
	appearance.albedo_texture = texture
	box.material = appearance
	mesh.mesh = box
	mesh.position = at
	mesh.visible = show_mesh
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	collision.name = "Collision_%d_%d" % [cell.x,cell.y]
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	body.add_child(collision)
	if save_owned:
		for child: Node in [sprite,mesh,collision]: child.owner = body

static func build_layout(layout: WeaponLayout, gameplay: bool = true) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = layout.display_name.validate_node_name() if not layout.display_name.is_empty() else "CustomWeapon"
	if gameplay:
		body.set_script(load("res://Scripts/Items/WeaponTest.gd"))
		body.set("default_material",layout.material)
		body.set("weapon_layout",layout)
		body.set("display_name",layout.display_name)
		body.set("sprite_visible",layout.sprite_visible)
		body.set("mesh_visible",layout.mesh_visible)
		body.set("attachment_canvas_position",layout.attachment)
		body.set("attachment_local_position",layout.attachment_local())
		body.set("item_rotation",layout.rotation_radians)
		body.set("preferred_holder_name",layout.holder_name)
		body.set("has_attachment_point",layout.attachment_is_set)
	body.mass = maxf(layout.cells.size()*layout.material.mass_per_cell,0.01)
	var middle := layout.center()
	for cell: Vector2i in layout.cells:
		var offset := (Vector2(cell)-middle)*layout.material.cell_size
		add_cell(body,cell,Vector3(offset.x,-offset.y,0),layout.material,layout.sprite_visible,layout.mesh_visible,true)
	return body
