extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var preview := Node3D.new()
	preview.name = "HumanWeaponsPreview"
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.13,0.14,0.16)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	preview.add_child(environment)
	environment.owner = preview
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-18,-20,0)
	light.light_energy = 0.7
	preview.add_child(light)
	light.owner = preview
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Human/Metadata/weapon_manifest.json"))
	var index := 0
	for record: Dictionary in data.weapons:
		var model := load(record.model_scene).instantiate() as Node3D
		var mesh := model.get_node("PaperVolume") as MeshInstance3D
		var bounds := mesh.transform * mesh.get_aabb()
		var fit := minf(4.2/bounds.size.y,4.4/bounds.size.x)
		var slot := Vector3((index%3-1)*5.2,2.5 if index<3 else -2.7,0)
		model.name = record.name
		model.basis = Basis(Vector3.UP,deg_to_rad(-8.0))*Basis.from_scale(Vector3.ONE*fit)
		model.position = slot-model.basis*bounds.get_center()
		preview.add_child(model)
		model.owner = preview
		var label := Label3D.new()
		label.text = str(record.name)
		label.position = slot+Vector3(0,2.45,0)
		label.font_size = 38
		label.pixel_size = 0.006
		label.outline_size = 0
		preview.add_child(label)
		label.owner = preview
		index += 1
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.5
	camera.position = Vector3(0,0.25,18)
	camera.current = true
	preview.add_child(camera)
	camera.owner = preview
	var packed := PackedScene.new()
	assert(packed.pack(preview)==OK)
	assert(ResourceSaver.save(packed,"res://Assets/3DResources/Creatures/Human/Previews/HumanWeaponsPreview.tscn")==OK)
	if DisplayServer.get_name() != "headless":
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1536,960)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		viewport.add_child(preview)
		for tick: int in 5: await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		assert(image != null and not image.is_empty())
		assert(image.save_png("D:/GameJamWorkspace/Reports/HumanWeapons_Preview.png")==OK)
	else: preview.free()
	print("PASS: Human weapon 3D gallery saved; grid display scale does not change weapon scenes.")
	quit()
