extends Control
## The existing WorldView rectangle hosts native scenes; paper UI stays in its scene.
const Catalog = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const Runtime = preload("res://Modules/FrontierDelivery/Scripts/Map/WorldMapRuntime.gd")
signal interaction_requested(id: String, kind: String)
signal progress_changed
signal distance_travelled(distance: float)
signal feedback(message: String)
signal location_hovered(id: String, point: Vector2)
var runtime = Runtime.new()
var world_scene: Node2D
var world_container: SubViewportContainer
var world_viewport: SubViewport
var world_canvas: Control
var battle_scene: Node3D
var battle_container: SubViewportContainer
var battle_viewport: SubViewport
var fog_rect: ColorRect
var fog_material: ShaderMaterial
var fog_image: Image
var fog_texture: ImageTexture
var hud: Node2D
var known_markers: Node2D
var camera := Vector2.ZERO
var zoom := 0.65
var mode := "world"
var current_battle := ""
var path := PackedVector2Array()
var pending_interaction := ""
var dragging := false
var last_fog_position := Vector2.INF
var nav := AStarGrid2D.new()
var navigation_revision := -1
var navigation_opening_locked := false
var navigation_embedded: Array = []
var input_enabled := true
var hovered_id := ""
var draw_fog := true
var unit_factory := Callable()
var battle_preview_enabled := true
var deployment_signature := ""
var _remembered_nodes: Dictionary = {}
var _object_refresh_elapsed := 0.0
var _fog_origin:=Vector2.ZERO
var _fog_step:=Vector2.ONE
var _hex_fog: RefCounted

func _notification(what: int) -> void:
	if what==NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(hud): hud.queue_redraw()

func _ready() -> void:
	clip_contents=true
	mouse_filter=Control.MOUSE_FILTER_STOP
	# Isolate authored negative/positive Z layers from the surrounding modal canvas.
	world_container=SubViewportContainer.new()
	world_container.stretch=true
	world_container.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(world_container)
	world_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world_viewport=SubViewport.new()
	world_viewport.disable_3d=true
	world_viewport.world_2d=World2D.new()
	world_viewport.transparent_bg=true
	world_container.add_child(world_viewport)
	world_canvas=Control.new()
	world_viewport.add_child(world_canvas)
	var packed: PackedScene=load(Catalog.index().maps.frontier_layout.scene)
	world_scene=packed.instantiate()
	world_canvas.add_child(world_scene)
	_create_fog()
	known_markers=Node2D.new()
	known_markers.z_index=1001
	world_canvas.add_child(known_markers)
	hud=Node2D.new()
	hud.z_index=1002
	world_canvas.add_child(hud)
	hud.draw.connect(_draw_hud)
	if battle_preview_enabled:
		battle_container=SubViewportContainer.new()
		battle_container.stretch=true
		battle_container.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(battle_container)
		battle_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		battle_viewport=SubViewport.new()
		battle_viewport.own_world_3d=true
		battle_viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
		battle_container.add_child(battle_viewport)
	resized.connect(_layout)
	mouse_exited.connect(func():hovered_id="";location_hovered.emit("",Vector2.ZERO);hud.queue_redraw())
	reset_runtime(runtime)
	present("world","",[])

func reset_runtime(value) -> void:
	runtime=value
	camera=runtime.player()
	path.clear()
	pending_interaction=""
	navigation_revision=-1
	last_fog_position=Vector2.INF
	if is_instance_valid(fog_rect):
		_rebuild_fog()
		_refresh_objects()
		_layout()

