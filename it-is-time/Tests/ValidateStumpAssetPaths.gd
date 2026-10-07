extends SceneTree

func _initialize() -> void:
	var base := "res://Assets/3DResources/Creatures/StumpBeast/"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "Metadata/rename_manifest.json"))
	var models: Dictionary = manifest.model_assets
	assert(models.size() == 27)
	for legacy: String in models:
		var model := load(base + models[legacy]) as PackedScene
		assert(model != null)
		var visual_root := model.instantiate()
		var visuals := visual_root.find_children("*", "MeshInstance3D", true, false)
		assert(not visuals.is_empty())
		assert((visuals[0] as MeshInstance3D).get_active_material(0).albedo_texture != null)
		visual_root.free()
		var wrapper_path: String = base + str(models[legacy]).replace("Models/", "Scenes/").replace(".glb", ".tscn")
		var wrapper := load(wrapper_path) as PackedScene
		assert(wrapper != null)
		var part := wrapper.instantiate()
		assert(part.has_node("JointIn") and part.has_node("JointOut"))
		part.free()
		var mesh_path := "res://Resources/Meshes/PaperParts/ToSplit_1/" + legacy.get_basename() + ".res"
		var mesh := load(mesh_path) as ArrayMesh
		assert(mesh != null and mesh.get_surface_count() >= 3)
		for dependency: String in ResourceLoader.get_dependencies(mesh_path):
			assert(not dependency.contains("Assets/3DResources/Creatures/PaperParts/ToSplit_1"))
		print("STUMP_ASSET_PASS ", legacy)
	for path: String in ["res://Scenes/Creatures/Characters/Generate_StumpBeast.tscn", "res://Scenes/Creatures/Characters/Generate_StumpBeast_NPC.tscn"]:
		var scene := load(path) as PackedScene
		assert(scene != null)
		var instance := scene.instantiate()
		assert(instance != null)
		instance.free()
	print("PASS: 27 models/textures/wrappers/baked meshes and StumpBeast/NPC scenes load after asset reorganization.")
	quit()
