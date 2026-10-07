extends SceneTree
const BUILDER = preload("res://Scripts/Geometry/PaperVolumeMeshBuilder.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var source_dir := "res://Assets/3DResources/Creatures/PaperParts/ToSplit_1"
	var target_dir := "res://Resources/Meshes/PaperParts/ToSplit_1"
	var count := 0
	for group: String in ["Base","LeftLeg","RightLeg"]:
		DirAccess.make_dir_recursive_absolute(target_dir.path_join(group))
		for file: String in DirAccess.get_files_at(source_dir.path_join(group)):
			if not file.ends_with(".glb"): continue
			var instance := load(source_dir.path_join(group).path_join(file)).instantiate() as Node3D
			var visual := instance.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
			var baked := BUILDER.build(visual.mesh,visual.get_active_material(0))
			assert(baked != null,"Failed to bake " + file)
			var output := target_dir.path_join(group).path_join(file.get_basename()+".res")
			assert(ResourceSaver.save(baked,output) == OK)
			print("PAPER_VOLUME_BAKED ",file," side_vertices=",baked.surface_get_array_len(2))
			instance.free()
			count += 1
	print("PAPER_VOLUMES_BAKED count=",count)
	quit()
