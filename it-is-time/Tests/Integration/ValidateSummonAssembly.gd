extends SceneTree
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const VIEW = preload("res://Scripts/Application/SummonAssemblyView.gd")
var failed := false
var checks := 0
var captures := {}

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	print("SUMMON_CHECK ",value," ",message)
	if not value: failed = true; push_error(message)

func records() -> Array:
	var result: Array = []
	for id: String in FACTORY.SUMMON_POOL:
		var record := FACTORY.template(id)
		record.merge({"id":"summon_"+id,"position":"pending","traits":[]},true)
		result.append(record)
	return result

func capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name()=="headless" or captures.has(name): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(args[0]+"/summon_"+name+".png")==OK,"Capture "+name)
	captures[name] = true

func run() -> void:
	root.size = Vector2i(1280,720)
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var audio := root.get_node("CombatAudio")
	audio.settings = audio.settings.duplicate()
	audio.settings.enabled = false
	var fixture := records()
	var original := fixture.duplicate(true)
	var view := VIEW.new()
	view.settings = view.settings.duplicate()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--radius="): view.settings.emission_radius = argument.trim_prefix("--radius=").to_float()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.begin(fixture)
	view.stage.rng.seed = 12345
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): view.stage.rng.seed = argument.trim_prefix("--seed=").to_int()
	var completed := [0]
	view.finished.connect(func(): completed[0] += 1)
	for frame: int in 120:
		if view.phase != "preparing": break
		view.advance(0.0)
		await physics_frame
	check(view.phase=="burst","Prepare complete creatures and decorations across frame batches")
	var stage: Node3D = view.stage
	check(stage.scene_file_path=="res://Scenes/Application/SummonBattleStage3D.tscn","A dedicated empty battle stage provides floor, emitter and camera")
	check(stage.creatures.size()==5 and stage.get_node("Creatures").get_child_count()==5,"Spawn exactly the five saved summoned creatures and no enemies")
	check(view.viewport.own_world_3d and view.viewport.find_world_3d()!=root.find_world_3d(),"Private physics world is isolated from gameplay")
	await framing_checks(view)
	var no_overlap := true
	for index: int in stage._occupied.size():
		for other: int in range(index+1,stage._occupied.size()): no_overlap = no_overlap and not stage._occupied[index].intersects(stage._occupied[other])
	check(no_overlap and stage._occupied.size()==5,"Reserve separated assembly footprints using the saved anatomy")
	check(view.settings.emission_radius<=0.0 or stage.emission_radius>=view.settings.emission_radius,"Requested radius expands only to preserve creature spacing")
	var floor_box: AABB = stage._ground_bounds()
	var selected_points: Array[Vector2] = []
	var intact := true
	var poses := {}
	for creature: Dictionary in stage.creatures:
		selected_points.append(creature.emission_point)
		intact = intact and creature.parts.size()==fixture[stage.creatures.find(creature)].parts.size() and not creature.joints.is_empty()
		var visuals := {}
		for part: Dictionary in creature.parts:
			for child: Node3D in part.body.find_children("*","Node3D",true,false): visuals[child.get_instance_id()] = child.transform
		poses[creature.record_id] = visuals
		check(not creature.actor.get_node("NPCStateMachine3D").can_process(),"AI remains disabled: "+creature.record_id)
		var body: PhysicalBodyPart3D = creature.parts[0].body
		var hp := body.current_hp
		check(body.apply_damage(100000.0)==0.0,"Presentation ignores damage: "+creature.record_id)
		body.break_part()
		check(not body.is_broken and body.current_hp==hp,"Presentation ignores break requests: "+creature.record_id)
	check(intact,"Use every actual saved physical part and preserve its joint nodes")
	check(stage.creatures.all(func(creature): return creature.parts.filter(func(part): return 6 in part.body.tags).all(func(part): return stage._part_order(part.body)==1)),"SubTorso assembles after Torso even when both physical tags are present")
	check(selected_points.all(func(point): return point.length()<=stage.emission_radius+0.001),"Assembly positions sample the shared map-centered circle")
	var decorations: Array = stage.pieces.map(func(piece): return weakref(piece.body))
	check(not decorations.is_empty() and decorations.size()<=view.settings.maximum_wrong_parts,"Decorative debris uses the bounded random-part pool")
	await boundary_checks(stage)
	await observation_checks(view)
	await pause_checks(view)
	# Release the captured pointer during the long simulation so native mouse input cannot alter QA framing.
	if not view._free_mouse: await key(view)
	stage.frame_camera(view.size.x/maxf(view.size.y,1.0))
	var observed_fade := false
	var planar := true
	var collision_masks := true
	var emergence_valid := true
	var suspended := true
	var hidden := true
	var decorated_points := false
	var powerful_decorations := true
	var free_motion_seen := false
	var falling_seen := false
	var maximum_concurrent := 0
	var maximum_pool: int = stage.pieces.size()
	var emissions_at_completion := -1
	var emission_stopped := true
	var cadence_valid := true
	var last_emissions: int = stage.decorations_emitted
	var last_emission_time: float = stage.last_decoration_time
	var name_fading_seen := false
	var name_pause_checked := false
	for frame: int in 3600:
		view.advance(1.0/60.0)
		maximum_concurrent = maxi(maximum_concurrent,stage.creatures.filter(func(creature): return creature.state=="assembling").size())
		maximum_pool = maxi(maximum_pool,stage.get_node("Decorations").get_child_count())
		if stage.decorations_emitted>last_emissions:
			cadence_valid = cadence_valid and (stage.last_decoration_time-last_emission_time)/float(stage.decorations_emitted-last_emissions)<=view.settings.decoration_interval+0.02
			last_emissions = stage.decorations_emitted
			last_emission_time = stage.last_decoration_time
		if stage.summon_complete_time>=0.0:
			if emissions_at_completion<0: emissions_at_completion = stage.decorations_emitted
			emission_stopped = emission_stopped and stage.decorations_emitted==emissions_at_completion
		for piece: Dictionary in stage.pieces:
			if piece.fade>0.0 and piece.fade<1.0: observed_fade = true; await capture("fade")
			if piece.launched:
				decorated_points = true
				powerful_decorations = powerful_decorations and piece.upward_speed>=10.0 and piece.upward_speed<=14.0
				emergence_valid = emergence_valid and piece.emission_point.length()<=stage.emission_radius+0.001 and piece.initial_bounds.end.y<=floor_box.position.y-view.settings.emergence_clearance+0.001
				if piece.emerged_time<0.0:
					collision_masks = collision_masks and piece.body.collision_layer==0 and piece.body.collision_mask==0
					emergence_valid = emergence_valid and piece.age==0.0 and piece.fade==0.0
				else:
					collision_masks = collision_masks and piece.body.collision_layer==1 and piece.body.collision_mask==2
					emergence_valid = emergence_valid and piece.emergence_bounds.position.y>=floor_box.end.y+view.settings.emergence_clearance-0.001
		for creature: Dictionary in stage.creatures:
			if creature.state=="idle" and stage.elapsed-creature.idle_time<view.settings.name_fade_in_duration:
				var label: Label3D = creature.label
				name_fading_seen = name_fading_seen or (label.modulate.a>0.0 and label.modulate.a<1.0 and label.position.y<creature.label_target.y)
				if not name_pause_checked and label.modulate.a>0.0:
					var name_position := label.position
					var name_color := label.modulate
					view.set_paused(true)
					for pause_frame: int in 4: await physics_frame
					check(label.position==name_position and label.modulate==name_color,"Settings pause freezes the name reveal as well as the creature")
					view.set_paused(false)
					name_pause_checked = true
			if creature.state=="assembling" and creature.next_part>=creature.parts.size()/2: await capture("assembly_middle")
			if creature.state!="idle":
				suspended = suspended and creature.joints.all(func(row): return row.node.node_a.is_empty() and row.node.node_b.is_empty()) and creature.springs.all(func(row): return not row.node.can_process())
			for part: Dictionary in creature.parts:
				var body: RigidBody3D = part.body
				planar = planar and body.axis_lock_angular_x and body.axis_lock_angular_y and absf(body.global_basis.z.normalized().dot(Vector3.BACK))>0.999
				if part.state=="waiting": hidden = hidden and not body.visible and body.freeze
				if creature.state!="idle" and part.state!="free_motion": collision_masks = collision_masks and body.collision_layer==0 and body.collision_mask==0
				else: collision_masks = collision_masks and body.collision_layer==4 and body.collision_mask==2
				if part.state=="emerging": await capture("emergence")
				if part.state=="free_motion":
					free_motion_seen = true
					falling_seen = falling_seen or body.linear_velocity.y < -1.0
					await capture("free_motion")
				if part.state=="attracting": await capture("assembly")
		if maximum_concurrent>=2 and stage.creatures.filter(func(creature): return creature.state=="assembling").size()>=2: await capture("parallel")
		if view.phase=="reveal": await capture("idle")
		if view.phase=="finished": break
		await physics_frame
	check(view.phase=="finished" and completed[0]==1,"All five creatures assemble and completion emits exactly once")
	check(name_fading_seen and name_pause_checked,"Creature names ease upward while fading in after assembly")
	check(stage.creatures.all(func(creature): return creature.label.visible and creature.label.position.is_equal_approx(creature.label_target) and creature.label.modulate.a==1.0 and creature.label.outline_modulate.a==1.0),"Names settle above their creatures and remain opaque")
	check(observed_fade and stage.pieces.is_empty() and decorations.all(func(ref): return ref.get_ref()==null),"Decoration visuals fade before their bodies are destroyed")
	check(planar and hidden,"Parts keep their sheet plane; pending parts remain hidden and frozen")
	check(suspended,"All solver joints and cross-segment springs stay suspended throughout assembly")
	check(collision_masks,"Only free-flight and completed biological parts collide with terrain; emergence and attraction remain collision-free")
	check(free_motion_seen and falling_seen,"Biological parts visibly fly freely and descend under gravity before assembly")
	check(decorated_points and emergence_valid,"Decorations retain shared-circle eruption, floor clearance and post-emergence fading")
	check(powerful_decorations,"Decorative parts also use the increased 10-to-14 upward launch speed")
	check(maximum_concurrent>=2,"Several creatures assemble concurrently instead of waiting for previous completion")
	check(maximum_pool<=view.settings.maximum_wrong_parts and stage.decorations_emitted>decorations.size(),"Continuous decoration emission reuses the bounded pool")
	check(cadence_valid and stage.summon_complete_time-stage.last_decoration_time<=view.settings.decoration_interval+0.02,"Random decoration emission continues at the configured cadence until the last assembly completes")
	check(emission_stopped and stage.summon_complete_time>=stage.creatures.map(func(creature): return creature.idle_time).max(),"Stop new decorations only after every creature completes, then fade and clean the remainder")
	print("SUMMON_PARALLEL ",JSON.stringify({"maximum_concurrent":maximum_concurrent,"pool":maximum_pool,"emitted":stage.decorations_emitted,"last_emission":stage.last_decoration_time,"summon_complete":stage.summon_complete_time,"finished":stage.elapsed}))
	for index: int in stage.creatures.size():
		var creature: Dictionary = stage.creatures[index]
		if index>0: check(absf(creature.launch_time-stage.creatures[index-1].launch_time-view.settings.creature_start_interval)<0.02,"Start the next creature one second after the previous start")
		var staggered := true
		var parallel := false
		var nearby := true
		var crossed := true
		var natural := true
		var arrived := true
		var unchanged := true
		var ordered := true
		var landed := true
		var stronger_launch := true
		var shortest_free_motion := INF
		for part_index: int in creature.parts.size():
			var part: Dictionary = creature.parts[part_index]
			var body: RigidBody3D = part.body
			if part_index>0:
				var previous: Dictionary = creature.parts[part_index-1]
				staggered = staggered and part.launch_time-previous.launch_time>=view.settings.part_interval-0.001
				parallel = parallel or part.launch_time<previous.arrival_time
				ordered = ordered and stage._part_order(previous.body)<=stage._part_order(body)
			nearby = nearby and part.emission_point.distance_to(creature.emission_point)<=view.settings.part_spawn_radius+0.001
			crossed = crossed and part.initial_bounds.end.y<=floor_box.position.y-view.settings.emergence_clearance+0.001 and part.emerged_time>part.launch_time and part.emergence_bounds.position.y>=floor_box.end.y+view.settings.emergence_clearance-0.001
			natural = natural and part.initial_basis.is_equal_approx(part.rest.basis)
			landed = landed and part.ground_time>part.emerged_time and part.attraction_time>=part.ground_time and part.attraction_time-part.emerged_time>=view.settings.part_free_motion_duration and int(part.get("ground_collider_id",0))==stage.get_node("Ground").get_instance_id() and Vector3(part.get("ground_normal",Vector3.ZERO)).dot(Vector3.UP)>0.5
			stronger_launch = stronger_launch and part.upward_speed>=10.0 and part.upward_speed<=14.0
			shortest_free_motion = minf(shortest_free_motion,part.attraction_time-part.emerged_time)
			arrived = arrived and part.state=="assembled" and part.arrival_time>=part.emerged_time and body.global_transform.is_equal_approx(part.rest) and body.freeze and body.linear_velocity.is_zero_approx() and body.angular_velocity.is_zero_approx()
			for child: Node3D in body.find_children("*","Node3D",true,false): unchanged = unchanged and child.transform.is_equal_approx(poses[creature.record_id][child.get_instance_id()])
		check(staggered and parallel and ordered,"Ordered part emission uses the configured gap and overlapping attraction: "+creature.record_id)
		check(nearby and crossed and natural,"Parts erupt locally, clear the whole floor and preserve authored orientation: "+creature.record_id)
		check(landed and stronger_launch,"Stronger eruption is followed by the minimum free-motion time and real ground contact before attraction: "+creature.record_id)
		check(arrived and unchanged,"Complete saved anatomy, model and collision transforms match exactly: "+creature.record_id)
		check(creature.joints.all(func(row): return row.node.node_a==row.a and row.node.node_b==row.b) and creature.springs.all(func(row): return row.node.process_mode==row.mode),"Restore joint endpoints and spring process settings after assembly: "+creature.record_id)
		check(creature.state=="idle" and not creature.actor.is_temporarily_ragdolled() and creature.actor.get_control_components().all(func(node): return not node.can_process()),"Direct idle presentation keeps gameplay disabled: "+creature.record_id)
		print("SUMMON_ASSEMBLY_RESULT ",JSON.stringify({"id":creature.record_id,"launch":creature.launch_time,"idle":creature.idle_time,"parts":creature.parts.size(),"point":str(creature.emission_point),"radius":stage.emission_radius,"shortest_free_motion":shortest_free_motion}))
	check(fixture==original,"No HP, pose, currency or summon result changes are written to saved records")
	view.advance(2.0)
	check(completed[0]==1,"Repeated advancement cannot finish twice")
	view.stop()
	view.queue_free()
	await process_frame
	await process_frame
	await application_flow(fixture)
	print("SUMMON_ASSEMBLY_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)

func check_framing(view: Control) -> void:
	var stage: Node3D = view.stage
	var camera: Camera3D = view.camera
	var screen := Rect2(Vector2.ZERO,Vector2(view.viewport.size)).grow(-1.0)
	var circle_visible := true
	for sample: int in 128:
		var point: Vector3 = Vector3(cos(sample*TAU/128.0),0,sin(sample*TAU/128.0))*stage.emission_radius
		circle_visible = circle_visible and not camera.is_position_behind(point) and screen.has_point(camera.unproject_position(point))
	check(circle_visible,"Default view covers the whole emission circle at "+str(view.viewport.size))
	var anatomy_visible := true
	for creature: Dictionary in stage.creatures:
		var box: AABB = stage._creature_envelope(creature,true)
		for corner: int in 8:
			var point := box.get_endpoint(corner)
			anatomy_visible = anatomy_visible and not camera.is_position_behind(point) and screen.has_point(camera.unproject_position(point))
	check(anatomy_visible,"Saved complete anatomy also fits the initial view")
	var floor_box: AABB = stage._ground_bounds()
	var environment: Environment = stage.get_node("WorldEnvironment").environment
	var material := stage.get_node("Ground/Mesh").mesh.material as ShaderMaterial
	var black_edges: bool = environment.background_color.is_equal_approx(Color.BLACK) and environment.ambient_light_energy<0.4 and stage.get_node("Sun").light_energy<1.0 and material!=null
	if material!=null:
		black_edges = black_edges and material.shader.resource_path=="res://Shaders/SummonGroundFade.gdshader" and Vector2(material.get_shader_parameter("ground_half_size")).is_equal_approx(Vector2(stage._arena_size.x,stage._arena_size.z)*0.5)
	var ground_and_sky_blend := black_edges
	for x: float in [0.0,float(view.viewport.size.x)]:
		for y: float in [0.0,float(view.viewport.size.y)]:
			var pixel := Vector2(x,y)
			var origin := camera.project_ray_origin(pixel)
			var direction := camera.project_ray_normal(pixel)
			if direction.y>=-0.001:
				continue
			var point := origin+direction*((floor_box.end.y-origin.y)/direction.y)
			if point.x>floor_box.position.x and point.x<floor_box.end.x and point.z>floor_box.position.z and point.z<floor_box.end.z:
				ground_and_sky_blend = ground_and_sky_blend and point.distance_to(origin)<camera.far
	check(ground_and_sky_blend,"Dark ground fades into the same black as sky-facing view rays")
	check(absf(stage.get_node("DragCamera3D/PitchPivot").rotation_degrees.x+35.0)<0.01,"Summon camera starts at the shallower 35-degree pitch")
	print("SUMMON_FRAMING ",JSON.stringify({"viewport":str(view.viewport.size),"distance":stage.get_node("DragCamera3D").get_distance(),"floor":str(stage._arena_size),"radius":stage.emission_radius,"circle_visible":circle_visible,"anatomy_visible":anatomy_visible,"dark_edge_blending":ground_and_sky_blend}))

func framing_checks(view: Control) -> void:
	view.set_paused(true)
	var original_size := root.size
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1024,768),Vector2i(2560,1080),Vector2i(720,1280)]:
		root.size = dimensions
		for frame: int in 3: await process_frame
		view.stage.frame_camera(view.size.x/maxf(view.size.y,1.0))
		check_framing(view)
	root.size = original_size
	for frame: int in 3: await process_frame
	view.stage.frame_camera(view.size.x/maxf(view.size.y,1.0))
	await capture("framing_default")
	view.set_paused(false)

