extends SceneTree

const BUILDER = preload("res://Scripts/Geometry/PaperVolumeMeshBuilder.gd")
const MANIFEST = "res://Assets/3DResources/Creatures/Bird/Metadata/model_manifest.json"

func _initialize() -> void: call_deferred("run")

func _write(path: String, text: String) -> void:
	assert(DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()

func run() -> void:
	var console := root.get_node_or_null("RuntimeConsole")
	if console != null: console.set("auto_getlogs_enabled", false)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for r: Dictionary in manifest.models:
		var unit := float(r.units_per_texture_pixel)
		var x := float(r.pivot_pixel[0])
		var y := float(r.pivot_pixel[1])
		var width := float(r.texture_size[0])
		var height := float(r.texture_size[1])
		var plane := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-x*unit,y*unit,0),Vector3(-x*unit,(y-height)*unit,0),Vector3((width-x)*unit,(y-height)*unit,0),Vector3((width-x)*unit,y*unit,0)])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)])
		# Godot front faces use clockwise winding; the GLTF exporter converts conventions.
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1,0,3,2])
		plane.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(r.texture) as Texture2D
		assert(material.albedo_texture != null,str(r.texture)+" must be imported first")
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.texture_repeat = false
		var mesh := BUILDER.build(plane,material,int(manifest.outline_resolution))
		assert(mesh != null and mesh.get_surface_count() == 3)
		DirAccess.make_dir_recursive_absolute(str(r.volume_mesh).get_base_dir())
		assert(ResourceSaver.save(mesh,r.volume_mesh) == OK)
		var model := Node3D.new()
		model.name = "Bird"+str(r.set)+str(r.name)
		var paper := MeshInstance3D.new()
		paper.name = "PaperVolume"
		paper.mesh = mesh
		paper.scale.z = float(r.thickness)
		paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		paper.set_meta("flat_collision_depth",0.02)
		model.add_child(paper)
		paper.owner = model
		var packed := PackedScene.new()
		assert(packed.pack(model) == OK)
		DirAccess.make_dir_recursive_absolute(str(r.model_scene).get_base_dir())
		assert(ResourceSaver.save(packed,r.model_scene) == OK)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_scene(model,state) == OK)
		DirAccess.make_dir_recursive_absolute(str(r.glb).get_base_dir())
		assert(document.write_to_filesystem(state,r.glb) == OK)
		if not FileAccess.file_exists(str(r.glb)+".import"):
			_write(str(r.glb)+".import","[remap]\nimporter=\"scene\"\n\n[params]\ngltf/embedded_image_handling=3\n")
		model.free()
		print("BIRD_BAKED ",r.key," side_vertices=",mesh.surface_get_array_len(2))
	print("PASS: ",manifest.model_count," Bird textured volumes, solid GLBs and model scenes baked.")
	quit()
