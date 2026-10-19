extends Control
const Hex=preload("res://Modules/HexFrontier/HexMapData.gd")
const Sight=preload("res://Modules/HexFrontier/MapSight.gd")
const Presentation=preload("res://Modules/HexFrontier/MapPresentation.gd")
const FOG_PIXEL_SCREEN_SIZE:=3.0
var doc:Dictionary
var spec:Dictionary
var model=Hex.new()
var assets:Dictionary={}
var sprites:Dictionary={}
var images:Dictionary={}
var tile_nodes:Dictionary={}
var visual_surfaces:Array=[]
var covered_cells:Dictionary={}
var world:=Node2D.new()
var backdrop:=Node2D.new()
var objects:=Node2D.new()
var remembered:=Node2D.new()
var mountain_faces:=Node2D.new()
var surface_sites:Dictionary={}
var seam_specs:Dictionary={}
var revealed_faces:Dictionary={}
var ui:=Control.new()
var fog:=TextureRect.new()
var fog_viewport:=SubViewport.new()
var fog_canvas:=ColorRect.new()
var fog_material:=ShaderMaterial.new()
var surface_material:=ShaderMaterial.new()
var face_materials:Dictionary={}
var explored:Image
var explored_texture:ImageTexture
var rays:Image
var ray_texture:ImageTexture
var player:=Vector2.ZERO
var camera:=Vector2.ZERO
var zoom:=.28
var dragging:=false
var review:=false
var status:=Label.new()
var actor:=Node2D.new()
var nav:=AStar2D.new()
var nav_ids:Dictionary={}
var route:=PackedVector2Array()
var last_stamp:=Vector2.INF
var last_sight:=Vector2.INF
var font:=SystemFont.new()
var refresh_elapsed:=0.0
var logical_surface_cache:Dictionary={}

func _ready() -> void:
	font.font_names=PackedStringArray(["Microsoft YaHei","SimHei"])
	var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://Content/Maps/HexFrontier_20261019/world_visuals.json"))
	if not parsed is Dictionary:
		push_error("缺少 scene.json，请按说明重新生成预览快照。");return
	spec=parsed
	for field in ["layout_path","asset_root"]:
		var source_path:=str(spec.get(field,""))
		if not source_path.is_absolute_path():source_path=ProjectSettings.globalize_path("res://"+source_path).simplify_path()
		spec[field]=source_path
	if int(spec.get("version",0))<2:
		push_error("山体后缘约束已更新，请重新运行启动脚本生成当前预览。");return
	if FileAccess.get_sha256(spec.layout_path)!=spec.layout_sha256:
		push_error("地图已更新，请重新运行启动脚本生成最新的视觉约束。");return
	var error:String=model.load_layout(spec.layout_path)
	if not error.is_empty():push_error(error);return
	doc=model.document
	for a in doc.assets:assets[a.id]=a
	player=Hex.v(doc.spawn);camera=player
	world.name="MapWorld";add_child(world);backdrop.name="Backdrop";backdrop.z_index=-100;world.add_child(backdrop)
	objects.name="Objects";world.add_child(objects)
	mountain_faces.name="VisibleMountainFaces";mountain_faces.z_index=1003;add_child(mountain_faces)
	remembered.name="KnownLandmarks";remembered.z_index=1004;add_child(remembered)
	var bg:=Sprite2D.new();bg.texture=texture(doc.background.asset);bg.centered=false;bg.position=Hex.v(doc.background.position);bg.scale=Hex.v(doc.background.size)/bg.texture.get_size();bg.z_index=-4;backdrop.add_child(bg)
	for surface in spec.mountain_surfaces:
		var rings:Array=[]
		for source_ring in surface.get("rings",[surface.polygon]):
			var p:=PackedVector2Array()
			for xy in source_ring:p.append(Hex.v(xy))
			rings.append(p)
		var obstacle:=Sight.occluder_rings(rings);obstacle["site_id"]=surface.id
		visual_surfaces.append(obstacle);surface_sites[surface.id]=obstacle
		if surface.has("seam_shadow"):seam_specs[surface.id]=surface.seam_shadow
		# Saved precise colliders get the same seam sealing as the visible shadow.
		for i in model.art_surfaces.size():
			if model.art_surfaces[i].site_id==surface.id:
				var logical:=obstacle.duplicate();logical["blocks_movement"]=model.art_surfaces[i].blocks_movement;logical["blocks_vision"]=model.art_surfaces[i].blocks_vision;model.art_surfaces[i]=logical
		for key in surface.cells:covered_cells[str(key)]=true
	var shader:=Shader.new();shader.code=Sight.fog_shader();fog_material.shader=shader
	var face_shader:=Shader.new();face_shader.code=Sight.surface_shader();surface_material.shader=face_shader
	for surface in spec.mountain_surfaces:
		var material:ShaderMaterial=surface_material.duplicate()
		if surface.has("rear_edge_mask"):
			var mask_spec:Dictionary=surface.rear_edge_mask;var mask_image:=Image.new()
			if mask_image.load_png_from_buffer(Marshalls.base64_to_raw(mask_spec.png))==OK:
				var b:Array=mask_spec.bounds
				material.set_shader_parameter("rear_mask",ImageTexture.create_from_image(mask_image))
				material.set_shader_parameter("rear_bounds",Vector4(b[0],b[1],b[2],b[3]))
				material.set_shader_parameter("rear_distance_scale",float(mask_spec.distance_scale))
				material.set_shader_parameter("rear_mask_enabled",true)
		face_materials[surface.id]=material
	fog_viewport.name="PixelFogBuffer";fog_viewport.disable_3d=true;fog_viewport.transparent_bg=true;fog_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(fog_viewport)
	fog_canvas.material=fog_material;fog_viewport.add_child(fog_canvas)
	fog.name="WarFog";fog.texture=fog_viewport.get_texture();fog.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;fog.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;fog.mouse_filter=Control.MOUSE_FILTER_IGNORE;fog.z_index=1000;add_child(fog)
	for material in face_materials.values():
		material.set_shader_parameter("fog_texture",fog.texture)
		material.set_shader_parameter("fog_texture_available",true)
	explored=Image.create(1280,750,false,Image.FORMAT_R8);explored.fill(Color.BLACK);explored_texture=ImageTexture.create_from_image(explored)
	rays=Image.create(Sight.RAY_COUNT,1,false,Image.FORMAT_RG8);rays.fill(Color.WHITE);ray_texture=ImageTexture.create_from_image(rays)
	var uniforms={"explored_mask":explored_texture,"sight_rays":ray_texture,"map_origin":Hex.v(doc.bounds.position),"map_size":Hex.v(doc.bounds.size),"radius":float(doc.vision_radius),"feather":clampf(float(doc.vision_radius)*.14,48,110),"cloud_scale":280.0}
	for key in uniforms:fog_material.set_shader_parameter(key,uniforms[key])
	actor.z_index=1006;add_child(actor);actor.draw.connect(_draw_actor)
	_build_ui();_build_navigation();resized.connect(refresh_view);_update_sight();refresh_view()

