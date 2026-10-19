extends SceneTree
const BUILDER = preload("res://Scripts/Geometry/PaperVolumeMeshBuilder.gd")
const BASE := "res://Content/Maps/FrontierEditor_20261019/Runtime"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var console := root.get_node_or_null("RuntimeConsole")
	if console!=null: console.auto_getlogs_enabled=false
	var specs: Array=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/paper_parts.json"))
	DirAccess.make_dir_recursive_absolute(BASE+"/PaperParts")
	for spec: Dictionary in specs:
		var material := StandardMaterial3D.new()
		material.albedo_texture=load(spec.path) as Texture2D
		assert(material.albedo_texture!=null,spec.path)
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		material.alpha_scissor_threshold=0.1
		var plane := QuadMesh.new()
		plane.size=Vector2.ONE
		var mesh: ArrayMesh=BUILDER.build(plane,material,128)
		assert(mesh!=null and mesh.get_surface_count()==3,str(spec.id))
		mesh.surface_get_material(2).albedo_color=Color(0.32,0.30,0.23)
		var path := BASE+"/PaperParts/"+str(spec.id)
		assert(ResourceSaver.save(mesh,path+".res")==OK)
		var file := FileAccess.open(path+".tscn",FileAccess.WRITE)
		assert(file!=null)
		file.store_string("[gd_scene load_steps=2 format=3]\n[ext_resource type=\"ArrayMesh\" path=\"%s.res\" id=\"mesh\"]\n[node name=\"PaperScenery\" type=\"Node3D\"]\nmetadata/collision_enabled = false\n[node name=\"Visual\" type=\"MeshInstance3D\" parent=\".\"]\nmesh = ExtResource(\"mesh\")\ncast_shadow = 0\n" % path)
	print("HEX_PAPER_PARTS_BAKED count=",specs.size())
	quit()
