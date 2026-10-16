extends SceneTree
## Two phases: --prepare, editor import, then --bake. Originals stay read-only.
const BUILDER = preload("res://Scripts/Geometry/PaperVolumeMeshBuilder.gd")
const INDEX = "res://Content/Maps/FrontierDelivery_20261015/Data/Maps/index.json"
const BASE = "res://Assets/3DResources/Environment/FrontierBattle"
const IMAGES = "res://Assets/2DResources/Environment/FrontierBattle"
const PARTS = "res://Scenes/Environment/FrontierBattle"
const MESHES = "res://Resources/Meshes/Environment/FrontierBattle"
const PIXEL_UNIT = 0.01
const OUTLINE_SIZE = 192
const COLLISION_SIZE = 96
const ALPHA_THRESHOLD = 0.1
# Stable, readable names instead of the importer's content hashes.
const SPECS = {
	"altar": ["GroundDecorations", "ActiveAltar"],
	"battle_dry_patch": ["GroundDecorations", "DryGrassPatch"],
	"battle_leaf_litter": ["GroundDecorations", "LeafLitter"],
	"battle_shale_patch": ["GroundDecorations", "ShalePatch"],
	"demo_barricade_broken": ["GroundDecorations", "BrokenBarricade"],
	"demo_grass_tuft": ["GroundDecorations", "GrassTuft"],
	"demo_rock_gravel": ["GroundDecorations", "Gravel"],
	"demo_summoning_array_idle": ["GroundDecorations", "SummoningArray"],
	"demo_wood_fragment": ["GroundDecorations", "WoodFragment"],
	"mud": ["GroundEffects", "Mud"],
	"pit": ["GroundEffects", "PitArtwork"],
	"thorns": ["GroundEffects", "Thorns"],
	"web": ["GroundEffects", "Web"],
	"battle_broken_stump": ["Props", "BrokenStump"],
	"battle_cave_mouth": ["Props", "CaveMouth"],
	"battle_rat_mound": ["Props", "RatMound"],
	"battle_root_fan": ["Props", "RootFan"],
	"battle_supply_crate": ["Props", "SupplyCrate"],
	"demo_monster_camp": ["Props", "TentAndFlag"],
	"demo_rock_large": ["Props", "LargeRock"],
	"rock": ["Props", "LargeRock"],
	"frontier_dead": ["Props", "DeadTree"],
	"tree": ["Props", "LivingTree"],
}

func _initialize() -> void: _run.call_deferred()

func _write(path: String, content: String) -> void:
	assert(DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, path)
	file.store_string(content)

func _image(path: String) -> Image:
	var result := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert(result != null and not result.is_empty(), path)
	result.convert(Image.FORMAT_RGBA8)
	return result

func _collect() -> Array[Dictionary]:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	var assets: Dictionary = catalog.battle_art.assets
	var groups := {}
	for map_id: String in catalog.maps:
		var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(catalog.maps[map_id].data))
		if map.kind != "battle": continue
		for object: Dictionary in map.objects:
			if object.type == "edge_decoration" or str(object.visual.asset).is_empty(): continue
			var id: String = catalog.battle_art.object_assets.get(map_id, {}).get(object.id, object.visual.asset)
			assert(SPECS.has(id) and assets.has(id), "Unclassified battle asset: " + id)
			var asset: Dictionary = assets[id]
			var key: String = asset.sha256
			if not groups.has(key):
				var spec: Array = SPECS[id]
				var folder: String = spec[0]
				var name: String = spec[1]
				var relative := folder + "/" + name
				groups[key] = {"name":name,"category":folder,"label":asset.name,
					"asset_ids":[],"uses":[],"source":asset.path,"source_sha256":key,
					"image":IMAGES+"/Separated/"+relative+".png",
					"texture":BASE+"/Textures/"+relative+".png",
					"glb":BASE+"/Models/"+relative+".glb",
					"model_scene":BASE+"/Scenes/"+relative+".tscn",
					"volume_mesh":MESHES+"/"+relative+".res",
					"unit_collision":MESHES+"/"+relative+"Collision.res",
					"physical_scene":PARTS+"/"+relative+".tscn",
					"ground":folder != "Props","thickness":0.02 if folder != "Props" else 0.08,
					"units_per_pixel":PIXEL_UNIT,"alpha_threshold":ALPHA_THRESHOLD,
					"authored_pivot":asset.get("pivotPixels",[])}
			if id not in groups[key].asset_ids: groups[key].asset_ids.append(id)
			groups[key].uses.append({"map_id":map_id,"object_id":object.id,"type":object.type,
				"visual_size":object.visual.size,"source_asset_id":id})
	var records: Array[Dictionary] = []
	for value: Dictionary in groups.values(): records.append(value)
	records.sort_custom(func(a,b): return a.image < b.image)
	return records

