extends SceneTree

const BUILDER = preload("res://Scripts/Geometry/PaperVolumeMeshBuilder.gd")
const STATE = preload("res://Scripts/Creatures/BodyPartVisualState3D.gd")
const BACK_SHADER = preload("res://Shaders/PaperHandBack.gdshader")
const METADATA := "res://Assets/3DResources/Creatures/Human/Metadata/hand_state_models.json"
const MESH_ROOT := "res://Resources/Meshes/Human/HandStates/"
const STATE_ROOT := "res://Resources/Creatures/VisualStates/Human/"

func _initialize() -> void: call_deferred("run")

func quad(size: Vector2, anchor: Vector2, unit: float, angle: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var rotation := Basis(Vector3.BACK,angle)
	for pixel: Vector2 in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]:
		vertices.append(rotation*Vector3((pixel.x-anchor.x)*unit,(anchor.y-pixel.y)*unit,0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO,Vector2(1,0),Vector2.ONE,Vector2(0,1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func run() -> void:
	DirAccess.make_dir_recursive_absolute(MESH_ROOT)
	DirAccess.make_dir_recursive_absolute(STATE_ROOT)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(METADATA))
	var count := 0
	for record: Dictionary in data.models:
		for pose: String in ["open","grip"]:
			var front := load(record.states[pose].palm) as Texture2D
			var back := load(record.states[pose].back) as Texture2D
			assert(front != null and back != null)
			var material := StandardMaterial3D.new()
			material.albedo_texture = front
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			material.alpha_scissor_threshold = 0.5
			material.roughness = 1.0
			var source := quad(Vector2(data.canvas_size[0],data.canvas_size[1]),Vector2(data.anchor_pixels[0],data.anchor_pixels[1]),float(record.pixel_unit),float(record.rotation_z))
			var volume := BUILDER.build(source,material,384)
			assert(volume != null)
			var arrays: Array = volume.surface_get_arrays(1)
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for index: int in uvs.size(): uvs[index].x = 1.0-uvs[index].x
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			var back_material := ShaderMaterial.new()
			back_material.shader = BACK_SHADER
			back_material.set_shader_parameter(&"front_texture",front)
			back_material.set_shader_parameter(&"back_texture",back)
			var rebuilt := ArrayMesh.new()
			for surface: int in 3:
				rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays if surface == 1 else volume.surface_get_arrays(surface))
				rebuilt.surface_set_material(surface,back_material if surface == 1 else volume.surface_get_material(surface))
			var name := str(record.name)+pose.capitalize()
			var mesh_file := MESH_ROOT+name+".res"
			assert(ResourceSaver.save(rebuilt,mesh_file)==OK)
			var state := STATE.new()
			state.resource_name = name
			state.state_name = StringName(pose)
			state.mesh = load(mesh_file)
			state.anchor_path = ^"JointIn"
			assert(ResourceSaver.save(state,STATE_ROOT+name+".tres")==OK)
			count += 1
			print("HAND_STATE_BAKED ",name," side_vertices=",rebuilt.surface_get_array_len(2))
	assert(count==20)
	print("PASS: 20 cached hand pose meshes/presets, paired palm/back textures, mirrored back UVs and shared sealed silhouette.")
	quit()
