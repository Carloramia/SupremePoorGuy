extends SceneTree
const BUILDER = preload("res://Scripts/Geometry/PaperVolumeMeshBuilder.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var base := "res://Assets/3DResources/Creatures/Ratkin/"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "Metadata/model_manifest.json"))
	for record: Dictionary in manifest.models:
		if not OS.get_cmdline_user_args().is_empty() and str(record.name) != OS.get_cmdline_user_args()[0]: continue
		var scene := load(base + str(record.glb)) as PackedScene
		assert(scene != null)
		var instance := scene.instantiate()
		var visual := instance.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var material := visual.get_active_material(0).duplicate() as StandardMaterial3D
		material.albedo_texture = load(record.source) as Texture2D
		assert(material.albedo_texture != null)
		var volume := BUILDER.build(visual.mesh, material)
		assert(volume != null and volume.get_surface_count() == 3)
		DirAccess.make_dir_recursive_absolute(str(record.volume_mesh).get_base_dir())
		assert(ResourceSaver.save(volume, record.volume_mesh) == OK)
		print("RATKIN_VOLUME_BAKED ", record.category, "/", record.name, " side_vertices=", volume.surface_get_array_len(2))
		instance.free()
	print("PASS: selected Ratkin paper volumes baked with original front/back textures.")
	quit()