func _prepare(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		assert(FileAccess.get_sha256(record.source) == record.source_sha256)
		var image := _image(record.source)
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(image, ALPHA_THRESHOLD)
		var bounds := Rect2i()
		var first := true
		for y: int in image.get_height():
			for x: int in image.get_width():
				if not bitmap.get_bit(x,y): continue
				if first: bounds = Rect2i(x,y,1,1); first = false
				else: bounds = bounds.merge(Rect2i(x,y,1,1))
		assert(not first, record.source)
		record.texture_size = [image.get_width(),image.get_height()]
		record.alpha_bounds = [bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]
		var pivot := Vector2(bounds.position) + Vector2(bounds.size)*Vector2(0.5,1.0)
		if record.ground: pivot = Vector2(image.get_size())*0.5
		record.pivot_pixel = [pivot.x,pivot.y]
		for target: String in [record.image,record.texture]:
			assert(DirAccess.make_dir_recursive_absolute(target.get_base_dir()) == OK)
			# Rebuilds cannot silently overwrite a manually changed texture.
			if FileAccess.file_exists(target): assert(_image(target).get_data() == image.get_data(), "Edited output: " + target)
			elif str(record.source).ends_with(".png"): assert(DirAccess.copy_absolute(record.source,target) == OK)
			else: assert(image.save_png(target) == OK)
		print("ENVIRONMENT_IMAGE ",record.category,"/",record.name)
	_write(BASE+"/Metadata/model_manifest.json",JSON.stringify({"model_count":records.size(),
		"source_index":INDEX,"pixel_unit":PIXEL_UNIT,"outline_max_size":OUTLINE_SIZE,
		"collision_max_size":COLLISION_SIZE,"models":records},"\t")+"\n")

func _plane(record: Dictionary) -> ArrayMesh:
	var w := float(record.texture_size[0])*PIXEL_UNIT
	var h := float(record.texture_size[1])*PIXEL_UNIT
	var x := -float(record.pivot_pixel[0])*PIXEL_UNIT
	var y := float(record.pivot_pixel[1])*PIXEL_UNIT
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(x,y,0),Vector3(x,y-h,0),Vector3(x+w,y,0),Vector3(x+w,y-h,0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(0,1),Vector2(1,0),Vector2(1,1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1,1,2,3])
	var plane := ArrayMesh.new()
	plane.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return plane

func _collision(record: Dictionary, plane: ArrayMesh, material: StandardMaterial3D) -> ConcavePolygonShape3D:
	# Approximate alpha at a bounded resolution, retaining holes and disjoint pieces.
	# Opaque row runs merge into rectangles; transparent face padding never collides.
	var image := _image(record.image)
	var ratio := minf(1.0,float(COLLISION_SIZE)/maxi(image.get_width(),image.get_height()))
	image.resize(maxi(1,roundi(image.get_width()*ratio)),maxi(1,roundi(image.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image,ALPHA_THRESHOLD)
	var active := {}
	var rectangles: Array[Rect2i] = []
	for y: int in range(image.get_height()+1):
		var next := {}
		var start := -1
		for x: int in range(image.get_width()+1):
			var solid := y < image.get_height() and x < image.get_width() and bitmap.get_bit(x,y)
			if solid and start < 0: start = x
			if solid or start < 0: continue
			var key := Vector2i(start,x)
			var rectangle: Rect2i = active.get(key,Rect2i(start,y,x-start,0))
			rectangle.size.y += 1
			next[key] = rectangle
			start = -1
		for key: Vector2i in active:
			if not next.has(key): rectangles.append(active[key])
		active = next
	var faces := PackedVector3Array()
	var pixel_scale := Vector2(record.texture_size[0],record.texture_size[1])/Vector2(image.get_size())*PIXEL_UNIT
	var pivot := Vector2(record.pivot_pixel[0],record.pivot_pixel[1])*PIXEL_UNIT
	for rect: Rect2i in rectangles:
		var a := Vector2(rect.position)*pixel_scale
		var b := Vector2(rect.end)*pixel_scale
		for z: float in [-0.5,0.5]:
			var points := PackedVector3Array([Vector3(a.x-pivot.x,pivot.y-a.y,z),Vector3(b.x-pivot.x,pivot.y-a.y,z),Vector3(a.x-pivot.x,pivot.y-b.y,z),Vector3(b.x-pivot.x,pivot.y-b.y,z)])
			var indices := [0,1,2,2,1,3] if z > 0 else [0,2,1,2,3,1]
			for index: int in indices: faces.append(points[index])
	var small_volume: ArrayMesh = BUILDER.build(plane,material,COLLISION_SIZE)
	assert(small_volume != null)
	var side_arrays := small_volume.surface_get_arrays(2)
	var vertices: PackedVector3Array = side_arrays[Mesh.ARRAY_VERTEX]
	for index: int in side_arrays[Mesh.ARRAY_INDEX]: faces.append(vertices[index])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	return shape

func _bake(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(record.texture) as Texture2D
		assert(material.albedo_texture != null)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		material.alpha_scissor_threshold = ALPHA_THRESHOLD
		var plane := _plane(record)
		var mesh: ArrayMesh = BUILDER.build(plane,material,OUTLINE_SIZE)
		assert(mesh != null and mesh.get_surface_count() == 3)
		mesh.surface_get_material(2).albedo_color = Color(0.32,0.30,0.23)
		assert(DirAccess.make_dir_recursive_absolute(str(record.volume_mesh).get_base_dir()) == OK)
		assert(ResourceSaver.save(mesh,record.volume_mesh) == OK)
		var shape := _collision(record,plane,material)
		assert(ResourceSaver.save(shape,record.unit_collision) == OK)
		var rotation := "-1.5707963268" if record.ground else "0"
		var model_text := "[gd_scene load_steps=2 format=3]\n[ext_resource type=\"ArrayMesh\" path=\"%s\" id=\"mesh\"]\n[node name=\"%s\" type=\"Node3D\"]\nrotation = Vector3(%s, 0, 0)\n[node name=\"Visual\" type=\"MeshInstance3D\" parent=\".\"]\nscale = Vector3(1, 1, %s)\nmesh = ExtResource(\"mesh\")\ncast_shadow = 0\n" % [record.volume_mesh,record.name,rotation,record.thickness]
		_write(record.model_scene,model_text)
		var model := load(record.model_scene).instantiate() as Node3D
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_scene(model,state) == OK)
		assert(DirAccess.make_dir_recursive_absolute(str(record.glb).get_base_dir()) == OK)
		assert(document.write_to_filesystem(state,record.glb) == OK)
		if not FileAccess.file_exists(record.glb+".import"):
			_write(record.glb+".import","[remap]\nimporter=\"scene\"\n\n[params]\ngltf/embedded_image_handling=3\n")
		model.free()
		var part_text := "[gd_scene load_steps=5 format=3]\n[ext_resource type=\"Script\" path=\"res://Scripts/Geometry/BattleEnvironmentPhysicalPart3D.gd\" id=\"script\"]\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"model\"]\n[ext_resource type=\"ConcavePolygonShape3D\" path=\"%s\" id=\"collision\"]\n[sub_resource type=\"ConcavePolygonShape3D\" id=\"initial\"]\n[node name=\"%s\" type=\"StaticBody3D\"]\nscript = ExtResource(\"script\")\nthickness = %s\nunit_collision = ExtResource(\"collision\")\nmetadata/source_asset_ids = %s\nmetadata/source_png = \"%s\"\n[node name=\"Model\" parent=\".\" instance=ExtResource(\"model\")]\n[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\".\"]\nrotation = Vector3(%s, 0, 0)\nshape = SubResource(\"initial\")\n" % [record.model_scene,record.unit_collision,record.name,record.thickness,JSON.stringify(record.asset_ids),record.image,rotation]
		_write(record.physical_scene,part_text)
		print("ENVIRONMENT_MODEL ",record.category,"/",record.name," collision_triangles=",shape.get_faces().size()/3)
	_preview(records)

func _preview(records: Array[Dictionary]) -> void:
	var text := "[gd_scene format=3]\n"
	for i: int in records.size(): text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]\n" % [records[i].physical_scene,i]
	text += "[sub_resource type=\"Environment\" id=\"env\"]\nbackground_mode = 1\nbackground_color = Color(0.12, 0.15, 0.18, 1)\n[node name=\"FrontierBattlePartsPreview\" type=\"Node3D\"]\n[node name=\"Camera3D\" type=\"Camera3D\" parent=\".\"]\ntransform = Transform3D(1, 0, 0, 0, 0.8320503, -0.5547002, 0, 0.5547002, 0.8320503, 0, 25, 37.5)\nprojection = 1\nsize = 34.0\ncurrent = true\n[node name=\"WorldEnvironment\" type=\"WorldEnvironment\" parent=\".\"]\nenvironment = SubResource(\"env\")\n"
	for i: int in records.size():
		var record: Dictionary = records[i]
		var x := (i%6-2.5)*8
		var z := (i/6-1.5)*15
		var extent := float(maxi(int(record.texture_size[0]),int(record.texture_size[1])))*PIXEL_UNIT
		var fit := 5.8/extent
		text += "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]\nposition = Vector3(%s, 0, %s)\nscale = Vector3(%s, %s, %s)\ncollision_enabled = false\n[node name=\"Label%s\" type=\"Label3D\" parent=\".\"]\nposition = Vector3(%s, 0.1, %s)\ntext = \"%s\"\nfont_size = 32\npixel_size = 0.025\nbillboard = 1\nno_depth_test = true\n" % [record.name,i,x,z,fit,fit,fit,i,x,z+3.2,record.name]
	_write(BASE+"/Previews/FrontierBattlePartsPreview.tscn",text)

func _run() -> void:
	if "--prepare" in OS.get_cmdline_user_args():
		var records := _collect()
		_prepare(records)
		print("ENVIRONMENT_PREPARED count=",records.size())
	elif "--bake" in OS.get_cmdline_user_args():
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE+"/Metadata/model_manifest.json"))
		var records: Array[Dictionary] = []
		for record: Dictionary in manifest.models: records.append(record)
		_bake(records)
		print("ENVIRONMENT_BAKED count=",records.size())
	else: push_error("Use --prepare or --bake"); quit(1); return
	quit()