func texture(path:String) -> Texture2D:
	if images.has(path):return images[path]
	var resolved:=str(spec.asset_root).path_join(path)
	if ResourceLoader.exists(resolved):
		var imported:=load(resolved) as Texture2D
		if imported!=null:images[path]=imported;return imported
	var image:=Image.load_from_file(resolved)
	if not image:return null
	var result:=ImageTexture.create_from_image(image);images[path]=result;return result

func _build_ui() -> void:
	ui.z_index=1010;ui.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(ui)
	var bar:=HBoxContainer.new();bar.position=Vector2(16,14);bar.add_theme_constant_override("separation",8);ui.add_child(bar)
	for entry in [["召唤小屋","layout_summoning_hut"],["福斯特镇","layout_foster_town"],["萨尔格特城","layout_sargate_city"]]:
		var button:=Button.new();button.text=entry[0];button.add_theme_font_override("font",font);var id:String=entry[1];button.pressed.connect(func():focus_site(id));bar.add_child(button)
	var near:=Button.new();near.text="抵近当前地点";near.add_theme_font_override("font",font);near.pressed.connect(_approach_camera);bar.add_child(near)
	var all_map:=Button.new();all_map.text="全图审阅 F2";all_map.add_theme_font_override("font",font);all_map.pressed.connect(toggle_review);bar.add_child(all_map)
	status.position=Vector2(16,52);status.add_theme_font_override("font",font);status.add_theme_font_size_override("font_size",15);status.add_theme_color_override("font_color",Color("f3efd9"));status.add_theme_color_override("font_shadow_color",Color("293830"));status.add_theme_constant_override("shadow_offset_x",1);status.add_theme_constant_override("shadow_offset_y",1);ui.add_child(status)
	status.text="当前保存地图 · %d点位 / %d素材 / %d高清原块 · 左键移动，滚轮缩放，中键拖动；本预览不写游戏进度"%[doc.sites.size(),assets.size(),spec.tiles.size()]

