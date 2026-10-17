extends SceneTree
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(960,720)
	var output := "D:/GameJamWorkspace/Reports/DeliveryIntegration_2026-10-16"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
	assert(DirAccess.make_dir_recursive_absolute(output)==OK)
	for id: String in CATALOG.index().maps:
		if CATALOG.map_data(id).kind!="battle": continue
		var host := preload("res://Scripts/Application/BattleHost.gd").new()
		host.delivery_settings = preload("res://Resources/Application/FrontierDeliveryBattle.tres")
		host.delivery_request = {"battle_map_id":id,"enemy_config_id":"wolf_clear_team","deployment_id":""}
		root.add_child(host)
		var adapter := preload("res://Scripts/Application/DeliveryBattleEnvironmentAdapter.gd").new()
		assert(adapter.build(host,[preload("res://Scripts/Application/CreatureFactory.gd").template("human")]))
		host.add_child(host._geometry)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = float(adapter.layout.radius)*adapter.scale*2.25
		camera.position = Vector3(0,camera.size*0.8,camera.size*0.8)
		host.add_child(camera)
		camera.look_at(Vector3.ZERO)
		camera.current = true
		for frame: int in 8: await process_frame
		RenderingServer.force_draw()
		assert(root.get_texture().get_image().save_png(output+"/environment_"+id+".png")==OK)
		print("ENVIRONMENT_CAPTURE ",id)
		host.queue_free()
		await process_frame
		await process_frame
	print("DELIVERY_ENVIRONMENT_CAPTURE_PASSED")
	quit()
