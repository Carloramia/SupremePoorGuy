extends SceneTree
const View=preload("res://CurrentMapPreview.gd")
var view
var folder:=ProjectSettings.globalize_path("res://review")
var checks:Dictionary={}
var failures:=0
func check(value:bool,label:String) -> void:
	checks[label]=value
	if not value:failures+=1
	print(("PASS " if value else "FAIL ")+label)
func _initialize() -> void:call_deferred("run")
func capture(label:String) -> void:
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("current_"+label+".png"))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	root.size=Vector2i(1280,800);view=View.new();root.add_child(view);view.size=Vector2(1280,800);view.refresh_view()
	check(view.doc.sites.size()==JSON.parse_string(FileAccess.get_file_as_string(view.spec.layout_path)).sites.size() and view.assets.size()==view.doc.assets.size() and view.spec.tiles.size()==view.doc.background.source_tiles.tiles.size(),"current canonical layout and latest asset table are loaded")
	check(view.spec.layout_sha256==FileAccess.get_sha256(view.spec.layout_path),"native preview matches the saved editor layout hash")
	check(view.mountain_faces.get_child_count()>0,"near-side mountain art is rendered above its own fog")
	var rear_masks_ok:bool=view.face_materials.size()==view.spec.mountain_surfaces.size()
	for material in view.face_materials.values():rear_masks_ok=rear_masks_ok and material.get_shader_parameter("rear_mask_enabled")==true
	check(rear_masks_ok,"every mountain uses its own art silhouette for rear fog overlap")
	var shared_mist_ok:=true
	for material in view.face_materials.values():shared_mist_ok=shared_mist_ok and material.get_shader_parameter("fog_texture_available")==true and material.get_shader_parameter("fog_texture")==view.fog.texture
	check(shared_mist_ok,"stone rear veil uses the live fog colour without cutting the art")
	var first:=View.Sight.occluder(PackedVector2Array([Vector2(170,120),Vector2(220,120),Vector2(220,280),Vector2(170,280)]))
	var second:=View.Sight.occluder(PackedVector2Array([Vector2(250,120),Vector2(280,120),Vector2(280,280),Vector2(250,280)]))
	var saved:Vector2=view.player;view.player=Vector2(100,200)
	check(view._front_face_visible(first,[first,second]) and not view._front_face_visible(second,[first,second]),"separate mountains hidden behind the first ridge are not exposed")
	view.player=saved
	await capture("summoning_hut")
	view.focus_site("layout_foster_town");await capture("foster_known")
	var landmark:Node=view.remembered.get_node("layout_foster_town")
	var ground:Control=landmark.get_node("GroundPatch")
	check(ground.size.x>795*1.5 and view.remembered.z_index+ground.z_index>view.fog.z_index,"known town has an enlarged footing above the fog")
	view._approach_camera();await capture("foster_nearby")
	var started:=Time.get_ticks_usec()
	for i in 120:await process_frame
	var elapsed:=float(Time.get_ticks_usec()-started)/1000000.0
	var report:={"checks":checks,"failures":failures,"fps_after_warmup":Engine.get_frames_per_second(),"observed_process_fps":120.0/elapsed,"measurement_seconds":elapsed,"layout_sha256":view.spec.layout_sha256,"site_count":view.doc.sites.size(),"asset_count":view.assets.size(),"hd_tiles":view.spec.tiles.size()}
	FileAccess.open(folder.path_join("current_render_checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CURRENT_MAP_CAPTURE_COMPLETE ",view.doc.sites.size()," sites / ",view.doc.assets.size()," assets / ",view.spec.tiles.size()," original HD tiles")
	quit(1 if failures else 0)
