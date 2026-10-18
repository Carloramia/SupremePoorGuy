extends SceneTree
## Offscreen Godot render of the authored pose; physics remains frozen throughout.

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var console := root.get_node_or_null("RuntimeConsole")
	if console != null: console.set("auto_getlogs_enabled",false)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600,1200)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var actor := load("res://Scenes/Creatures/Characters/Generate_Bird.tscn").instantiate() as Node3D
	actor.set("generate_on_ready",false)
	for node: Node in actor.find_children("*","",true,false): node.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(actor)
	for node: Node in actor.get_node("GeneratedParts").get_children():
		if node is RigidBody3D: node.freeze = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.94,0.94,0.94)
	world.add_child(environment)
	var bounds := AABB()
	var first := true
	for node: Node in actor.get_node("GeneratedParts").get_children():
		if not node is PhysicalBodyPart3D: continue
		var mesh := node.get_node("Model/PaperVolume") as MeshInstance3D
		var box: AABB = mesh.global_transform*mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.y,bounds.size.x*0.75)*1.15
	camera.position = bounds.get_center()+Vector3(0,0,30)
	world.add_child(camera)
	camera.current = true
	for frame: int in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	assert(image != null)
	assert(image.save_png("D:/GameJamWorkspace/Reports/BirdAssembly_2026-10-18/Bird1Assembly.png") == OK)
	print("BIRD_ASSEMBLY_RENDERED")
	world.free()
	viewport.free()
	quit()
