extends SceneTree
const LEGACY=preload("res://Modules/FrontierDelivery/Scripts/Map/FrontierMapView.gd")
var failed:=false
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failed=true; push_error(label)
func frames(count: int=3) -> void:
	for frame in count: await process_frame
func mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event:=InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=button; event.pressed=pressed
	root.push_input(event,true); await process_frame
func motion(point: Vector2, relative: Vector2) -> void:
	var event:=InputEventMouseMotion.new(); event.position=point; event.global_position=point; event.relative=relative
	root.push_input(event,true); await process_frame
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	root.size=Vector2i(1280,720)
	var app:=preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path="res://Tests/.runtime/map_controls_%d.json"%Time.get_ticks_usec(); app.display_settings_path=app.save_path+".cfg"
	root.add_child(app); app.ui.animate_panels=false; app.ui.board_motion.enabled=false
	app.start_new_game()
	for frame in 600:
		if app.phase=="world": break
		await process_frame
	app.ui._close_all(); await frames()
	var map: Control=app.hex_map
	var legacy:=LEGACY.new()
	check(is_equal_approx(map.zoom*map.doc.vision_radius,legacy.zoom*legacy.Catalog.world().fog.radius),"Default screen scale matches pre-event integrated map")
	check(is_equal_approx(map.zoom*180*map.reference_unit_scale,legacy.zoom*180),"Default on-screen walk speed matches original map")
	legacy.free()
	var local_point:=map.size*.5+Vector2(100,50)
	var screen_point: Vector2=app.map_container.get_global_transform_with_canvas()*local_point
	var world_before: Vector2=map.screen_to_world(local_point)
	var zoom_before: float=map.zoom
	await mouse(screen_point,MOUSE_BUTTON_WHEEL_UP,true)
	check(is_equal_approx(map.zoom,zoom_before*1.15),"Wheel increment preserves original 1.15 factor")
	check(map.screen_to_world(local_point).distance_to(world_before)<.02,"Wheel zoom anchors the actual mouse world point")
	await mouse(screen_point,MOUSE_BUTTON_WHEEL_DOWN,true)
	check(is_equal_approx(map.zoom,zoom_before) and map.screen_to_world(local_point).distance_to(world_before)<.02,"Opposite wheel restores camera and zoom")
	var camera_before: Vector2=map.camera
	await mouse(screen_point,MOUSE_BUTTON_MIDDLE,true)
	var offset:=Vector2(30,20)
	await motion(screen_point+offset,offset)
	check(map.camera.distance_to(camera_before-offset/map.zoom)<.02,"Middle drag follows pointer in viewport coordinates")
	await mouse(screen_point+offset,MOUSE_BUTTON_MIDDLE,false)
	var released: Vector2=map.camera
	await motion(screen_point+offset*2,offset)
	check(map.camera.is_equal_approx(released) and not map.dragging,"Releasing middle button stops panning")
	map.set_process(false)
	var target:=Vector2.INF
	for i in 16:
		var point: Vector2=map.player+Vector2.from_angle(TAU*i/16)*160*map.reference_unit_scale
		if map._segment_clear(map.player,point): target=point; break
	check(target!=Vector2.INF,"Actual walkable target located")
	if target!=Vector2.INF:
		var start: Vector2=map.player
		check(map.request_move(target) and map.route.size()==1 and map.route[-1].distance_to(target)<.001,"Open ground takes a direct route to exact click, without hex-centre snap")
		map._advance_travel(1.0/60)
		check(map.camera.distance_to(map.player)<.001 and map.player!=start,"Camera follows on first moving frame")
		var first: Vector2=map.player
		map._advance_travel(1.0/60)
		check(map.camera.distance_to(map.player)<.001 and map.player!=first,"Camera also follows the next frame without 100ms stepping")
		var second_target: Vector2=target+(target-start).normalized()*30
		check(map.request_move(second_target) and map.route.size()==1 and (map.route[0]-map.player).dot(second_target-map.player)>0,"Retargeting does not walk back to nearest cell centre")
		var preserved: PackedVector2Array=map.route.duplicate()
		check(not map.request_move(map.model.bounds.position-Vector2.ONE) and map.route==preserved,"Blocked clicks do not silently snap to a different reachable cell")
		for frame in 240:
			if map.route.is_empty(): break
			map._advance_travel(1.0/60)
		check(map.route.is_empty() and map.player.distance_to(second_target)<.01,"Movement finishes at the actual requested point")
	if not map.model.roads.is_empty():
		var road: Dictionary=map.model.roads[0]
		check(is_equal_approx(map._road_speed(map.Hex.v(road.points[0])),1.5),"Authored roads preserve original integrated 1.5x travel speed")
	var hut: Dictionary={}
	for site: Dictionary in map.doc.sites:
		if site.id=="layout_summoning_hut": hut=site; break
	var art_hit:=false
	for x in range(-180,181,30):
		for y in range(-240,-49,30):
			var point: Vector2=map.Hex.v(hut.position)+Vector2(x,y)
			if map.pick(point).get("id")==hut.id: art_hit=true; break
		if art_hit: break
	check(art_hit,"Click target includes visible building artwork beyond the old 48-unit dot")
	map.route.clear(); map.set_process(true)
	app.ui._settings(); await frames()
	check(not map.input_enabled,"Modal input gate is retained after control restoration")
	app.ui._close_all(); await frames()
	check(map.input_enabled,"Closing modal restores controls")
	app.queue_free(); await process_frame
	print("HEX_MAP_CONTROLS_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
