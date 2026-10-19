extends "res://Modules/HexFrontier/CurrentMapPreview.gd"
const PROGRESS=preload("res://Scripts/Events/HexMapProgress.gd")
var application: Node
var progress: Dictionary
var input_enabled:=true
var pending_site: Dictionary={}
var auto_latched: Array=[]
var save_elapsed:=0.0
var moved_since_save:=false
const LEGACY_CATALOG=preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
var reference_unit_scale:=1.0
var _sight_elapsed:=0.0
var _hit_masks: Dictionary={}
var _interactive_sites: Array=[]
var active_location_id:="layout_summoning_hut"
signal site_arrived(site: Dictionary)

func _build_ui() -> void:
	# Retain ownership of inherited helpers without exposing the authoring toolbar.
	add_child(ui); ui.add_child(status); ui.hide()
func _unhandled_key_input(_event: InputEvent) -> void: pass

func _build_navigation() -> void:
	nav.clear(); nav_ids.clear()
	var removed: Array=progress.get("destroyed",application.session.data.get("hex_map",{}).get("destroyed",[]))
	for cell in model.cells:
		var p: Vector2=model.center(cell)
		if model.blocked(p,removed): continue
		var id:=nav.get_point_count(); nav_ids[cell]=id; nav.add_point(id,p)
	for cell in nav_ids:
		for direction in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,1)]:
			if nav_ids.has(cell+direction) and not model.crosses_art(model.center(cell),model.center(cell+direction)): nav.connect_points(nav_ids[cell],nav_ids[cell+direction])

func _ready() -> void:
	super._ready()
	progress=application.session.data.get("hex_map",PROGRESS.initial()).duplicate(true)
	if not PROGRESS.valid(progress): push_error("新地图进度无效。"); return
	# Match the original integrated map's screen scale and travel speed while
	# retaining the new map's authored world coordinates and sight radius.
	reference_unit_scale=float(doc.vision_radius)/float(LEGACY_CATALOG.world().fog.radius)
	zoom=.65/reference_unit_scale
	_interactive_sites=doc.sites.filter(func(site):return site.kind in ["camp","event","town","house","destructible"])
	_interactive_sites.sort_custom(func(a,b):return float(a.get("visual",{}).get("z_index",0))>float(b.get("visual",{}).get("z_index",0)))
	player=Hex.v(progress.player); camera=player
	_apply_destroyed(); _build_navigation()
	if not progress.explored_png.is_empty():
		var image:=Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(progress.explored_png))==OK and image.get_size()==explored.get_size():
			image.convert(Image.FORMAT_R8); explored=image; explored_texture.update(explored)
	last_sight=Vector2.INF; last_stamp=Vector2.INF
	_update_sight(); refresh_view()
	var rain:=preload("res://Scripts/Events/BloodRainView.gd").new()
	rain.map=self; rain.z_index=1005; add_child(rain)
	for id: String in progress.destroyed:
		if sprites.has(id): sprites[id].hide()

func world_to_screen(point: Vector2) -> Vector2:
	return (point-camera)*zoom+size*.5

func screen_to_world(point: Vector2) -> Vector2:
	return (point-size*.5)/zoom+camera

func _gui_input(event: InputEvent) -> void:
	if not input_enabled: return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE:
			dragging=event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var before:=screen_to_world(event.position)
			zoom=clampf(zoom*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.15),.10/reference_unit_scale,2.5/reference_unit_scale)
			camera+=before-screen_to_world(event.position)
			refresh_view()
		elif event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			var point:=screen_to_world(event.position)
			var picked:=pick(point)
			if not picked.is_empty():
				if not model.visible(player,Hex.v(picked.position)):
					application.ui._notice("已知地点需要探索到当前视野内才能交互。")
				elif picked.kind=="destructible": request_obstacle(picked.id)
				else: request_location(picked.id)
			else:
				var cell: Dictionary=model.cell_at(point)
				if cell.get("control")=="breakable" or cell.get("feature")=="breakable":
					var owner_found:=false
					for owner: String in cell.get("obstacle_ids",[]):
						if owner in progress.destroyed: continue
						request_obstacle(owner); owner_found=true; break
					if not owner_found: _break_passage(model.axial(point),cell.get("control")=="breakable")
				else: request_move(point)
	elif event is InputEventMouseMotion:
		if dragging:
			camera-=event.relative/zoom
			refresh_view()
		else:
			var picked:=pick(screen_to_world(event.position))
			tooltip_text=str(picked.get("name",""))
	accept_event()