func key(view: Control, echo: bool = false) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = KEY_Q
		event.physical_keycode = KEY_Q
		event.pressed = pressed
		event.echo = echo if pressed else false
		root.push_input(event,true)
		await process_frame
		await physics_frame

func mouse(view: Control, relative: Vector2, button: MouseButton = MOUSE_BUTTON_NONE, pressed := false, settle := true) -> void:
	var event: InputEventMouse
	if button == MOUSE_BUTTON_NONE:
		event = InputEventMouseMotion.new()
		event.relative = relative
		event.button_mask = MOUSE_BUTTON_MASK_RIGHT if view.stage.get_node("DragCamera3D")._orbiting else 0
	else:
		event = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.button_mask = (1 << (button-1)) if pressed else 0
	event.position = view.get_global_rect().get_center()
	event.global_position = event.position
	root.push_input(event,true)
	if settle:
		for frame: int in 2: await physics_frame
	if pressed and button in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var release: InputEventMouseButton = event.duplicate()
		release.pressed = false
		release.button_mask = 0
		root.push_input(release,true)
		await process_frame

func observation_checks(view: Control) -> void:
	var rig: Node3D = view.stage.get_node("DragCamera3D")
	var cursor: TerrainCursor3D = view.stage.get_node("TerrainCursor3D")
	var distance: float = rig.get_distance()
	var rotation := rig.rotation
	var pitch: float = rig.get_node("PitchPivot").rotation.x
	for frame: int in 3: await physics_frame
	check(view.camera==rig.get_camera() and view.camera.projection==Camera3D.PROJECTION_PERSPECTIVE and rig.scene_file_path=="res://Scenes/Camera/DragCamera3D.tscn","Observation reuses the battle's perspective DragCamera3D")
	check(cursor.free_cursor_mode and cursor.free_camera_rig==rig and not cursor.selection_enabled and cursor.has_valid_ground_position() and cursor.is_gameplay_cursor_active(),"A free blue terrain cursor observes the private stage without controlling creatures")
	var localization := root.get_node("GameLocalization")
	var locale: String = localization.current_locale()
	localization.set_locale("en",false)
	check(view.get_node("ObservationHint").text.begins_with("Move mouse"),"The observation hint resolves English and updates live")
	localization.set_locale("zh_CN",false)
	check(view.get_node("ObservationHint").text.begins_with("移动鼠标"),"The observation hint resolves Chinese and updates live")
	localization.set_locale(locale,false)
	if DisplayServer.get_name()!="headless": check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Observation captures the real system mouse")
	var before := cursor.get_mouse_ground_position()
	await mouse(view,Vector2(120,-60))
	check(cursor.get_mouse_ground_position().distance_to(before)>1.0 and rig.global_position.is_equal_approx(cursor.get_mouse_ground_position()),"Real mouse motion pans the cursor and camera together")
	before = cursor.get_mouse_ground_position()
	# Deliver a drag atomically so native captured-pointer warps cannot interleave the synthetic gesture.
	await mouse(view,Vector2.ZERO,MOUSE_BUTTON_RIGHT,true,false)
	await mouse(view,Vector2(80,-30),MOUSE_BUTTON_NONE,false,false)
	await mouse(view,Vector2.ZERO,MOUSE_BUTTON_RIGHT,false,false)
	check(not rig.rotation.is_equal_approx(rotation) and cursor.get_mouse_ground_position().is_equal_approx(before),"Right drag orbits without moving the ground cursor")
	await mouse(view,Vector2.ZERO,MOUSE_BUTTON_WHEEL_UP,true)
	check(rig.get_distance()<distance,"The real wheel event zooms the perspective camera")
	await key(view)
	check(not cursor.is_gameplay_cursor_active() and not rig.input_enabled,"Q releases observation for UI interaction")
	if DisplayServer.get_name()!="headless": check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Q displays the real system mouse")
	var pose := rig.global_transform
	var zoom: float = rig.get_distance()
	await mouse(view,Vector2(200,100))
	await mouse(view,Vector2.ZERO,MOUSE_BUTTON_WHEEL_UP,true)
	await key(view,true)
	check(rig.global_transform.is_equal_approx(pose) and rig.get_distance()==zoom and view._free_mouse,"Released mouse and Q key repeat cannot manipulate the camera")
	await key(view)
	check(cursor.is_gameplay_cursor_active() and rig.input_enabled,"Second Q resumes the terrain cursor")
	cursor.set_cursor_world_position(Vector3(100000,0,-100000))
	var rectangle: Rect2 = cursor.world_horizontal_bounds
	var point := cursor.get_mouse_ground_position()
	check(point.x<=rectangle.end.x and point.z>=rectangle.position.y,"Cursor panning stays inside the map instead of losing terrain")
	for frame: int in 3: await physics_frame
	var host := preload("res://Scripts/Player/PlayerControlContext.gd").application(view)
	if host != null: host.ui._settings()
	else: view.set_paused(true)
	for frame: int in 2: await process_frame
	pose = rig.global_transform
	await mouse(view,Vector2(200,100))
	await key(view)
	check(not cursor.is_gameplay_cursor_active() and rig.global_transform.is_equal_approx(pose) and not view._free_mouse,"Presentation pause blocks observation and Q without changing mouse preference")
	if host != null: host.ui._close_all()
	else: view.set_paused(false)
	var console := root.get_node("RuntimeConsole")
	console.set_console_open(true)
	for frame: int in 2: await process_frame
	check(not cursor.is_gameplay_cursor_active() and not rig.input_enabled,"Console input releases the observation controls")
	console.set_console_open(false)
	rig.rotation = rotation
	rig.get_node("PitchPivot").rotation.x = pitch
	rig._pitch_radians = pitch
	rig.set_distance(distance)
	cursor.set_cursor_world_position(Vector3.ZERO)
	for frame: int in 3: await physics_frame

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true)
	for frame: int in 2: await process_frame

