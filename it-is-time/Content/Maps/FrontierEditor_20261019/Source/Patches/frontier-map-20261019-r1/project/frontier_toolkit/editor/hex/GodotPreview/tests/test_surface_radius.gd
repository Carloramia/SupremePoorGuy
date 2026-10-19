extends SceneTree
const Sight=preload("res://MapSight.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(640,400)
	var bg:=ColorRect.new();bg.size=Vector2(640,400);bg.color=Color(.30,.37,.34);root.add_child(bg)
	# One continuous mountain asset extends past the player's range at both ends.
	var stone:=Polygon2D.new();stone.polygon=PackedVector2Array([Vector2(170,0),Vector2(220,0),Vector2(220,400),Vector2(170,400)]);stone.color=Color(.7,.6,.5);root.add_child(stone)
	var shader:=Shader.new();shader.code=Sight.surface_shader();var material:=ShaderMaterial.new();material.shader=shader;stone.material=material
	var parameters:={"player":Vector2(100,200),"camera":Vector2(320,200),"view_size":Vector2(640,400),"zoom":1.0,"radius":180.0,"pixel_size":20.0,"map_origin":Vector2.ZERO}
	for key in parameters:material.set_shader_parameter(key,parameters[key])
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var inside:=image.get_pixel(195,200);var outside:=image.get_pixel(195,20)
	var in_ok:=absf(inside.r-.7)<.02
	var out_ok:=absf(outside.r-.30)<.02 and absf(outside.g-.37)<.02
	var art_edge_delta:=absf(image.get_pixel(195,72).r-image.get_pixel(195,77).r)
	var art_edge_continuous:=art_edge_delta>.008 and art_edge_delta<.08
	var leaks:=0
	for x in range(170,220):
		for y in 400:
			if Vector2(x+.5,y+.5).distance_to(Vector2(100,200))>180.0 and absf(image.get_pixel(x,y).r-.30)>.02:leaks+=1
	var result:={"in_range_mountain_visible":in_ok,"out_of_range_mountain_hidden":out_ok,"stone_pixels_leaked_beyond_radius":leaks,"art_edge_is_continuous":art_edge_continuous,"art_edge_sample_delta":art_edge_delta}
	FileAccess.open("res://surface_radius_checks.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("SURFACE_RADIUS ",result)
	quit(0 if in_ok and out_ok and leaks==0 and art_edge_continuous else 1)
