extends SceneTree

const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const SOURCE_POSE = preload("res://Content/Maps/FrontierEditor_20261019/Source/Patches/frontier-map-20261019-r1/project/frontier_toolkit/editor/godot/battle_visual_pose.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	CATALOG.select_version("20261019")
	var sprites := 0
	var translucent := 0
	for info: Dictionary in CATALOG.index().maps.values():
		if info.kind != "battle": continue
		var data := CATALOG.map_data(info.id)
		var scene := load(info.scene_3d).instantiate() as Node3D
		root.add_child(scene)
		check(scene.find_children("PhysicalPart","",true,false).is_empty(),"No thick scenery: "+str(info.id))
		for object: Dictionary in data.objects:
			var sprite := scene.get_node_or_null("Objects/"+str(object.id)+"/Visual") as Sprite3D
			if sprite == null: continue
			var asset: Dictionary = CATALOG.index().battle_assets[object.visual.asset]
			check(sprite.texture.resource_path == asset.get("render_path",asset.path),"Source texture: "+str(object.id))
			var expected := Sprite3D.new()
			expected.texture = sprite.texture
			sprite.get_parent().add_child(expected)
			SOURCE_POSE.apply(expected,sprite.get_parent(),object,float(data.presentation.scenery_tilt_degrees))
			check(sprite.global_transform.is_equal_approx(expected.global_transform),"Native preview pose: "+str(object.id))
			check(sprite.billboard == expected.billboard and sprite.get_meta("surface_mode") == expected.get_meta("surface_mode"),"Source surface mode: "+str(object.id))
			expected.free()
			check(is_equal_approx(sprite.modulate.a,float(object.visual.opacity)),"Source opacity: "+str(object.id))
			check(sprite.pixel_size == 1.0 and sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS and sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS and sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Source rendering: "+str(object.id))
			sprites += 1
			if object.visual.opacity != 1.0: translucent += 1
		scene.free()
	check(sprites == 2263 and translucent == 350,"Complete scenery and authored transparency coverage")
	CATALOG.select_version("20261015")
	print("SOURCE_SCENERY_CHECKS ",checks," sprites=",sprites," translucent=",translucent," failures=",failures.size())
	for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
