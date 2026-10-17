extends SceneTree

var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func bounds_of_shape(shape: ConvexPolygonShape3D) -> AABB:
	var low := Vector3(INF,INF,INF)
	var high := -low
	for point: Vector3 in shape.points:
		low = low.min(point)
		high = high.max(point)
	return AABB(low,high-low)

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Human/Metadata/model_manifest.json"))
	var record: Dictionary
	for entry: Dictionary in manifest.models:
		if entry.name == "Human1Spear": record = entry
	check(not record.is_empty(),"Spear1 model metadata must exist")
	var texture := load(record.source) as Texture2D
	check(texture.get_size() == Vector2(2324,2502),"Spear1 must use the latest 75% extended-shaft texture")
	check(is_equal_approx(record.units_per_texture_pixel,0.00587890625),"Pixel-to-world scale must remain unchanged when resizing the texture")
	check(is_equal_approx(record.thickness,0.08),"Requested thickness must remain 0.08")
	check(Vector2(record.visible_world_size[0],record.visible_world_size[1]).is_equal_approx(Vector2(13.37451171875,14.4268359375)),"XY model dimensions must reflect the latest 75% scale")
	var model := load("res://Assets/3DResources/Creatures/Human/Scenes/Weapons/Human1Spear.tscn").instantiate() as Node3D
	var paper := model.get_node("PaperVolume") as MeshInstance3D
	check(paper.mesh.get_surface_count() == 3,"Rebaked spear requires front, back and side surfaces")
	var model_bounds := paper.transform*paper.get_aabb()
	check(is_equal_approx(model_bounds.size.z,0.08),"Baked model Z depth must remain unchanged")
	check(is_equal_approx(model_bounds.size.x,texture.get_width()*record.units_per_texture_pixel) and is_equal_approx(model_bounds.size.y,texture.get_height()*record.units_per_texture_pixel),"3D plane must match the new PNG dimensions")
	check(model.get_node("JointOut").position.is_equal_approx(Vector3(3.705474609375,-3.7926,0)),"Tip connector relative to grip must scale only in XY")
	model.free()
	var part := load(record.physical_scene).instantiate() as PhysicalBodyPart3D
	part.freeze = true
	root.add_child(part)
	var part_bounds := bounds_of_shape(part.get_node("CollisionShape3D").shape)
	check(is_equal_approx(part.paper_volume_thickness,0.08) and is_equal_approx(part_bounds.size.z,0.16),"Legacy PhysicalPart retains visual depth and doubles collision depth")
	check(part.get_node("Model/PaperVolume").mesh.resource_path == record.volume_mesh,"Legacy Part must use the new baked model")
	check(part.get_node("JointOut").position.is_equal_approx(Vector3(3.705474609375,-3.7926,0)),"Legacy Part connector must match the rebuilt model")
	var item := load("res://Scenes/Items/Weapons/Human/Human1Spear.tscn").instantiate() as SampleWeapon3D
	item.freeze = true
	root.add_child(item)
	var weapon_bounds := bounds_of_shape(item.get_node("CollisionShape3D").shape)
	check(is_equal_approx(weapon_bounds.size.z,0.08) and is_equal_approx(part_bounds.size.z,weapon_bounds.size.z*2.0),"Only PhysicalBodyPart colliders gain depth padding")
	check(Vector2(weapon_bounds.size.x,weapon_bounds.size.y).is_equal_approx(Vector2(part_bounds.size.x,part_bounds.size.y)) and weapon_bounds.get_center().is_equal_approx(part_bounds.get_center()),"Weapon and legacy Part retain matching XY and center")
	check(item.attachment_local_position.is_equal_approx(Vector3(0.1172841796875,-0.141446484375,0)),"Weapon grip must follow the preserved shaft end through the 75% scale")
	check(is_equal_approx(item.mass,0.5) and is_equal_approx(part.mass,0.5),"The size-only edit must retain authored mass values")
	print("SPEAR1_RESIZE_DIMENSIONS texture=",texture.get_size()," model=",model_bounds.size," collision=",weapon_bounds.size," depth=",part.paper_volume_thickness)
	part.queue_free()
	item.queue_free()
	await process_frame
	print("HUMAN_SPEAR1_RESIZE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
