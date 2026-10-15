extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var preview:=Node3D.new()
	preview.name="Human4HandStatesPreview"
	var environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color(0.13,0.14,0.16)
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color.WHITE
	settings.ambient_light_energy=0.8
	environment.environment=settings
	preview.add_child(environment)
	environment.owner=preview
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-18,-20,0)
	light.light_energy=0.7
	preview.add_child(light)
	light.owner=preview
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Human/Metadata/hand_state_models.json"))
	var column:=0
	for record:Dictionary in data.models:
		if record.set!=4:continue
		for pose:String in ["open","grip"]:
			var state:=load("res://Resources/Creatures/VisualStates/Human/"+str(record.name)+pose.capitalize()+".tres") as BodyPartVisualState3D
			for back:bool in [false,true]:
				var mesh:=MeshInstance3D.new()
				mesh.name=str(record.name)+pose.capitalize()+("Back" if back else "Palm")
				mesh.mesh=state.mesh
				var basis:=Basis.from_scale(Vector3(1,1,0.08))*Basis(Vector3.BACK,-float(record.rotation_z))
				if back:basis=Basis(Vector3.UP,PI)*basis
				mesh.transform=Transform3D(basis,Vector3(-4.5+column*3,2.25 if not back else -0.75,0))
				preview.add_child(mesh)
				mesh.owner=preview
				var label:=Label3D.new()
				label.text="%s / %s / %s" % [str(record.side).capitalize(),pose.capitalize(),"Back" if back else "Palm"]
				label.position=mesh.position+Vector3(0,0.55,0)
				label.font_size=42
				label.pixel_size=0.006
				label.outline_size=0
				preview.add_child(label)
				label.owner=preview
			column+=1
	var camera:=Camera3D.new()
	camera.name="Camera3D"
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=7.5
	camera.position=Vector3(0,0.1,15)
	camera.current=true
	preview.add_child(camera)
	camera.owner=preview
	var packed:=PackedScene.new()
	assert(packed.pack(preview)==OK)
	assert(ResourceSaver.save(packed,"res://Assets/3DResources/Creatures/Human/Previews/Human4HandStatesPreview.tscn")==OK)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(1536,960)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(preview)
	for i:int in 5:await process_frame
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	assert(image!=null and not image.is_empty())
	assert(image.save_png("D:/GameJamWorkspace/Reports/BodyPartVisualStates_Human4Preview.png")==OK)
	print("PASS: Saved Human4 hand states 3D preview scene and rendered palm/back poses.")
	quit()
