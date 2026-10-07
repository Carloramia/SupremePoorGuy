extends SceneTree
const BUILDER = preload("res://Scripts/Geometry/PaperVolumeMeshBuilder.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var source_dir := "res://Assets/3DResources/Creatures/StumpBeast"
	var target_dir := "res://Resources/Meshes/PaperParts/ToSplit_1"
	var count := 0
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_dir.path_join("Metadata/rename_manifest.json")))
	var assets: Dictionary = manifest.model_assets
	for legacy: String in assets:
		var instance := load(source_dir.path_join(assets[legacy])).instantiate() as Node3D
		var visual := instance.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
		var baked := BUILDER.build(visual.mesh,visual.get_active_material(0))
		assert(baked != null,"Failed to bake " + legacy)
		var output := target_dir.path_join(legacy.get_basename()+".res")
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		assert(ResourceSaver.save(baked,output) == OK)
		print("PAPER_VOLUME_BAKED ",legacy," side_vertices=",baked.surface_get_array_len(2))
		instance.free()
		count += 1
	print("PAPER_VOLUMES_BAKED count=",count)
	quit()
