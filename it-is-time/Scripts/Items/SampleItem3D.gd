class_name SampleItem3D
extends RigidBody3D

@export_group("Item")
@export var can_be_picked_up: bool = true
@export var display_name: String = "Item"
@export var item_image: Texture2D
@export_range(32, 512, 1) var generated_image_size: int = 128

@export_group("Visuals")
@export var sprite_visible: bool = true:
	set(value):
		sprite_visible = value
		_temporary_item_image = null
		_sync_visual_visibility()
@export var mesh_visible: bool = false:
	set(value):
		mesh_visible = value
		_temporary_item_image = null
		_sync_visual_visibility()

@export_group("Attachment")
@export var attachment_canvas_position: Vector2 = Vector2.ZERO
@export var attachment_local_position: Vector3 = Vector3.ZERO
@export var item_rotation: float = 0.0
@export var preferred_holder_name: StringName = &"Arm_R"
@export var has_attachment_point: bool = false

## Non-null while this item shares the holder's compound rigid body.
var rigid_attachment_holder: RigidBody3D

var _temporary_item_image: Texture2D

func _ready() -> void:
	_sync_visual_visibility()
	child_entered_tree.connect(_on_visual_child_entered)

func _on_visual_child_entered(child: Node) -> void:
	_apply_visual_visibility(child)
	_temporary_item_image = null

func _sync_visual_visibility() -> void:
	for child: Node in get_children():
		_apply_visual_visibility(child)

func _apply_visual_visibility(node: Node) -> void:
	if node is Sprite3D:
		(node as Sprite3D).visible = sprite_visible
	elif node is MeshInstance3D:
		(node as MeshInstance3D).visible = mesh_visible
	for child: Node in node.get_children():
		_apply_visual_visibility(child)

func is_pickable() -> bool:
	return can_be_picked_up and not is_queued_for_deletion()

func get_item_image() -> Texture2D:
	return item_image if item_image != null else _temporary_item_image

func configure_attachment(
	canvas_position: Vector2,
	local_position: Vector3,
	item_rotation_radians: float,
	holder_name: StringName
) -> void:
	attachment_canvas_position = canvas_position
	attachment_local_position = local_position
	item_rotation = item_rotation_radians
	preferred_holder_name = holder_name
	has_attachment_point = true

## Returns the assigned image, or renders a temporary square image from the item's 3D visuals.
func create_item_image() -> Texture2D:
	if item_image != null:
		return item_image
	if _temporary_item_image != null:
		return _temporary_item_image
	if DisplayServer.get_name() == "headless":
		_temporary_item_image = _create_fallback_item_image()
		return _temporary_item_image
	var viewport := SubViewport.new()
	viewport.name = "ItemImageViewport"
	viewport.size = Vector2i(generated_image_size, generated_image_size)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.world_3d = World3D.new()
	get_tree().root.add_child(viewport)
	var preview_root := Node3D.new()
	viewport.add_child(preview_root)
	var preview := duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
	if preview == null:
		viewport.queue_free()
		return null
	preview.name = "ItemPreview"
	preview.set_script(null)
	preview.position = Vector3.ZERO
	preview.rotation = Vector3.ZERO
	preview.scale = Vector3.ONE
	preview_root.add_child(preview)
	# Inventory storage hides the live item before requesting its icon. The
	# duplicate inherits that visibility, so force only the preview root visible.
	_prepare_preview_tree(preview, true)
	var bounds := _calculate_preview_bounds(preview)
	var center := bounds.get_center()
	var extent := maxf(maxf(bounds.size.x, bounds.size.y), 0.5)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = extent * 1.35
	camera.position = center + Vector3(0.0, 0.0, maxf(bounds.size.z, 0.5) + extent * 2.0)
	preview_root.add_child(camera)
	camera.look_at(center, Vector3.UP)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25.0, -25.0, 0.0)
	light.shadow_enabled = false
	preview_root.add_child(light)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if _image_has_visible_pixels(image):
		_temporary_item_image = ImageTexture.create_from_image(image)
	viewport.queue_free()
	if _temporary_item_image == null:
		_temporary_item_image = _create_fallback_item_image()
	return _temporary_item_image

func _create_fallback_item_image() -> Texture2D:
	var image := Image.create(generated_image_size, generated_image_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var margin := maxi(generated_image_size / 8, 2)
	image.fill_rect(
		Rect2i(margin, margin, generated_image_size - margin * 2, generated_image_size - margin * 2),
		Color(0.9, 0.9, 0.92, 1.0)
	)
	return ImageTexture.create_from_image(image)

func _prepare_preview_tree(root: Node, force_root_visible: bool = false) -> void:
	root.process_mode = Node.PROCESS_MODE_DISABLED
	if force_root_visible and root is Node3D:
		(root as Node3D).visible = true
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = true
	for child: Node in root.get_children():
		_prepare_preview_tree(child)

func _image_has_visible_pixels(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.01:
				return true
	return false

func _calculate_preview_bounds(root: Node3D) -> AABB:
	var result := AABB(Vector3(-0.5, -0.5, -0.1), Vector3(1.0, 1.0, 0.2))
	var found_visual := false
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if not visual.is_visible_in_tree():
			continue
		var visual_bounds := root.global_transform.affine_inverse() * visual.global_transform * visual.get_aabb()
		if found_visual:
			result = result.merge(visual_bounds)
		else:
			result = visual_bounds
			found_visual = true
	return result
