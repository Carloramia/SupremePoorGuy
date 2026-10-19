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
	root.size=Vector2i(640,400)
	var world:=Node2D.new();root.add_child(world)
	var ground:=ColorRect.new();ground.size=Vector2(640,400);ground.color=Color(.8,.75,.3);world.add_child(ground)
	# One concave asset has two lobes along a ray; the ray must not cut its art in half.
	var shape:=PackedVector2Array([Vector2(170,110),Vector2(320,110),Vector2(320,290),Vector2(280,290),Vector2(280,150),Vector2(260,150),Vector2(260,290),Vector2(170,290)])
	var rock:=Polygon2D.new();rock.polygon=shape;rock.color=Color(.65,.55,.50);world.add_child(rock)
	var rays:=Image.create(Sight.RAY_COUNT,1,false,Image.FORMAT_RG8)
	Sight.update_rays(rays,Vector2(100,200),230,[Sight.occluder(shape)])
	var ray_texture:=ImageTexture.create_from_image(rays)
	var parameters:={"sight_rays":ray_texture,"map_origin":Vector2.ZERO,"map_size":Vector2(640,400),"player":Vector2(100,200),"sight_origin":Vector2(100,200),"camera":Vector2(320,200),"view_size":Vector2(640,400),"zoom":1.0,"radius":230.0,"feather":44.0,"pixel_size":12.0,"cloud_speed":0.0}
	var explored:=Image.create(64,40,false,Image.FORMAT_R8);explored.fill(Color.BLACK)
	parameters.explored_mask=ImageTexture.create_from_image(explored)
	var buffer:=SubViewport.new();buffer.size=Vector2i(640,400);buffer.transparent_bg=true;buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(buffer)
	var fog:=ColorRect.new();fog.size=Vector2(640,400);buffer.add_child(fog)
	var fog_material:=ShaderMaterial.new();var fog_shader:=Shader.new();fog_shader.code=Sight.fog_shader();fog_material.shader=fog_shader;fog.material=fog_material
	for key in parameters:fog_material.set_shader_parameter(key,parameters[key])
	var display:=TextureRect.new();display.size=Vector2(640,400);display.texture=buffer.get_texture();world.add_child(display)
	# Reproduce the real renderer: the same rock art is lifted above its fog.
	var lifted:Polygon2D=rock.duplicate();world.add_child(lifted)
	var surface_material:=ShaderMaterial.new();var surface_shader:=Shader.new();surface_shader.code=Sight.surface_shader();surface_material.shader=surface_shader;lifted.material=surface_material
	for key in parameters:surface_material.set_shader_parameter(key,parameters[key])
	var mask:=Image.create(640,400,false,Image.FORMAT_R8)
	for y in 400:
		for x in 640:
			var d:float=-1000
			for rect in [Rect2(170,110,90,180),Rect2(170,110,150,40),Rect2(280,110,40,180)]:
				var signed_distance:float=minf(minf(x-rect.position.x,rect.end.x-x),minf(y-rect.position.y,rect.end.y-y)) if rect.has_point(Vector2(x,y)) else -Vector2(maxf(maxf(rect.position.x-x,x-rect.end.x),0),maxf(maxf(rect.position.y-y,y-rect.end.y),0)).length()
				d=maxf(d,signed_distance)
			mask.set_pixel(x,y,Color(clampf(.5+d/128.0,0,1),0,0,1))
	surface_material.set_shader_parameter("rear_mask",ImageTexture.create_from_image(mask));surface_material.set_shader_parameter("rear_bounds",Vector4(0,0,640,400));surface_material.set_shader_parameter("rear_mask_enabled",true)
	surface_material.set_shader_parameter("fog_texture",buffer.get_texture());surface_material.set_shader_parameter("fog_texture_available",true)
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.save_png("res://rear_overlap.png")
	var fog_image:=buffer.get_texture().get_image()
	var front:=image.get_pixel(185,200);var rear:=image.get_pixel(254,200);var fog_rear:=fog_image.get_pixel(254,200)
	check(front.is_equal_approx(rock.color) or Vector3(front.r-rock.color.r,front.g-rock.color.g,front.b-rock.color.b).length()<.025,"mountain front keeps its original material")
	check(fog_image.get_pixel(262,200).a>.98,"fog closes the ground immediately behind the rear silhouette")
	check(fog_rear.a>.8,"fog extends inward over the rear foot of the mountain")
	var rear_shift:=Vector3(rear.r-rock.color.r,rear.g-rock.color.g,rear.b-rock.color.b).length()
	check(rear_shift>.008 and rear_shift<.15,"rear stone receives a subtle mist veil while keeping its material")
	var second_lobe:=image.get_pixel(286,200)
	check(Vector3(second_lobe.r-rock.color.r,second_lobe.g-rock.color.g,second_lobe.b-rock.color.b).length()<.025,"concave mountain art keeps its front faces beyond the first ray interval")
	check(fog_image.get_pixel(115,200).a<.02,"open ground in front of the mountain remains clear")
	FileAccess.open("res://rear_overlap_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"checks":results,"rear_fog_alpha":fog_rear.a,"behind_fog_alpha":fog_image.get_pixel(262,200).a,"front_color":[front.r,front.g,front.b],"rear_color":[rear.r,rear.g,rear.b],"fog_color":[fog_rear.r,fog_rear.g,fog_rear.b]},"\t"))
	quit(1 if failures else 0)
