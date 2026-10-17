extends SceneTree
const BUILDER = preload("res://Scripts/Geometry/PaperVolumeMeshBuilder.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var base := "res://Assets/3DResources/Creatures/Rats/"
	var manifest_file := "hind_claw_model_manifest.json" if "--hind-claws-only" in OS.get_cmdline_user_args() else "model_manifest.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base+"Metadata/"+manifest_file))
	var baked:=0
	for record: Dictionary in manifest.models:
		if "--rat1-hind-feet-only" in OS.get_cmdline_user_args() and str(record.key) not in ["Rat_1/Feet/HindFoot1","Rat_1/Feet/HindFoot2"]: continue
		var scene := load(base+str(record.glb)) as PackedScene
		assert(scene != null)
		var instance := scene.instantiate()
		var visual := instance.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var material := visual.get_active_material(0).duplicate() as StandardMaterial3D
		material.albedo_texture = load(record.source) as Texture2D
		assert(material.albedo_texture != null)
		var volume := BUILDER.build(visual.mesh,material)
		assert(volume != null and volume.get_surface_count()==3)
		DirAccess.make_dir_recursive_absolute(str(record.volume_mesh).get_base_dir())
		assert(ResourceSaver.save(volume,record.volume_mesh)==OK)
		instance.free()
		baked+=1
	print("PASS: ",baked," Rats double-sided paper volumes baked.")
	quit()
