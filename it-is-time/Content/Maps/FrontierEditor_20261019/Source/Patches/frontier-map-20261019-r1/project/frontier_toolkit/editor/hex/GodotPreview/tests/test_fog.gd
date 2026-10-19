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
	var ground:=ColorRect.new();ground.size=Vector2(640,400);ground.color=Color(.7,.67,.33);world.add_child(ground)
	var rock:=Polygon2D.new();rock.polygon=PackedVector2Array([Vector2(170,120),Vector2(220,120),Vector2(220,280),Vector2(170,280)]);rock.color=Color(.58,.59,.65);world.add_child(rock)
	var behind:=ColorRect.new();behind.position=Vector2(250,190);behind.size=Vector2(20,20);behind.color=Color.RED;world.add_child(behind)
	var rays:=Image.create(Sight.RAY_COUNT,1,false,Image.FORMAT_RGBA8)
	var obstacles:Array=[Sight.occluder(rock.polygon)]
	Sight.update_rays(rays,Vector2(100,200),180,obstacles)
	var fog:=ColorRect.new();fog.size=Vector2(640,400);world.add_child(fog)
	var material:=ShaderMaterial.new();var shader:=Shader.new();shader.code=Sight.fog_shader();material.shader=shader;fog.material=material
	var explored:=Image.create(64,40,false,Image.FORMAT_R8);explored.fill(Color.BLACK)
	for entry in {"explored_mask":ImageTexture.create_from_image(explored),"sight_rays":ImageTexture.create_from_image(rays),"map_origin":Vector2.ZERO,"map_size":Vector2(640,400),"player":Vector2(100,200),"sight_origin":Vector2(100,200),"camera":Vector2(320,200),"view_size":Vector2(640,400),"zoom":1.0,"radius":180.0,"feather":44.0,"pixel_size":20.0}:
		material.set_shader_parameter(entry,{"explored_mask":ImageTexture.create_from_image(explored),"sight_rays":ImageTexture.create_from_image(rays),"map_origin":Vector2.ZERO,"map_size":Vector2(640,400),"player":Vector2(100,200),"sight_origin":Vector2(100,200),"camera":Vector2(320,200),"view_size":Vector2(640,400),"zoom":1.0,"radius":180.0,"feather":44.0,"pixel_size":20.0}[entry])
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.save_png("res://result.png")
	var stone:=image.get_pixel(195,200);var target:=image.get_pixel(260,200)
	check(Vector3(stone.r-rock.color.r,stone.g-rock.color.g,stone.b-rock.color.b).length()<.08,"visible mountain material is not erased by its own occlusion")
	check(target.r<.55 and target.r<target.g*1.4,"terrain and actors behind the mountain remain fogged")
	check(not Sight.visible(Vector2(100,200),Vector2(195,200),obstacles) and not Sight.visible(Vector2(100,200),Vector2(260,200),obstacles),"gameplay line of sight remains blocked independently of surface rendering")
	var blended:=0
	for y in range(0,100):
		var color:=image.get_pixel(100,y)
		if color.r>.4 and color.r<.68:blended+=1
	check(blended>=18,"fog boundary has a broad continuous feather instead of a hard cut")
	var same_block_a:=image.get_pixel(104,48);var same_block_b:=image.get_pixel(109,48)
	check(Vector3(same_block_a.r-same_block_b.r,same_block_a.g-same_block_b.g,same_block_a.b-same_block_b.b).length()<.01,"fog opacity stays consistent inside a world-locked pixel block")
	check(absf(image.get_pixel(104,39).r-image.get_pixel(104,40).r)>.04,"fog edge uses deliberate pixel steps while terrain remains unscaled")
	FileAccess.open("res://result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"checks":results,"rock_color":[stone.r,stone.g,stone.b],"behind_color":[target.r,target.g,target.b],"feather_pixels":blended},"\t"))
	quit(1 if failures else 0)