func present(new_mode: String,id: String,units: Array) -> bool:
	mode=new_mode
	if not is_instance_valid(world_scene):return true
	world_scene.visible=mode=="world"
	world_container.visible=mode=="world"
	fog_rect.visible=mode=="world" and draw_fog and Catalog.world().fog.enabled
	known_markers.visible=mode=="world"
	hud.visible=mode=="world"
	if is_instance_valid(battle_container): battle_container.visible=mode=="battle"
	if mode=="battle" and not battle_preview_enabled:return false
	if mode=="battle":
		var object:=Catalog.location(id)
		var battle_id:=str(runtime.data.active_battle.get("battle_map_id",object.get("battle_map_id","")))
		if not Catalog.index().maps.has(battle_id):return false
		if current_battle!=battle_id:
			if is_instance_valid(battle_scene):
				battle_viewport.remove_child(battle_scene)
				battle_scene.queue_free()
			var packed: PackedScene=load(Catalog.index().maps[battle_id].scene_3d)
			if packed==null:return false
			battle_scene=packed.instantiate()
			battle_viewport.add_child(battle_scene)
			current_battle=battle_id
			deployment_signature=""
		var signature:=str(runtime.data.active_battle.get("request_id",battle_id))+str(units.map(func(unit):return unit.id))
		if signature!=deployment_signature:
			battle_scene.deploy(units,str(runtime.data.active_battle.get("deployment_id","")),unit_factory)
			deployment_signature=signature
	_layout()
	return true

func _layout() -> void:
	if not is_instance_valid(world_scene):return
	world_canvas.size=size
	world_scene.scale=Vector2.ONE*zoom
	world_scene.position=size/2.0-camera*zoom
	if Catalog.is_hex(): world_scene.update_view(Rect2(camera-size/(2.0*zoom),size/zoom),zoom)
	known_markers.transform=world_scene.transform
	if fog_material:
		fog_material.set_shader_parameter("view_size",size)
		fog_material.set_shader_parameter("camera",camera)
		fog_material.set_shader_parameter("zoom",zoom)
	hud.queue_redraw()

func fit_map() -> void:
	var map:=Catalog.world()
	var bounds_size:=Catalog.v(map.bounds.size)
	zoom=minf(size.x/bounds_size.x,size.y/bounds_size.y)*.96
	camera=Catalog.v(map.bounds.position)+bounds_size/2.0
	_layout()

func world_to_screen(point: Vector2) -> Vector2:
	return (point-camera)*zoom+size/2.0

func screen_to_world(point: Vector2) -> Vector2:
	return (point-size/2.0)/zoom+camera

func _gui_input(event: InputEvent) -> void:
	if not input_enabled or runtime.busy or mode!="world":return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE:
			dragging=event.pressed
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var before:=screen_to_world(event.position)
			zoom=clampf(zoom*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.15),.025 if Catalog.is_hex() else .10,2.5)
			camera+=before-screen_to_world(event.position)
			_layout()
			accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			var point:=screen_to_world(event.position)
			var object:=pick(point)
			if not object.is_empty():
				if runtime.visibility(Catalog.v(object.position))!="visible":
					feedback.emit("已知地点需要探索到当前视野内才能交互。")
				elif object.type=="destructible":request_obstacle(object.id)
				else:request_location(object.id)
			else:request_move(point)
			accept_event()
	elif event is InputEventMouseMotion:
		if dragging:
			location_hovered.emit("",Vector2.ZERO)
			camera-=event.relative/zoom
			_layout()
		else:
			var object:=pick(screen_to_world(event.position))
			hovered_id=str(object.get("id",""))
			location_hovered.emit(hovered_id,world_to_screen(Catalog.v(object.position)) if not object.is_empty() else Vector2.ZERO)
			hud.queue_redraw()

func pick(point: Vector2) -> Dictionary:
	var objects: Array=Catalog.objects_in_role("interactive").duplicate()
	objects.sort_custom(func(a,b):return a.visual.z_index>b.visual.z_index)
	for object in objects:
		if object.type not in ["camp","house","town","destructible"] or not runtime.object_visible(object):continue
		var shape: Dictionary=object.get("click_area",object.get("collision",{}))
		if not shape.is_empty() and Catalog.shape_contains(shape,Catalog.local_point(object,point)):return object
	return {}

