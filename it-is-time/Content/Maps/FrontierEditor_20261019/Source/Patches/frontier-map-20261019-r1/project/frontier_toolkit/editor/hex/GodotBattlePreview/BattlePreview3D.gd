extends Node3D
const Pose=preload("res://battle_visual_pose.gd")
var spec:Dictionary
var current_map:Dictionary
var textures:Dictionary={}
var scenery:Node3D
var camera:Camera3D
var picker:OptionButton
var angle_picker:OptionButton
var info:Label
var tilt_override:float=-1
var active_index:int=0
var moving:bool=false
var font:=SystemFont.new()

func _ready() -> void:
	font.font_names=["Microsoft YaHei"]
	var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://battle_scene.json"))
	if not parsed is Dictionary:
		push_error("缺少 battle_scene.json，请按说明重新生成战场快照。");return
	spec=parsed
	var layout_path:=str(spec.get("layout_path",""))
	if not layout_path.is_absolute_path():layout_path=ProjectSettings.globalize_path("res://"+layout_path).simplify_path()
	spec.layout_path=layout_path
	if FileAccess.get_sha256(layout_path)!=str(spec.get("layout_sha256","")):
		push_error("战场已更新，请重新生成预览快照，避免读取旧部署和素材。");return
	for asset in spec.assets.values():
		var path:=str(asset.native_path)
		if not path.is_absolute_path():asset.native_path=ProjectSettings.globalize_path("res://"+path).simplify_path()
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("27372e")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=1
	environment.environment=settings;add_child(environment)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;add_child(camera)
	var layer:=CanvasLayer.new();add_child(layer)
	var bar:=HBoxContainer.new();bar.theme=Theme.new();bar.theme.default_font=font;bar.position=Vector2(18,16);layer.add_child(bar)
	picker=OptionButton.new();picker.custom_minimum_size=Vector2(420,36)
	for map in spec.maps:picker.add_item(map.name)
	picker.item_selected.connect(show_map);bar.add_child(picker)
	angle_picker=OptionButton.new();angle_picker.add_item("使用已保存倾角")
	for angle in [45,60,75]:angle_picker.add_item("临时比较：离地 %d°"%angle)
	angle_picker.item_selected.connect(func(index:int):tilt_override=-1 if index==0 else [45,60,75][index-1];show_map(active_index))
	bar.add_child(angle_picker)
	var reset:=Button.new();reset.text="重置镜头";reset.pressed.connect(_reset_camera);bar.add_child(reset)
	info=Label.new();info.add_theme_font_override("font",font);info.position=Vector2(18,58);info.add_theme_font_size_override("font_size",18);layer.add_child(info)
	show_map(0)

func _reset_camera() -> void:
	if current_map.is_empty():return
	camera.rotation_degrees=Vector3(float(current_map.get("presentation",{}).get("camera_pitch_degrees",-50)),0,0)
	camera.position=camera.basis.z*float(current_map.radius)*2.4
	camera.size=float(current_map.radius)*1.75

func texture(path:String) -> Texture2D:
	if not textures.has(path):
		var image:=Image.load_from_file(path)
		if image==null or image.is_empty():return null
		image.generate_mipmaps()
		textures[path]=ImageTexture.create_from_image(image)
	return textures[path]

func mat(color:Color) -> StandardMaterial3D:
	var value:=StandardMaterial3D.new();value.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;value.albedo_color=color;return value

func polygon() -> PackedVector2Array:
	var points:=PackedVector2Array();var start:float=-PI*.5 if current_map.orientation=="pointy" else 0.0
	for i in 6:points.append(Vector2(cos(start+i*PI/3),sin(start+i*PI/3))*float(current_map.radius))
	return points

func show_map(index:int) -> void:
	active_index=index;picker.select(index);current_map=spec.maps[index]
	if scenery:remove_child(scenery);scenery.queue_free()
	scenery=Node3D.new();scenery.name="CurrentBattle";add_child(scenery)
	ground();var count:int=0
	for object:Dictionary in current_map.objects:
		if object.type=="deployment":
			for slot:Array in object.slots:marker(world_point(object,Vector2(slot[0],slot[1])),Color("55bba0"),"己")
		elif object.type=="enemy":marker(Vector2(object.position[0],object.position[1]),Color("dc7870"),str(int(object.get("count",1))))
		elif object.visual.get("visible",true) and not str(object.visual.asset).is_empty():
			if art(object):count+=1
	var alignment:Dictionary=current_map.get("deployment_layout",{})
	var line:=float(alignment.get("center_z",0));var left:float=-float(current_map.radius)*.8;var right:float=-left
	line3d(PackedVector3Array([Vector3(left,.07,line),Vector3(right,.07,line)]),Color(.85,.83,.57,.55))
	_reset_camera()
	info.text="己方青色／敌方红色 · 双方中心 Z %.2f · 离地倾角 %s · %d 个独立美术\n中键平移／滚轮缩放；本页角度比较不写入地图。泥潭、深坑与地表贴片保持贴地。"%[line,str(tilt_override if tilt_override>=0 else 60)+"°",count]

func world_point(object:Dictionary,local:Vector2) -> Vector2:
	return (local*Vector2(object.scale[0],object.scale[1])).rotated(deg_to_rad(float(object.rotation)))+Vector2(object.position[0],object.position[1])

