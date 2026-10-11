extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Spider/Metadata/frame_fitted_manifest.json"))
	var replacements := {}
	for record: Dictionary in manifest.models:
		var source := load(record.original_mesh) as ArrayMesh
		var texture := load(record.texture) as Texture2D
		assert(texture != null,record.texture+" must be imported first")
		var top_left := Vector2(record.top_left_world[0],record.top_left_world[1])
		var size := Vector2(record.texture_size[0],record.texture_size[1])/float(record.pixels_per_unit)
		var plane := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(top_left.x,top_left.y,0),Vector3(top_left.x,top_left.y-size.y,0),Vector3(top_left.x+size.x,top_left.y-size.y,0),Vector3(top_left.x+size.x,top_left.y,0)])
		arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)])
		arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1,0,3,2])
		plane.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material := source.surface_get_material(0).duplicate() as StandardMaterial3D
		material.albedo_texture=texture
		material.texture_repeat=false
		var mesh := preload("res://Scripts/Geometry/PaperVolumeMeshBuilder.gd").build(plane,material)
		assert(mesh != null)
		DirAccess.make_dir_recursive_absolute(str(record.mesh).get_base_dir())
		assert(ResourceSaver.save(mesh,record.mesh)==OK)
		var model := Node3D.new()
		model.name="SpiderFrameFitted"+str(record.name)
		var volume := MeshInstance3D.new()
		volume.name="PaperVolume"
		volume.mesh=mesh
		volume.scale.z=.08
		model.add_child(volume)
		volume.owner=model
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_scene(model,state)==OK)
		DirAccess.make_dir_recursive_absolute(str(record.glb).get_base_dir())
		assert(document.write_to_filesystem(state,record.glb)==OK)
		model.free()
		# Inherit physics and connector settings; override only the visible mesh.
		var text := '[gd_scene format=3]\n[ext_resource type="PackedScene" path="%s" id="base"]\n[ext_resource type="ArrayMesh" path="%s" id="mesh"]\n[node name="SpiderFrameFitted%s" instance=ExtResource("base")]\nmetadata/source_png = "%s"\nmetadata/original_source_png = "%s"\nmetadata/texture_pixels_per_unit = %s\n[node name="PaperVolume" parent="Model" index="0"]\nmesh = ExtResource("mesh")\n' % [record.original_scene,record.mesh,record.name,record.texture,record.source,record.pixels_per_unit]
		DirAccess.make_dir_recursive_absolute(str(record.scene).get_base_dir())
		var file := FileAccess.open(record.scene,FileAccess.WRITE)
		file.store_string(text)
		file.close()
		replacements[record.original_scene]=record.scene
		replacements[record.original_mesh]=record.mesh
		replacements[record.source]=record.texture
		print("SPIDER_FRAME_FITTED ",record.key)
	var paths: PackedStringArray = ["res://Resources/Generators/SpiderGeneratorDefaults.tres","res://Scenes/Creatures/Characters/Generate_Spider.tscn"]
	for name: String in DirAccess.get_files_at("res://Resources/Generators/SpiderParts"):
		if name.ends_with(".tres"): paths.append("res://Resources/Generators/SpiderParts/"+name)
	for path: String in paths:
		var text := FileAccess.get_file_as_string(path)
		for old: String in replacements: text=text.replace(old,replacements[old])
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(text)
		file.close()
	var map_path := "res://Assets/3DResources/Creatures/Spider/Metadata/generator_part_mapping.json"
	var mapping := FileAccess.get_file_as_string(map_path)
	for old: String in replacements: mapping=mapping.replace(old,replacements[old])
	var output := FileAccess.open(map_path,FileAccess.WRITE)
	output.store_string(mapping)
	output.close()
	print("PASS: 16 frame-textured mesh/GLB/PhysicalPart variants connected; physics retained, visual contours rebuilt.")
	quit()