func boundary_checks(stage: Node3D) -> void:
	var walls: Array[Node] = stage.get_node("BoundaryWalls").get_children()
	check(walls.size()==4 and walls.all(func(wall): return wall is StaticBody3D and wall.collision_layer==2 and wall.collision_mask==5 and wall.find_children("*","GeometryInstance3D",true,false).is_empty()),"Four invisible walls share the stage collision layer")
	var probes: Array[Dictionary] = []
	for wall: StaticBody3D in walls:
		var normal := Vector3(wall.position.x,0,wall.position.z).normalized()
		var probe := PhysicalBodyPart3D.new()
		probe.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso])
		probe.gravity_scale = 0.0
		probe.collision_layer = 1 if probes.size()%2==0 else 4
		probe.collision_mask = 2
		probe.position = Vector3(wall.position.x,3,wall.position.z)-normal*2
		probe.linear_velocity = normal*20
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = BoxShape3D.new()
		collision.shape.size = Vector3.ONE*0.6
		probe.add_child(collision)
		var sprite := Sprite3D.new()
		sprite.name = "Sprite3D"
		probe.add_child(sprite)
		stage.add_child(probe)
		probe.set_process(false)
		probes.append({"body":probe,"wall":wall,"normal":normal})
	for frame: int in 20: await physics_frame
	for row: Dictionary in probes:
		var projection: float = row.body.position.dot(row.normal)
		var limit: float = row.wall.position.dot(row.normal)-1.0
		check(projection<=limit and row.wall in row.body.get_colliding_bodies(),"Physical collision prevents escape through "+str(row.wall.name))
		row.body.queue_free()
	await process_frame