func request_location(id: String) -> bool:
	var object:=Catalog.location(id)
	var error:String=runtime.interaction_error(object,false)
	if not error.is_empty():feedback.emit(error);return false
	var target:=Catalog.world_point(object,Catalog.v(object.get("interaction_offset",[0,0])))
	if runtime.player().distance_to(target)<=float(object.get("interaction_radius",42))+5:
		interaction_requested.emit(id,"clear" if object.type=="camp" else "location")
		return true
	if not request_move(target,id):return false
	return true

func request_obstacle(id: String) -> bool:
	var object:=Catalog.location(id)
	var error:String=runtime.interaction_error(object,false)
	if not error.is_empty():feedback.emit(error);return false
	if runtime.hex!=null:
		runtime.hex.sync(runtime.data,runtime.party_count)
		if runtime.hex.axial(runtime.player()) in runtime.hex.obstacle_neighbors(object):
			interaction_requested.emit(id,"obstacle")
			return true
		path=runtime.hex.obstacle_route(runtime.player(),object)
		pending_interaction=id
		if path.is_empty(): feedback.emit("无法抵达石障相邻的可通行格。"); return false
		return true
	if not object.get("requires_near_interaction",false) or runtime.interaction_error(object).is_empty():
		interaction_requested.emit(id,"obstacle")
		return true
	var center:=Catalog.v(object.position)
	var direction:Vector2=(runtime.player()-center).normalized()
	var radius:=float(object.get("interaction_radius",76))*.88
	# Approach the near side of the solid stone; its centre is never walkable.
	for angle in [0.0,.3,-.3,.6,-.6,1.0,-1.0]:
		var target:=center+direction.rotated(angle)*radius
		if runtime.blocked(target):continue
		if request_move(target,id):return true
	feedback.emit("暂时无法靠近这块石头。")
	return false

func _rebuild_navigation() -> void:
	var opening_locked:bool=runtime.opening_locked()
	var embedded:Array=[]
	var player_radius:=float(Catalog.world().get("player_radius",6))
	for collider in Catalog.colliders_at(runtime.player()):
		if collider.id not in runtime.data.destroyed and Catalog.collider_contains(collider,runtime.player(),player_radius):embedded.append(str(collider.id)+"/"+str(collider.get("member_id","")))
	if navigation_revision==runtime.data.destroyed.size() and navigation_opening_locked==opening_locked and navigation_embedded==embedded:return
	var map:=Catalog.world()
	var origin:=Catalog.v(map.bounds.position)
	var dimensions:=Catalog.v(map.bounds.size)
	if opening_locked:
		var identity={"position":[0,0],"rotation":0,"scale":[1,1]}
		var opening:=Catalog.shape_world_bounds(identity,map.opening_area.region)
		var bounds:=Rect2(origin,dimensions).intersection(opening)
		origin=bounds.position
		dimensions=bounds.size
	nav.clear()
	nav.region=Rect2i(Vector2i.ZERO,Vector2i(ceil(dimensions.x/18.0),ceil(dimensions.y/18.0)))
	nav.cell_size=Vector2.ONE*18
	nav.offset=origin+Vector2.ONE*9
	nav.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	# Empty map cells need no collision query. Inspect only the outer border and
	# grid cells touched by the authored collider bounds, preserving the same gate.
	for x in nav.region.size.x:
		for y in [0,nav.region.size.y-1]:_mark_navigation_cell(Vector2i(x,y))
	for y in nav.region.size.y:
		for x in [0,nav.region.size.x-1]:_mark_navigation_cell(Vector2i(x,y))
	if opening_locked:
		for x in nav.region.size.x:
			for y in nav.region.size.y:_mark_navigation_cell(Vector2i(x,y))
	for object in Catalog.colliders():
		if object.id in runtime.data.destroyed:continue
		if str(object.id)+"/"+str(object.get("member_id","")) in embedded:continue
		var rect:=Catalog.shape_world_bounds(object,object.collision).grow(float(map.get("player_radius",6))+8.0)
		var begin:=Vector2i(((rect.position-nav.offset)/nav.cell_size).floor()).max(Vector2i.ZERO)
		var end:=Vector2i(((rect.end-nav.offset)/nav.cell_size).ceil()).min(nav.region.size-Vector2i.ONE)
		for x in range(begin.x,end.x+1):
			for y in range(begin.y,end.y+1):
				var cell:=Vector2i(x,y)
				if nav.is_point_solid(cell):continue
				var point:=nav.offset+Vector2(cell)*nav.cell_size
				var radius:=float(map.get("player_radius",6))
				# Union each cached collider directly; avoid querying its neighbours again.
				if Catalog.collider_contains(object,point,radius) or Catalog.collider_contains(object,point+Vector2(5,5),radius) or Catalog.collider_contains(object,point-Vector2(5,5),radius):nav.set_point_solid(cell,true)
	navigation_revision=runtime.data.destroyed.size()
	navigation_opening_locked=opening_locked
	navigation_embedded=embedded