func art(object:Dictionary) -> bool:
	var asset:Dictionary=spec.assets.get(object.visual.asset,{})
	if asset.is_empty():return false
	var image:=texture(asset.native_path)
	if not image:return false
	var host:=Node3D.new();host.name=object.id;host.position=Vector3(object.position[0],object.height,object.position[1]);host.set_meta("editor_object",object);scenery.add_child(host)
	var sprite:=Sprite3D.new();sprite.name="Visual";sprite.texture=image;sprite.pixel_size=1;sprite.modulate.a=float(object.visual.opacity)
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS;sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;host.add_child(sprite)
	var data:Dictionary=object.duplicate(true)
	if tilt_override>=0 and Pose.surface_mode(data)=="tilted":data.visual.tilt_degrees=tilt_override
	Pose.apply(sprite,host,data,float(current_map.get("presentation",{}).get("scenery_tilt_degrees",60)))
	return true

func ground() -> void:
	var points:=polygon();var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		for p in [Vector2.ZERO,points[i],points[(i+1)%6]]:
			mesh.surface_set_normal(Vector3.UP);mesh.surface_add_vertex(Vector3(p.x,0,p.y))
	mesh.surface_end();var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=mat(Color(current_map.ground_color));node.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED;scenery.add_child(node)
	var border:=PackedVector3Array()
	for p in points:border.append(Vector3(p.x,.02,p.y))
	border.append(border[0]);line3d(border,Color("ada37a"))
	var halo:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2.ONE*float(current_map.radius)*3
	halo.mesh=plane;halo.position.y=-.04
	var halo_shader:=Shader.new();halo_shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec2 corners[6];
uniform float feather=4.0;
uniform vec4 tint:source_color;
varying vec2 point;
void vertex(){point=VERTEX.xz;}
void fragment(){
 float outside=-10000.0;
 for(int i=0;i<6;i++){vec2 a=corners[i];vec2 edge=corners[(i+1)%6]-a;outside=max(outside,dot(point-a,normalize(vec2(edge.y,-edge.x))));}
 ALBEDO=tint.rgb;ALPHA=(1.0-smoothstep(0.0,feather,max(0.0,outside)))*.38;
}
"""
	var halo_material:=ShaderMaterial.new();halo_material.shader=halo_shader
	halo_material.set_shader_parameter("corners",points);halo_material.set_shader_parameter("feather",maxf(1,float(current_map.edge_feather)+float(current_map.background_blur)*.25))
	halo_material.set_shader_parameter("tint",Color(current_map.get("background_color",current_map.ground_color)))
	halo.material_override=halo_material;scenery.add_child(halo)
	# Saved hex ground colours stay flat and independent of paper scenery.
	var colors:Dictionary=current_map.get("ground_palette",{})
	for cell:Dictionary in current_map.get("hex_cells",[]):
		if not cell.has("ground"):continue
		var at:=hex_center(cell.q,cell.r);var radius:=float(current_map.hex_grid.cell_width)*.5
		var contour:=PackedVector2Array()
		for i in 6:
			var angle:float=i*PI/3+(PI/6 if current_map.orientation=="pointy" else 0)
			contour.append(at+Vector2(cos(angle),sin(angle))*radius)
		var tile:=ImmediateMesh.new();tile.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for clipped in Geometry2D.intersect_polygons(contour,points):
			for vertex_index:int in Geometry2D.triangulate_polygon(clipped):
				var p:Vector2=clipped[vertex_index];tile.surface_add_vertex(Vector3(p.x,.012,p.y))
		tile.surface_end();var fill:=MeshInstance3D.new();fill.mesh=tile
		var color:=str(colors.get(cell.ground,{"grass":"#779060","plain":"#78816a","soil":"#9b805e","stone":"#747b7d","sand":"#ba9e6c","water":"#527e91"}.get(cell.ground,"#78816a")))
		fill.material_override=mat(Color(color));fill.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED;scenery.add_child(fill)

func hex_center(q:int,r:int) -> Vector2:
	var radius:=float(current_map.hex_grid.cell_width)*.5
	var p:=Vector2(1.5*radius*q,sqrt(3)*radius*(r+q*.5))
	if current_map.orientation=="pointy":p=p.rotated(PI/6)
	return p+Vector2(current_map.hex_grid.origin[0],current_map.hex_grid.origin[1])

func line3d(points:PackedVector3Array,color:Color) -> void:
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:mesh.surface_add_vertex(point)
	mesh.surface_end();var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=mat(color);scenery.add_child(node)

func marker(point:Vector2,color:Color,text:String) -> void:
	var cylinder:=CylinderMesh.new();cylinder.top_radius=.55;cylinder.bottom_radius=.55;cylinder.height=.12
	var node:=MeshInstance3D.new();node.mesh=cylinder;node.material_override=mat(color);node.position=Vector3(point.x,.13,point.y);scenery.add_child(node)
	var label:=Label3D.new();label.font=font;label.text=text;label.font_size=40;label.pixel_size=.025;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.position=Vector3(point.x,.55,point.y);label.no_depth_test=false;scenery.add_child(label)

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE:moving=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:camera.size=clampf(camera.size*(.88 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.12),6,float(current_map.radius)*3)
	elif event is InputEventMouseMotion and moving:
		camera.position+=Vector3(-event.relative.x,0,-event.relative.y/sin(deg_to_rad(50)))*camera.size/float(get_viewport().get_visible_rect().size.y)