func focus_site(id:String) -> void:
	for site in doc.sites:
		if site.id==id:camera=Hex.v(site.position);review=false;zoom=.28;refresh_view();return

func _approach_camera() -> void:
	var id:=nav.get_closest_point(camera-Vector2(300,220));player=nav.get_point_position(id);route.clear();last_sight=Vector2.INF;last_stamp=Vector2.INF;review=false;_update_sight();refresh_view()

func toggle_review() -> void:
	review=not review
	if review:camera=Hex.v(doc.bounds.position)+Hex.v(doc.bounds.size)*.5;zoom=minf(size.x/doc.bounds.size[0],size.y/doc.bounds.size[1])*.96
	else:camera=player;zoom=.28
	refresh_view()

func refresh_view() -> void:
	if doc.is_empty() or size.x<=0:return
	world.scale=Vector2.ONE*zoom;world.position=size*.5-camera*zoom;remembered.transform=world.transform;mountain_faces.transform=world.transform
	fog.size=size;fog.visible=not review
	fog_viewport.size=Vector2i((size/FOG_PIXEL_SCREEN_SIZE).ceil()).max(Vector2i.ONE);fog_canvas.size=Vector2(fog_viewport.size)
	fog_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED if review else SubViewport.UPDATE_ALWAYS
	fog_material.set_shader_parameter("camera",camera);fog_material.set_shader_parameter("view_size",size);fog_material.set_shader_parameter("zoom",zoom)
	for key in {"camera":camera,"view_size":size,"zoom":zoom,"player":player,"radius":float(doc.vision_radius),"map_origin":Hex.v(doc.bounds.position)}:
		surface_material.set_shader_parameter(key,{"camera":camera,"view_size":size,"zoom":zoom,"player":player,"radius":float(doc.vision_radius),"map_origin":Hex.v(doc.bounds.position)}[key])
		for material in face_materials.values():material.set_shader_parameter(key,surface_material.get_shader_parameter(key))
	var viewport:=Rect2(camera-size/(2*zoom),size/zoom).grow(600)
	_refresh_tiles(viewport);_refresh_sprites(viewport);_refresh_mountain_faces();actor.queue_redraw()

func _refresh_tiles(viewport:Rect2) -> void:
	var wanted:Dictionary={}
	if doc.bounds.size[0]*zoom>2764.8:
		for tile in spec.tiles:
			var b:Array=tile.clip_bounds
			var rect:=Rect2(_pixel_world(Vector2(b[0],b[1])),Vector2(b[2]-b[0],b[3]-b[1])/Hex.v(doc.background.source_tiles.pixel_size)*Hex.v(doc.background.size))
			if not rect.intersects(viewport):continue
			wanted[tile.id]=true
			if tile_nodes.has(tile.id):continue
			var image:=texture(tile.path);var group:=Node2D.new();backdrop.add_child(group);tile_nodes[tile.id]=group
			var raw:=Sprite2D.new();raw.centered=false;raw.texture=image;raw.z_index=-3;raw.position=_pixel_world(Vector2(tile.rect[0]+tile.offset[0],tile.rect[1]+tile.offset[1]));raw.scale=Vector2(tile.rect[2],tile.rect[3])/Hex.v(doc.background.source_tiles.pixel_size)*Hex.v(doc.background.size)/image.get_size();group.add_child(raw)
			var vertices:=PackedVector3Array();var uv:=PackedVector2Array()
			for i in range(0,tile.triangles.size(),2):
				var pixel:=Vector2(tile.triangles[i],tile.triangles[i+1]);var p:=_pixel_world(pixel);vertices.append(Vector3(p.x,p.y,0));uv.append((pixel-Vector2(tile.rect[0]+tile.offset[0],tile.rect[1]+tile.offset[1]))/Vector2(tile.rect[2],tile.rect[3]))
			var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv
			var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var node:=MeshInstance2D.new();node.mesh=mesh;node.texture=image;node.z_index=-2;node.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;group.add_child(node)
	for key in tile_nodes.keys():
		if not wanted.has(key):tile_nodes[key].queue_free();tile_nodes.erase(key)

func _pixel_world(p:Vector2) -> Vector2:return Hex.v(doc.background.position)+p/Hex.v(doc.background.source_tiles.pixel_size)*Hex.v(doc.background.size)