func _mark_navigation_cell(cell: Vector2i) -> void:
	var point:=nav.offset+Vector2(cell)*nav.cell_size
	nav.set_point_solid(cell,runtime.blocked(point) or runtime.blocked(point+Vector2(5,5)) or runtime.blocked(point-Vector2(5,5)))

func request_move(point: Vector2,interaction_id := "") -> bool:
	pending_interaction=interaction_id
	if runtime.hex!=null:
		if runtime.busy or not input_enabled: return false
		if interaction_id.is_empty() and runtime.blocked(point): feedback.emit("该位置无法抵达。"); return false
		runtime.hex.sync(runtime.data,runtime.party_count)
		path=runtime.hex.route(runtime.player(),point,not interaction_id.is_empty())
		if path.is_empty(): feedback.emit("没有可通行的六边形路线：请检查河流、山体或石障。"); return false
		return true
	if runtime.opening_locked() and not runtime._inside_opening(point):
		feedback.emit("需要先在召唤小屋获得妖兽，才能离开开局区域。")
		return false
	if runtime.busy or not input_enabled or runtime.blocked(point):
		feedback.emit("该位置无法抵达。")
		return false
	_rebuild_navigation()
	var a:=Vector2i((runtime.player()-nav.offset)/18)
	var b:=Vector2i((point-nav.offset)/18)
	if not nav.is_in_boundsv(a) or not nav.is_in_boundsv(b) or nav.is_point_solid(b):return false
	# The old saved position may be inside a newly added trunk or stone.
	var start_solid:=nav.is_point_solid(a)
	if start_solid:nav.set_point_solid(a,false)
	path=nav.get_point_path(a,b)
	if start_solid:nav.set_point_solid(a,true)
	if path.is_empty():feedback.emit("没有可通行的路线。");return false
	path.append(point)
	return true

func stop_moving() -> void:
	path.clear()
	pending_interaction=""

func _process(delta: float) -> void:
	if mode!="world" or not input_enabled or runtime.busy or path.is_empty() or not is_visible_in_tree():return
	var from: Vector2=runtime.player()
	var to:=from.move_toward(path[0],float(Catalog.world().get("travel_animation_speed",180.0))*Catalog.road_speed(from)*minf(delta,.05))
	var encounter: Dictionary=runtime.move_to(to)
	var distance := from.distance_to(runtime.player())
	if distance > 0.0: distance_travelled.emit(distance)
	if runtime.player().is_equal_approx(from) and not from.is_equal_approx(to):
		stop_moving()
		progress_changed.emit()
		feedback.emit("前方有障碍，已停止移动。")
	if not path.is_empty() and runtime.player().distance_to(path[0])<.5:path.remove_at(0)
	camera=runtime.player()
	_stamp_fog()
	_object_refresh_elapsed+=delta
	if _object_refresh_elapsed>=.1:
		_refresh_objects()
		_object_refresh_elapsed=0.0
	_layout()
	if not encounter.is_empty():
		stop_moving()
		progress_changed.emit()
		interaction_requested.emit(encounter.location_id,encounter.kind)
	elif path.is_empty():
		progress_changed.emit()
		if not pending_interaction.is_empty():
			var id:=pending_interaction
			pending_interaction=""
			var object:=Catalog.location(id)
			interaction_requested.emit(id,"obstacle" if object.type=="destructible" else ("clear" if object.type=="camp" else "location"))

