extends SceneTree
const Sight=preload("res://MapSight.gd")
var failures:=0
var results:Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(value:bool,label:String) -> void:
	results[label]=value
	print(("PASS " if value else "FAIL ")+label)
	if not value:failures+=1
func run() -> void:
	# Match the lifted mountain pass: opaque artwork over a transparent viewport.
	var buffer:=SubViewport.new();buffer.size=Vector2i(640,400);buffer.transparent_bg=true;buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(buffer)
	var stone:=Polygon2D.new();stone.polygon=PackedVector2Array([Vector2(170,110),Vector2(260,110),Vector2(260,290),Vector2(170,290)]);stone.color=Color(.65,.55,.5);buffer.add_child(stone)
	var shader:=Shader.new();shader.code=Sight.surface_shader();var material:=ShaderMaterial.new();material.shader=shader;stone.material=material
	var mask:=Image.create(640,400,false,Image.FORMAT_R8)
	for y in 400:
		for x in 640:
			var d:float=minf(minf(x-170,260-x),minf(y-110,290-y)) if Rect2(170,110,90,180).has_point(Vector2(x,y)) else -Vector2(maxf(maxf(170-x,x-260),0),maxf(maxf(110-y,y-290),0)).length()
			mask.set_pixel(x,y,Color(clampf(.5+d/128.0,0,1),0,0,1))
	var parameters:={"rear_mask":ImageTexture.create_from_image(mask),"rear_bounds":Vector4(0,0,640,400),"rear_mask_enabled":true,"player":Vector2(100,200),"camera":Vector2(320,200),"view_size":Vector2(640,400),"radius":630.0,"map_origin":Vector2.ZERO,"cloud_speed":0.0}
	for key in parameters:material.set_shader_parameter(key,parameters[key])
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	var image:=buffer.get_texture().get_image();image.save_png("res://mountain_integrity.png")
	var lost_pixels:=0
	for y in range(111,289):
		for x in range(171,259):
			if image.get_pixel(x,y).a<.98:lost_pixels+=1
	check(lost_pixels==0,"rear mist preserves the entire opaque stone silhouette")
	var front:=image.get_pixel(185,200);var rear:=image.get_pixel(254,200)
	var original:=Vector3(stone.color.r,stone.color.g,stone.color.b)
	var front_rgb:=Vector3(front.r,front.g,front.b)/maxf(front.a,.001)
	var rear_rgb:=Vector3(rear.r,rear.g,rear.b)/maxf(rear.a,.001)
	check(front_rgb.distance_to(original)<.025,"front stone material is unchanged")
	check(rear.a>.98 and rear_rgb.distance_to(original)>.008 and rear_rgb.distance_to(original)<.15,"rear stone receives a thin mist tint without being erased")
	FileAccess.open("res://mountain_integrity_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"checks":results,"lost_opaque_pixels":lost_pixels,"rear_alpha":rear.a,"rear_color_shift":rear_rgb.distance_to(original)},"\t"))
	quit(1 if failures else 0)