func pick(point: Vector2) -> Dictionary:
	for site: Dictionary in _interactive_sites:
		if site.id in progress.destroyed: continue
		var position:=Hex.v(site.position)
		if not model.visible(player,position) and site.kind!="town" and site.id!="layout_summoning_hut": continue
		var visual: Dictionary=site.get("visual",{})
		if visual.is_empty():
			if point.distance_to(position)<=48: return site
		elif _hits_visual(point,position,visual): return site
		for layer: Dictionary in visual.get("layers",[]):
			if _hits_visual(point,position,layer): return site
	return {}

func _hits_visual(point: Vector2, at: Vector2, visual: Dictionary) -> bool:
	var asset: Dictionary=assets.get(visual.get("asset_id",""),{})
	if asset.is_empty(): return false
	var width: float=visual.get("width",255)
	var dimensions:=Vector2(width,width*float(asset.height)/float(asset.width)*float(visual.get("height_scale",1)))
	var center:=at+(Vector2(.5,.5)-Hex.v(visual.get("anchor",asset.get("anchor",[.5,1]))))*dimensions+Hex.v(visual.get("offset",[0,0]))
	var pixel: Vector2=((point-center).rotated(-deg_to_rad(float(visual.get("rotation",0))))+dimensions*.5)/dimensions
	if not Rect2(Vector2.ZERO,Vector2.ONE).has_point(pixel): return false
	if not _hit_masks.has(asset.id):
		var artwork: Texture2D=texture(asset.path)
		if artwork==null: return false
		var bitmap:=BitMap.new(); bitmap.create_from_image_alpha(artwork.get_image(),.1)
		_hit_masks[asset.id]=bitmap
	var mask: BitMap=_hit_masks[asset.id]
	return mask.get_bitv(Vector2i(pixel*Vector2(mask.get_size())))

func _break_passage(key: Vector2i, control: bool) -> void:
	if player.distance_to(model.center(key))>float(doc.get("vision_radius",600)) or not model.visible(player,model.center(key)): application.ui._notice("需要先靠近通路。"); return
	var allowed: Array=[]
	for id: String in application.session.data.get("story_events",{}).get("entries",{}):
		if application.session.story_event_view(id).get("completed",false): allowed.append(id)
	var result: Dictionary=model.break_control(key,not application.session.monsters().is_empty(),allowed) if control else model.break_cell(key,not application.session.monsters().is_empty(),allowed)
	if not result.ok: application.ui._notice(result.reason); return
	application.ui._modal("清理通路",func(body):
		var screen: Control=application.ui._text_screen(body,"命令持有的怪物清理这段通路？")
		application.ui._btn(screen.get_node("%Commands"),"清理",func():
			progress.destroyed.append(result.id)
			if save_progress(): _build_navigation(); route.clear(); application.ui._close_all(); refresh_view())
		application.ui._btn(screen.get_node("%Commands"),"取消",func():application.ui._close_modal()))

func _interaction_distance(site: Dictionary) -> float:
	return (float(site.get("interaction_radius",76 if site.kind=="destructible" else 42))+5)*reference_unit_scale

func request_location(id: String) -> bool:
	for site: Dictionary in _interactive_sites:
		if site.id!=id: continue
		if not input_enabled: return false
		var at:=Hex.v(site.position)
		var distance:=_interaction_distance(site)
		if player.distance_to(at)<=distance:
			pending_site=site; _arrive(); return true
		var targets: Array[Vector2]=[at]
		var direction: Vector2=(player-at).normalized()
		for angle: float in [0.0,.3,-.3,.6,-.6,1.0,-1.0,PI]: targets.append(at+direction.rotated(angle)*distance*.88)
		for target: Vector2 in targets:
			var planned:=_path_to(target)
			if planned.is_empty(): continue
			route=planned; pending_site=site; actor.queue_redraw(); return true
		application.ui._notice("此地点暂时没有可抵达的交互落点。")
		return false
	return false

func request_obstacle(id: String) -> bool:
	for site: Dictionary in _interactive_sites:
		if site.id!=id or site.kind!="destructible": continue
		if application.session.monsters().is_empty(): application.ui._notice("需要先持有怪物。"); return false
		if player.distance_to(Hex.v(site.position))<=_interaction_distance(site): _destroy_obstacle(site); return true
		return request_location(id)
	return false

func request_move(point: Vector2) -> bool:
	if not input_enabled: return false
	if model.blocked(point,progress.destroyed): application.ui._notice("该位置无法抵达。"); return false
	var planned:=_path_to(point)
	if planned.is_empty(): application.ui._notice("没有可通行的路线。"); return false
	route=planned; pending_site={}; actor.queue_redraw(); return true