func pause_checks(view: Control) -> void:
	var actor := RigidBody3D.new()
	actor.gravity_scale = 0.0
	actor.linear_velocity = Vector3.RIGHT
	actor.position = Vector3(0,20,0)
	view.stage.add_child(actor)
	var pose := actor.global_transform
	var clock: float = view.elapsed
	view.set_paused(true)
	for frame: int in 8: view.advance(1.0); await physics_frame
	check(actor.global_transform.is_equal_approx(pose) and view.elapsed==clock,"Settings-style pause stops physics and all presentation timers")
	view.set_paused(false)
	var probe := RigidBody3D.new()
	probe.gravity_scale = 0.0
	probe.linear_velocity = Vector3.RIGHT
	probe.position.x = 500.0
	root.add_child(probe)
	var extra := SubViewport.new()
	extra.own_world_3d = true
	root.add_child(extra)
	var extra_space := extra.find_world_3d().space
	PhysicsServer3D.space_set_active(extra_space,false)
	paused = true
	view.advance(0.0)
	var later := SubViewport.new()
	later.own_world_3d = true
	root.add_child(later)
	var later_space := later.find_world_3d().space
	for frame: int in 2: await physics_frame
	var outside := probe.position
	var inside := actor.global_position
	for frame: int in 12: view.advance(1.0/60.0); await physics_frame
	check(actor.global_position.distance_to(inside)>0.01 and view.elapsed>clock,"Private physics continues while the gameplay SceneTree is paused")
	check(probe.position.is_equal_approx(outside),"Reopening preview physics never advances the paused gameplay world")
	check(not PhysicsServer3D.space_is_active(later_space),"Newly added viewports are also isolated during a paused presentation")
	view.set_paused(true)
	var frozen := actor.global_transform
	for frame: int in 8: await physics_frame
	check(actor.global_transform.is_equal_approx(frozen),"Opening settings during a global pause also stops the preview")
	view.set_paused(false)
	paused = false
	view.advance(0.0)
	for frame: int in 8: await physics_frame
	check(probe.position.x>outside.x and not PhysicsServer3D.space_is_active(extra_space),"Resume restores gameplay physics and preserves previously inactive spaces")
	actor.queue_free()
	probe.queue_free()
	extra.queue_free()
	later.queue_free()
	await process_frame