func _refresh_sprites(viewport:Rect2) -> void:
	for site in doc.sites:
		var pos:=Hex.v(site.position);var visible:bool=viewport.grow(float(site.get("visual",{}).get("width",255))).has_point(pos)
		if not visible:
			if sprites.has(site.id):sprites[site.id].visible=false
			continue
		if not sprites.has(site.id):
			var node:=Node2D.new();node.name=site.id;node.position=pos;node.z_index=int(site.get("visual",{}).get("z_index",0));objects.add_child(node);sprites[site.id]=node
			if seam_specs.has(site.id):_seam_shadow(node,seam_specs[site.id],pos)
			if site.get("visual"):_sprite(node,site.visual,"Visual")
			for index in site.get("visual",{}).get("layers",[]).size():
				var layer:Dictionary=site.visual.layers[index];_sprite(node,layer,"Layer"+str(index))
			if not site.get("visual") and site.kind=="event":_event_marker(node)
			if site.kind in ["house","town"]:
				var label:=Label.new();label.name="PaperLabel";label.text=site.name;label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",48);label.add_theme_color_override("font_color",Color("423b2c"));label.add_theme_color_override("font_outline_color",Color("eee5c4"));label.add_theme_constant_override("outline_size",8);label.position=Vector2(-160,24);label.size=Vector2(320,64);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;node.add_child(label)
				Presentation.install_landmark_bases(world,[{"id":site.id,"type":site.kind}])
		var node:Node2D=sprites[site.id];node.visible=true
		var known:bool=site.kind=="town" or site.id=="layout_summoning_hut"
		var copy:=remembered.get_node_or_null(NodePath(str(site.id)))
		if known and not review:
			if not copy:copy=node.duplicate();copy.z_index=0;remembered.add_child(copy)
			if copy.has_node("GroundPatch"):copy.get_node("GroundPatch").z_index=-3
			copy.visible=true;copy.modulate=Color(.93,.93,.93,.94)
		elif copy:copy.visible=false

# Only art is lifted above the fog. No terrain, actors, event state or LOS is revealed.
# A near face must be in range and reachable before this first opaque surface.
func _front_face_visible(surface:Dictionary,occluders:Array) -> bool:
	var radius:=float(doc.vision_radius)
	for polygon in surface.get("_rings",[surface._polygon]):
		for i in polygon.size():
			var near:=Geometry2D.get_closest_point_to_segment(player,polygon[i],polygon[(i+1)%polygon.size()])
			if player.distance_to(near)>radius-12:continue
			var front:=near.move_toward(player,2.0)
			if Sight.visible(player,front,occluders):return true
	return false

func _refresh_mountain_faces() -> void:
	var occluders:=_occluders()
	for id in surface_sites:
		var copy:=mountain_faces.get_node_or_null(NodePath(str(id)))
		var surface:Dictionary=surface_sites[id]
		var in_sight:=not review and _front_face_visible(surface,occluders)
		if in_sight:
			revealed_faces[id]=true
			if not copy and sprites.has(id):
				copy=sprites[id].duplicate();copy.z_index=0;mountain_faces.add_child(copy)
				for child in copy.get_children():
					if child is Sprite2D or child is MeshInstance2D:child.material=face_materials[id]
		if copy:
			copy.visible=in_sight
			copy.modulate=Color(.98,.98,.98,1)

func _seam_shadow(parent:Node2D,specification:Dictionary,origin:Vector2) -> void:
	var vertices:=PackedVector3Array();var colors:=PackedColorArray()
	var points:Array=specification.triangles
	for i in range(0,points.size(),2):
		var point:=Vector2(points[i],points[i+1])-origin
		vertices.append(Vector3(point.x,point.y,0));colors.append(Color(specification.color))
	if vertices.is_empty():return
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var shadow:=MeshInstance2D.new();shadow.name="BlackSeamShadow";shadow.z_index=-1;shadow.mesh=mesh;parent.add_child(shadow)

func _sprite(node:Node2D,visual:Dictionary,label:String) -> void:
	var a:Dictionary=assets.get(visual.get("asset_id",""),{})
	if a.is_empty():return
	var image:=texture(a.path)
	if not image:return
	var w:float=visual.get("width",255);var h:=w*float(a.height)/float(a.width)*float(visual.get("height_scale",1));var anchor:Vector2=Hex.v(visual.get("anchor",a.get("anchor",[.5,1])))
	var sprite:=Sprite2D.new();sprite.name=label;sprite.texture=image;sprite.scale=Vector2(w,h)/image.get_size();sprite.position=(Vector2(.5,.5)-anchor)*Vector2(w,h)+Hex.v(visual.get("offset",[0,0]));sprite.rotation=deg_to_rad(float(visual.get("rotation",0)));sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index=int(visual.get("z_index",0)) if label!="Visual" else 0
	node.add_child(sprite)