func _create_fog() -> void:
	if Catalog.is_hex():
		_hex_fog=preload("res://Scripts/Application/HexWorldFog.gd").new()
		_hex_fog.create(self)
		return
	fog_rect=ColorRect.new()
	fog_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	fog_rect.z_index=1000
	world_canvas.add_child(fog_rect)
	fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader:=Shader.new()
	shader.code="""shader_type canvas_item;
uniform sampler2D explored_mask : filter_linear;
uniform vec2 map_origin; uniform vec2 map_size;
uniform vec2 player; uniform vec2 camera; uniform vec2 view_size;
uniform float zoom=1.0; uniform float radius=210.0;
uniform vec4 unknown_color : source_color=vec4(.208,.282,.251,1.0);
uniform vec4 explored_color : source_color=vec4(.094,.169,.149,.76);
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment(){
 vec2 world=(UV*view_size-view_size*.5)/zoom+camera;
 vec2 uv=(world-map_origin)/map_size;
 float explored=texture(explored_mask,clamp(uv,vec2(0.0),vec2(1.0))).r;
 if(any(lessThan(uv,vec2(0.0)))||any(greaterThan(uv,vec2(1.0))))explored=0.0;
 float visible=1.0-smoothstep(radius-12.0,radius,distance(world,player));
 vec2 p=world/120.0+vec2(TIME*.012,0.0);vec2 f=fract(p);f=f*f*(3.0-2.0*f);
 float noise=mix(mix(hash(floor(p)),hash(floor(p)+vec2(1,0)),f.x),mix(hash(floor(p)+vec2(0,1)),hash(floor(p)+vec2(1,1)),f.x),f.y);
 vec4 unknown=vec4(unknown_color.rgb*(.88+.24*noise),1.0);
 COLOR=mix(unknown,explored_color,explored);COLOR.a*=1.0-visible;
}"""
	fog_material=ShaderMaterial.new()
	fog_material.shader=shader
	fog_rect.material=fog_material
	fog_material.set_shader_parameter("map_origin",Catalog.v(Catalog.world().bounds.position))
	fog_material.set_shader_parameter("map_size",Catalog.v(Catalog.world().bounds.size))
	fog_material.set_shader_parameter("radius",float(Catalog.world().fog.radius))
	fog_material.set_shader_parameter("unknown_color",Color(Catalog.world().fog.unknown_color))
	var explored_color:=Color(Catalog.world().fog.explored_color)
	explored_color.a=float(Catalog.world().fog.explored_opacity)
	fog_material.set_shader_parameter("explored_color",explored_color)

func _rebuild_fog() -> void:
	if _hex_fog!=null: _hex_fog.rebuild(); return
	fog_image=Image.create(256,154,false,Image.FORMAT_R8)
	_fog_origin=Catalog.v(Catalog.world().bounds.position)
	_fog_step=Catalog.v(Catalog.world().bounds.size)/Vector2(fog_image.get_size())
	var fog:Dictionary=Catalog.world().fog
	fog_image.fill(Color.WHITE if not fog.enabled or fog.default_state=="explored" else Color.BLACK)
	if fog.enabled:
		for object in Catalog.objects_in_role("reveals"):
			var rect:=_fog_pixels(Catalog.shape_world_bounds(object,object.region))
			for x in range(rect.position.x,rect.end.x):
				for y in range(rect.position.y,rect.end.y):
					if Catalog.shape_contains(object.region,Catalog.local_point(object,_fog_world_point(x,y))):fog_image.set_pixel(x,y,Color.WHITE)
		for stroke in fog.paint:
			_paint_fog_segment(Catalog.v(stroke.points[0]),Catalog.v(stroke.points[0]),float(stroke.radius),stroke.state)
			for i in range(1,stroke.points.size()):_paint_fog_segment(Catalog.v(stroke.points[i-1]),Catalog.v(stroke.points[i]),float(stroke.radius),stroke.state)
		for segment in runtime.data.samples:
			_paint_fog_segment(Vector2(segment[0],segment[1]),Vector2(segment[2],segment[3]),float(fog.radius),"explored")
	fog_texture=ImageTexture.create_from_image(fog_image)
	fog_material.set_shader_parameter("explored_mask",fog_texture)
	_stamp_fog()