func application_flow(fixture: Array) -> void:
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path = "user://summon_stage_session.json"
	app.display_settings_path = "user://summon_stage_display.cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.start_new_game()
	for frame: int in 600:
		if app.phase=="world": break
		await process_frame
	app.ui._close_all()
	for record: Dictionary in fixture:
		app.session.data.monsters.append(record.duplicate(true))
		app.session.data.pending.append(record.id)
	app.session.data.pending_return = "world"
	check(app.session.save(),"Persist the pending summon batch before presentation")
	var before: Dictionary = app.session.data.duplicate(true)
	app.ui._resume_pending()
	check(app.ui.view.running and app.ui.view.summon_assembly!=null and not app.delivery_map.visible,"Formal summon route displays the new stage")
	for frame: int in 120:
		if app.ui.view.summon_assembly.phase!="preparing": break
		await process_frame
	app.set_pause_reason(&"summon_test",true)
	var assembly: Control = app.ui.view.summon_assembly
	check_framing(assembly)
	await observation_checks(assembly)
	check(app.is_gameplay_blocked() and preload("res://Scripts/Player/PlayerControlContext.gd").interface_open(app),"Private observation never unlocks the underlying paused gameplay")
	var clock: float = assembly.elapsed
	for frame: int in 12: await physics_frame
	check(assembly.elapsed>clock,"Real UI keeps summon animation active during gameplay pause")
	app.ui._settings()
	for frame: int in 2: await process_frame
	clock = assembly.elapsed
	var part: RigidBody3D = assembly.stage.creatures[0].parts[0].body
	var pose := part.global_transform
	for frame: int in 12: await physics_frame
	check(assembly.elapsed==clock and part.global_transform.is_equal_approx(pose),"Real settings menu pauses complete creatures and debris")
	check(not assembly.stage.get_node("TerrainCursor3D").is_gameplay_cursor_active() and not assembly.stage.get_node("DragCamera3D").input_enabled,"Real settings also release the observation mouse and camera")
	app.ui._close_all()
	for frame: int in 6: await physics_frame
	check(assembly.elapsed>clock,"Closing settings resumes the stage")
	check(assembly.stage.get_node("TerrainCursor3D").is_gameplay_cursor_active(),"Closing settings restores the selected observation mouse mode")
	await capture("interface")
	await key(assembly)
	check(assembly._free_mouse,"Q releases the pointer before using the real Skip button")
	await click(app.ui.base.get_node("%Settings"))
	check(app.ui.overlay.visible and app.ui.modal_stack.back().get("kind","")=="settings","Released pointer can click the real Settings button")
	app.ui._close_all()
	for frame: int in 3: await process_frame
	check(assembly._free_mouse and not assembly.stage.get_node("TerrainCursor3D").is_gameplay_cursor_active(),"Closing settings preserves a deliberately released mouse")
	await capture("free_mouse")
	var skip_button: Button = app.ui.actions.get_child(0)
	await click(skip_button)
	for frame: int in 2: await process_frame
	check(not app.ui.view.running and app.ui.view.summon_assembly==null and app.ui.overlay.visible,"Q then a real Skip button click cleans the world and opens the original result interface")
	check(not PhysicsServer3D.space_is_active(root.find_world_3d().space) or paused,"Skip restores the gameplay pause instead of leaving the physics server open")
	app.set_pause_reason(&"summon_test",false)
	app.ui.view.skip_eruption()
	check(app.session.data==before and app.session.data.pending.size()==5,"Skip cannot repeat summons, consume currency or write presentation damage")
	app.ui._close_all()
	app.ui._resume_pending()
	app.return_to_main_menu()
	for frame: int in 4: await process_frame
	check(app.phase=="main" and app.ui.view.summon_assembly==null and app.session.data.pending.size()==5,"Returning to menu cancels preparation and preserves pending results")
	check(not paused,"Leaving the presentation restores the original SceneTree pause")
	app.queue_free()
	await process_frame
	await process_frame