func _segment_clear(from: Vector2, to: Vector2) -> bool:
	if model.crosses_art(from,to): return false
	var steps:=maxi(1,ceili(from.distance_to(to)/minf(18*reference_unit_scale,float(doc.grid.cell_width)*.25)))
	for index in range(1,steps+1):
		if model.blocked(from.lerp(to,float(index)/steps),progress.destroyed): return false
	return true

func _contact(point: Vector2) -> int:
	if nav.get_point_count()==0: return -1
	var closest:=nav.get_closest_point(point)
	if _segment_clear(point,nav.get_point_position(closest)): return closest
	var candidates: Array[int]=[]
	var at: Vector2i=model.axial(point)
	for q in range(-2,3):
		for r in range(-2,3):
			var key:=at+Vector2i(q,r)
			if nav_ids.has(key): candidates.append(nav_ids[key])
	candidates.sort_custom(func(a,b):return point.distance_squared_to(nav.get_point_position(a))<point.distance_squared_to(nav.get_point_position(b)))
	for candidate in candidates:
		if _segment_clear(point,nav.get_point_position(candidate)): return candidate
	return -1

func _path_to(point: Vector2) -> PackedVector2Array:
	if model.blocked(point,progress.destroyed): return PackedVector2Array()
	if _segment_clear(player,point): return PackedVector2Array([point])
	var first:=_contact(player); var last:=_contact(point)
	if first<0 or last<0: return PackedVector2Array()
	var coarse:=nav.get_point_path(first,last)
	if coarse.is_empty(): return coarse
	coarse.append(point)
	var result:=PackedVector2Array(); var at:=player; var index:=0
	while index<coarse.size():
		var selected:=-1
		for candidate in range(coarse.size()-1,index-1,-1):
			if _segment_clear(at,coarse[candidate]): selected=candidate; break
		if selected<0: return PackedVector2Array()
		at=coarse[selected]
		if result.is_empty() or not at.is_equal_approx(result[-1]): result.append(at)
		index=selected+1
	return result

func _road_speed(point: Vector2) -> float:
	var multiplier:=1.0
	for road: Dictionary in model.roads:
		for index in range(1,road.points.size()):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,Hex.v(road.points[index-1]),Hex.v(road.points[index])))<=float(road.width)*.5:
				multiplier=maxf(multiplier,float(road.get("speed_multiplier",1.5))); break
	return multiplier

func _advance_travel(delta: float) -> float:
	if route.is_empty(): return 0.0
	var traveled:=0.0
	var budget:=180.0*reference_unit_scale*_road_speed(player)*minf(delta,.05)
	while budget>0 and not route.is_empty():
		var remaining:=player.distance_to(route[0])
		var to:=player.move_toward(route[0],budget)
		if not _segment_clear(player,to): route.clear(); pending_site={}; application.ui._notice("前方有障碍，已停止移动。"); break
		traveled+=player.distance_to(to)
		player=to; budget=maxf(0,budget-remaining)
		if player.distance_to(route[0])<.5: route.remove_at(0)
	camera=player
	_sight_elapsed+=delta
	if _sight_elapsed>=1.0/30: _sight_elapsed=0; _update_sight()
	_sync_camera()
	refresh_elapsed+=delta
	if refresh_elapsed>=.1 or route.is_empty(): refresh_elapsed=0; refresh_view()
	actor.queue_redraw()
	return traveled

func _sync_camera() -> void:
	world.scale=Vector2.ONE*zoom; world.position=size*.5-camera*zoom
	remembered.transform=world.transform; mountain_faces.transform=world.transform
	fog_material.set_shader_parameter("camera",camera)
	surface_material.set_shader_parameter("camera",camera)
	for material: ShaderMaterial in face_materials.values(): material.set_shader_parameter("camera",camera)

func _draw_actor() -> void:
	super._draw_actor()
	if route.is_empty(): return
	var points:=PackedVector2Array([world_to_screen(player)])
	for at: Vector2 in route: points.append(world_to_screen(at))
	actor.draw_polyline(points,Color(.9,.84,.6,.65),2,true)