func _event_marker(node:Node2D) -> void:
	var polygon:=Polygon2D.new();polygon.polygon=PackedVector2Array([Vector2(0,-60),Vector2(45,-15),Vector2(0,30),Vector2(-45,-15)]);polygon.color=Color("e8d6a5");node.add_child(polygon)
	var line:=Line2D.new();line.points=polygon.polygon+PackedVector2Array([polygon.polygon[0]]);line.width=6;line.default_color=Color("80613e");line.antialiased=true;node.add_child(line)
	var mark:=Label.new();mark.text="?";mark.position=Vector2(-20,-58);mark.add_theme_font_size_override("font_size",64);mark.add_theme_color_override("font_color",Color("80613e"));node.add_child(mark)

func _occluders() -> Array:
	var area:=Rect2(player-Vector2.ONE*float(doc.vision_radius),Vector2.ONE*float(doc.vision_radius)*2).grow(255)
	var result:Array=[]
	for surface in visual_surfaces:
		if surface._bounds.intersects(area):result.append(surface)
	# Background-only walls retain their original opaque boundary.
	for cell in model.cells:
		if model.terrain_kind(cell)!="mountain" or (covered_cells.has(str(cell.x)+","+str(cell.y)) and not model.cells[cell].get("mountain_manual_rule",false)):continue
		var p:Vector2=model.center(cell)
		if not area.has_point(p):continue
		result.append(Sight.occluder(model.polygon(cell)))
	return result

func _logical_visible(point:Vector2) -> bool:return player.distance_to(point)<=float(doc.vision_radius) and model.line_of_sight(player,point)

func _update_sight() -> void:
	if player.distance_to(last_sight)<8:return
	last_sight=player;Sight.update_rays(rays,player,float(doc.vision_radius),_occluders());ray_texture.update(rays)
	fog_material.set_shader_parameter("player",player);fog_material.set_shader_parameter("sight_origin",player)
	if player.distance_to(last_stamp)<16:return
	last_stamp=player
	var step:=Hex.v(doc.bounds.size)/Vector2(explored.get_size());var origin:=Hex.v(doc.bounds.position);var radius:=float(doc.vision_radius)
	var first:=Vector2i(((player-Vector2.ONE*radius-origin)/step).floor()).max(Vector2i.ZERO);var last:=Vector2i(((player+Vector2.ONE*radius-origin)/step).ceil()).min(explored.get_size()-Vector2i.ONE)
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			var p:=origin+Vector2(x+.5,y+.5)*step
			if Sight.surface_visible_in_rays(rays,player,p,radius):explored.set_pixel(x,y,Color.WHITE)
	explored_texture.update(explored)

func _build_navigation() -> void:
	var id:=0
	for cell in model.cells:
		var p:Vector2=model.center(cell)
		if model.blocked(p):continue
		nav_ids[cell]=id;nav.add_point(id,p);id+=1
	for cell in nav_ids:
		for direction in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,1)]:
			if nav_ids.has(cell+direction) and not model.crosses_art(model.center(cell),model.center(cell+direction)):nav.connect_points(nav_ids[cell],nav_ids[cell+direction])

func _gui_input(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE:dragging=event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:zoom=clampf(zoom*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.15),.025,1.3);refresh_view()
		elif event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			var destination:Vector2=camera+(event.position-size*.5)/zoom
			if nav.get_point_count()>0:route=nav.get_point_path(nav.get_closest_point(player),nav.get_closest_point(destination))
	elif event is InputEventMouseMotion and dragging:camera-=event.relative/zoom;refresh_view()
	accept_event()

func _unhandled_key_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F2:toggle_review()
		if event.keycode==KEY_F3:review=false;camera=player;zoom=.28;refresh_view()

func _process(delta:float) -> void:
	if route.is_empty():return
	var destination:=route[0];player=player.move_toward(destination,260*minf(delta,.05))
	if player.distance_to(destination)<1:route.remove_at(0)
	_update_sight();refresh_elapsed+=delta
	if refresh_elapsed>.1:refresh_elapsed=0;camera=player;refresh_view()
	actor.queue_redraw()

func _draw_actor() -> void:
	if doc.is_empty() or review:return
	var p:Vector2=size*.5+(player-camera)*zoom;actor.draw_circle(p,7,Color("f6e4a6"));actor.draw_arc(p,9,0,TAU,32,Color("485535"),2,true)