func _fog_world_point(x: int,y: int) -> Vector2:
	return _fog_origin+Vector2(x+.5,y+.5)*_fog_step

func _fog_pixels(rect: Rect2) -> Rect2i:
	var origin:=Catalog.v(Catalog.world().bounds.position)
	var dimensions:=Catalog.v(Catalog.world().bounds.size)
	var image_size:=Vector2(fog_image.get_size())
	var begin:=Vector2i(((rect.position-origin)/dimensions*image_size).floor()).max(Vector2i.ZERO)
	var end:=Vector2i(((rect.end-origin)/dimensions*image_size).ceil()).min(fog_image.get_size()-Vector2i.ONE)
	if end.x<begin.x or end.y<begin.y:return Rect2i()
	return Rect2i(begin,end-begin+Vector2i.ONE)

func _paint_fog_segment(from: Vector2,to: Vector2,radius: float,state: String) -> void:
	var world_rect:=Rect2(from,Vector2.ZERO).expand(to).grow(radius)
	var rect:=_fog_pixels(world_rect)
	for x in range(rect.position.x,rect.end.x):
		for y in range(rect.position.y,rect.end.y):
			var point:=_fog_world_point(x,y)
			if Catalog.distance_to_segment(point,from,to)>radius:continue
			var explored:=state=="explored"
			if state=="reset":
				explored=Catalog.world().fog.default_state=="explored"
				for object in Catalog.objects_in_role("reveals"):
					if Catalog.shape_contains(object.region,Catalog.local_point(object,point)):explored=true
			fog_image.set_pixel(x,y,Color.WHITE if explored else Color.BLACK)

func _stamp_fog() -> void:
	if _hex_fog!=null: _hex_fog.update(); return
	fog_material.set_shader_parameter("player",runtime.player())
	if runtime.player().distance_to(last_fog_position)<12:return
	last_fog_position=runtime.player()
	var origin:=Catalog.v(Catalog.world().bounds.position)
	var dimensions:=Catalog.v(Catalog.world().bounds.size)
	var radius:=float(Catalog.world().fog.radius)
	var center:Vector2=(runtime.player()-origin)/dimensions*Vector2(fog_image.get_size())
	var r:Vector2=Vector2.ONE*radius/dimensions*Vector2(fog_image.get_size())
	for x in range(maxi(0,int(center.x-r.x)),mini(fog_image.get_width(),int(center.x+r.x)+1)):
		for y in range(maxi(0,int(center.y-r.y)),mini(fog_image.get_height(),int(center.y+r.y)+1)):
			var point:=origin+Vector2(x+.5,y+.5)/Vector2(fog_image.get_size())*dimensions
			if point.distance_to(runtime.player())<=radius:fog_image.set_pixel(x,y,Color.WHITE)
	fog_texture.update(fog_image)