func _process(delta: float) -> void:
	if not input_enabled or progress.is_empty(): return
	for id: String in progress.get("destruction_jobs",{}).keys():
		progress.destruction_jobs[id]=maxf(0,float(progress.destruction_jobs[id])-delta)
		if progress.destruction_jobs[id]<=0:
			progress.destroyed.append(id); progress.destruction_jobs.erase(id)
			if save_progress(): _apply_destroyed(); _build_navigation(); last_sight=Vector2.INF; _update_sight(); refresh_view()
	var before:=player
	var moved:=_advance_travel(delta)
	if moved>0:
		progress.travel_distance+=moved; moved_since_save=true
		for site: Dictionary in doc.sites:
			if site.id not in progress.discovered and model.visible(player,Hex.v(site.position)): progress.discovered.append(site.id)
		if pending_site.is_empty() and application.phase=="world":
			var encounter: Dictionary=model.encounter(before,player,auto_latched)
			if not encounter.is_empty() and encounter.id not in progress.cleared:
				# Story locations have explicit prerequisites and confirmation.
				if not application.story_content.bindings_for_site(encounter.id).is_empty(): return
				pending_site=encounter; _arrive()
	if not pending_site.is_empty() and route.is_empty():
		if player.distance_to(Hex.v(pending_site.position))<=_interaction_distance(pending_site): _arrive()
	save_elapsed+=delta
	if moved_since_save and save_elapsed>=1.0: save_progress()
	var raining: bool=PROGRESS.rain_active(application.session.data)
	world.modulate=Color(1.0,.83,.83) if raining else Color.WHITE

func _arrive() -> void:
	var site:=pending_site.duplicate(true)
	pending_site={}; route.clear()
	if site.is_empty(): return
	active_location_id=site.id
	if site.id not in progress.visited: progress.visited.append(site.id)
	if site.id not in progress.discovered: progress.discovered.append(site.id)
	if not save_progress(): return
	if not application.session.record_task_arrival("hex_frontier_20261019",site.id): application.ui._notice(application.session.last_error); return
	if site.kind=="destructible": _destroy_obstacle(site)
	else: site_arrived.emit(site)

func save_progress() -> bool:
	if progress.is_empty(): return false
	progress.player=[player.x,player.y]
	progress.explored_png=Marshalls.raw_to_base64(explored.save_png_to_buffer())
	if application.session.save_hex_world(progress):
		progress=application.session.data.hex_map.duplicate(true)
		moved_since_save=false; save_elapsed=0
		return true
	application.ui._notice(application.session.last_error)
	progress=application.session.data.get("hex_map",PROGRESS.initial()).duplicate(true)
	player=Hex.v(progress.player); route.clear(); pending_site={}; refresh_view()
	return false

func set_enabled(enabled: bool) -> void:
	input_enabled=enabled
	if not enabled: dragging=false

func location_name() -> String:
	for site: Dictionary in doc.sites:
		if site.id==active_location_id: return site.name
	return "草原旅途"

func _destroy_obstacle(site: Dictionary) -> void:
	if site.id in progress.destroyed: return
	if progress.get("destruction_jobs",{}).has(site.id): application.ui._notice("正在清理通路，保持在地图中等待完成。"); return
	if player.distance_to(Hex.v(site.position))>float(doc.grid.cell_width)*2: application.ui._notice("请先靠近石障，再命令怪物清理。"); return
	if application.session.monsters().is_empty(): application.ui._notice("需要先持有怪物。"); return
	application.ui._modal("清理石障",func(body):
		var seconds: float=float(site.destruction.get("walk_steps",3))*float(doc.traversal.get("hex_step_seconds",.6))
		var screen: Control=application.ui._text_screen(body,"命令怪物清理这块独立石障？耗时 %.1f 秒；暂停及离开地图时停止计时。"%seconds)
		application.ui._btn(screen.get_node("%Commands"),"开始清理",func():
			if not progress.has("destruction_jobs"): progress["destruction_jobs"]={}
			progress.destruction_jobs[site.id]=seconds; route.clear()
			if save_progress(): application.ui._close_all())
		application.ui._btn(screen.get_node("%Commands"),"取消",func():application.ui._close_modal()))

func _apply_destroyed() -> void:
	model.art_surfaces=model.art_surfaces.filter(func(surface):return surface.site_id not in progress.destroyed)
	visual_surfaces=visual_surfaces.filter(func(surface):return surface.site_id not in progress.destroyed)
	for cell: Dictionary in model.cells.values():
		var owners: Array=cell.get("obstacle_ids",[])
		if owners.is_empty() or not owners.all(func(id):return id in progress.destroyed): continue
		if cell.get("feature")=="breakable": cell.feature=""
		if cell.get("control")=="breakable": cell.control="allowed"
	for id: String in progress.destroyed:
		model.art_site_ids.erase(id); surface_sites.erase(id)
		var face:=mountain_faces.get_node_or_null(NodePath(id))
		if face!=null: face.hide()

func _refresh_sprites(viewport: Rect2) -> void:
	super._refresh_sprites(viewport)
	for id: String in progress.get("destroyed",[]):
		if sprites.has(id): sprites[id].hide()
