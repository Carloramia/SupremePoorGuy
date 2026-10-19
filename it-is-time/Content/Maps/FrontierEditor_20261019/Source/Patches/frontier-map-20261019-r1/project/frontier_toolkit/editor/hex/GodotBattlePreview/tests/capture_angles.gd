extends SceneTree
const View=preload("res://BattlePreview3D.gd")
var view
func _initialize() -> void:call_deferred("run")
func capture(label:String) -> void:
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://review/"+label+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://review"))
	root.size=Vector2i(1440,900);view=View.new();root.add_child(view)
	for id in ["battle_forest_wolf","battle_spider_tree"]:
		var index:int=0
		for i in view.spec.maps.size():
			if view.spec.maps[i].id==id:index=i;break
		for angle in [45,60,75]:
			view.tilt_override=angle;view.angle_picker.select([45,60,75].find(angle)+1);view.show_map(index);await capture(id+"_"+str(angle))
	print("ANGLE_CAPTURES_COMPLETE")
	quit()