func _refresh_objects() -> void:
	if Catalog.is_hex():
		world_scene.refresh(runtime)
		for remembered: Node2D in _remembered_nodes.values(): remembered.visible=false
		for object: Dictionary in Catalog.objects_in_role("interactive"):
			if not runtime.known(object) or runtime.visibility(Catalog.v(object.position))=="visible": continue
			if not _remembered_nodes.has(object.id):
				var copy := world_scene.get_node("Objects/"+str(object.id)).duplicate() as Node2D
				copy.z_index=0
				copy.modulate=Color(0.65,0.65,0.65,0.8)
				known_markers.add_child(copy)
				_remembered_nodes[object.id]=copy
			_remembered_nodes[object.id].visible=true
		return
	for child in _remembered_nodes.values():child.visible=false
	for object in Catalog.world().objects:
		var node: Node2D=world_scene.get_node("Objects/"+object.id)
		if object.has("discovery"):node.visible=runtime.object_visible(object)
		if object.has("reference_landmark_id"):
			var owner:=Catalog.location(object.reference_landmark_id)
			node.visible=runtime.object_visible(owner)
			var asset:Dictionary=Catalog.index().assets.get(object.visual.asset,{})
			if asset.has("svg_text") and runtime.known(owner) and runtime.visibility(Catalog.v(owner.position))!="visible":
				if not _remembered_nodes.has(object.id):
					var copy:=node.duplicate() as Node2D
					copy.z_index=0
					copy.modulate=Color(.65,.65,.65,.85)
					known_markers.add_child(copy)
					_remembered_nodes[object.id]=copy
				_remembered_nodes[object.id].visible=true
		if object.type=="destructible":
			var destroyed: bool=object.id in runtime.data.destroyed
			var body:=node.get_node_or_null("Body") as StaticBody2D
			if body:body.collision_layer=0 if destroyed else int(object.collision.get("layer",1))
			var sprite:=node.get_node_or_null("Visual") as Sprite2D
			if sprite and destroyed:
				var art:=Catalog.object_art(object,true)
				sprite.texture=load(art.get("render_path",art.path))
				var ratio:=Catalog.v(object.visual.size)/Vector2(art.width,art.height)
				if art.get("demo_art",false):ratio=Vector2.ONE*minf(ratio.x,ratio.y)
				sprite.scale=ratio
		if runtime.known(object) and runtime.visibility(Catalog.v(object.position))!="visible":
			var sprite:=node.get_node_or_null("Visual") as Sprite2D
			if sprite:
				if not _remembered_nodes.has(object.id):
					var copy:=Sprite2D.new()
					copy.texture=sprite.texture
					copy.transform=node.transform*sprite.transform
					copy.modulate=Color(.65,.65,.65,.8)
					known_markers.add_child(copy)
					_remembered_nodes[object.id]=copy
				_remembered_nodes[object.id].visible=true

func _draw_hud() -> void:
	var point:=world_to_screen(runtime.player())
	hud.draw_circle(point,8,Color("e3cf91"))
	hud.draw_arc(point,10,0,TAU,24,Color("344d3e"),2,true)
	if path.size()>1:
		var line:=PackedVector2Array([point])
		for p in path:line.append(world_to_screen(p))
		hud.draw_polyline(line,Color(.9,.84,.6,.65),2,true)
	var font:=get_theme_default_font()
	for object in Catalog.objects_in_role("interactive"):
		if not runtime.object_visible(object):continue
		if Catalog.is_hex() and zoom<0.10 and object.id!=hovered_id: continue
		if object.get("name_label",{}).get("style","")=="paper":continue
		if object.get("hide_name_label",false):
			if object.id!=hovered_id:continue
		var label:=preload("res://Scripts/Localization/GameText.gd").text(str(object.name))
		var p:=world_to_screen(Catalog.v(object.position))+Vector2(0,20)
		if p.x<0 or p.x>size.x or p.y<0 or p.y>size.y:continue
		var width:=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
		var label_rect := Rect2(p-Vector2(width/2+4,18),Vector2(width+8,24))
		if Catalog.is_hex():
			hud.draw_rect(label_rect,Color("ead9b6"))
			hud.draw_rect(label_rect,Color("5a4a35"),false,1)
		else: hud.draw_style_box(get_theme_stylebox("panel","Panel"),label_rect)
		hud.draw_string(font,p-Vector2(width/2,0),label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("392e24"))
	hud.draw_rect(Rect2(Vector2(2,2),size-Vector2(4,4)),Color("a67b45"),false,3)
