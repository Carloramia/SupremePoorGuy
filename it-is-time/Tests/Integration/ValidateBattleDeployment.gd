extends SceneTree
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var failed := false
var output := "D:/GameJamWorkspace/Reports/BattleDeployment_2026-10-16"

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("DEPLOYMENT_CHECK ",ok," ",message)
	if not ok: failed = true; push_error(message)
func wait_phase(app: Node, wanted: String) -> bool:
	for tick: int in 600:
		if app.phase == wanted: return true
		await physics_frame
	return false
func action(app: Node, name: StringName) -> void:
	for pressed: bool in [true,false]:
		if name == &"MouseLeft":
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = app.battle_container.get_global_rect().get_center()
			event.global_position = event.position
			event.pressed = pressed
			root.push_input(event,true)
		else:
			var event := InputEventAction.new()
			event.action = name
			event.pressed = pressed
			root.push_input(event,true)
		await process_frame
func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at; motion.global_position = at
	root.push_input(motion,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at; event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		root.push_input(event,true)
		await process_frame
func capture(app: Node, state: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var suffix := "delivery" if app.use_delivery_map else "legacy"
	check(root.get_texture().get_image().save_png(output+"/"+state+"_"+suffix+".png") == OK,"Capture deployment UI: "+state)
func create_app(delivery: bool) -> Node:
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = delivery
	app.save_path = output+"/session_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path = output+"/display.cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	return app
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	for delivery: bool in [false,true]:
		var app := create_app(delivery)
		app.start_new_game()
		check(await wait_phase(app,"world"),"World initializes: "+str(delivery))
		app.ui._close_all()
		var unit := FACTORY.template("human" if delivery else "stump_beast")
		unit.merge({"id":"test_human","position":"team","traits":[]},true)
		app.session.data.monsters.append(unit)
		check(app.session.save(),"Save isolated party fixture")
		var saved: Dictionary = app.session.monster_by_id("test_human").duplicate(true)
		if delivery:
			var catalog := preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
			for camp: Dictionary in catalog.world().objects:
				if camp.type == "camp" and "wolf" in str(camp.get("enemy_config_id","")):
					app.delivery_map.runtime.data.player = camp.position.duplicate()
					app.delivery_map.runtime.data.discovered.append(camp.id)
					check(app.delivery_map.begin_battle(camp.id,"clear"),"Delivery battle request")
					break
		else:
			var location: WorldMapLocation = app.world_map.get_location(&"bandits")
			location.state.discovered = true
			app.world_map.player.global_position = location.interaction_point()
			app.world_map.interaction.begin(location)
			app.world_map.interaction.request_battle()
		check(await wait_phase(app,"deployment"),"Both battle entrances wait in deployment")
		if app.battle == null or app.phase != "deployment": quit(1); return
		await _exercise(app,saved)
		app.queue_free()
		await process_frame; await process_frame
	await _mixed_species()
	print("BATTLE_DEPLOYMENT_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _exercise(app: Node, saved: Dictionary) -> void:
	var host: Node3D = app.battle
	var deployment: Node3D = host.deployment
	var ally: Node3D = host.actors[0]
	var enemy: Node3D = host.actors[1]
	var cursor: TerrainCursor3D = host.cursor
	print("DEPLOYMENT_LAYOUT region=",host.deployment_polygon," body=",FACTORY.local_bounds(saved)," actor=",ally.position)
	var poses := {}
	for body: RigidBody3D in ally.find_children("*","RigidBody3D",true,false): poses[body] = body.global_transform
	for tick: int in 30: await physics_frame
	check(not host.ready_for_combat and host.elapsed == 0.0 and not paused,"Deployment stops combat time without pausing the interactive camera/cursor")
	for actor: Node3D in host.actors:
		check(not actor.can_process(),"Both factions' controllers are disabled")
		for node: Node in actor.find_children("*","",true,false): check(not node.can_process(),"No creature component can bypass deployment freeze")
		for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false): check(body.freeze,"All physical parts/weapons are frozen")
	check(cursor.is_gameplay_cursor_active() and cursor.deployment_mode and host.deployment.has_node("DeploymentBoundary"),"Free cursor and blue boundary are active")
	check(not host.has_node("BattleEnvironmentEffects"),"Environmental damage/effects do not run before combat")
	check(not cursor._is_selectable_character(enemy) and not deployment.pick_up(enemy),"Enemies cannot be selected or dragged")
	await action(app,&"Space")
	check(app.phase == "deployment" and not paused,"Space cannot start or pause deployment")
	var center: Vector3 = cursor._get_character_projection(ally).center
	cursor.set_cursor_world_position(center)
	for tick: int in 3: await physics_frame
	check(cursor.get_selected_character() == ally,"Hover locks the ally")
	var ring := cursor.get_node("Ring") as MeshInstance3D
	var material := ring.material_override as StandardMaterial3D
	check(material.albedo_color.b > material.albedo_color.r,"Hover remains blue")
	await capture(app,"blue")
	await action(app,&"MouseLeft")
	check(deployment.dragged == ally and app.ui.start_battle_button.disabled,"First click carries the ally and disables Start")
	check(material.albedo_color.g > material.albedo_color.b,"Carried cursor is green")
	app.start_battle()
	check(app.phase == "deployment","Start is rejected while carrying")
	var old_origin: Vector3 = ally.global_position
	var old_pointer := cursor.get_mouse_ground_position()
	var move_by := Vector3(2 if app.use_delivery_map else 0,0,2)
	cursor.set_cursor_world_position(old_pointer+move_by)
	for tick: int in 3: await physics_frame
	var offset: Vector3 = ally.global_position-old_origin
	check(Vector2(offset.x,offset.z).distance_to(Vector2(move_by.x,move_by.z)) < 0.001,"Carry follows cursor translation")
	var same_pose := true
	for body: RigidBody3D in poses:
		var expected: Transform3D = poses[body]
		expected.origin += offset
		if not body.global_transform.is_equal_approx(expected): print("POSE_DIFFERENCE ",body.get_path()," before=",poses[body]," expected=",expected," actual=",body.global_transform)
		same_pose = same_pose and body.global_transform.is_equal_approx(expected)
	check(same_pose,"All body and weapon transforms keep their relative pose and orientation")
	await capture(app,"green")
	var enemy_origin: Vector3 = enemy.global_position
	var enemy_poses := {}
	for body: RigidBody3D in enemy.find_children("*","RigidBody3D",true,false): enemy_poses[body] = body.global_transform
	var enemy_offset: Vector3 = ally.get_combat_anchor().global_position-enemy.get_combat_anchor().global_position
	enemy.global_position += enemy_offset
	for body: RigidBody3D in enemy_poses:
		var pose: Transform3D = enemy_poses[body]
		pose.origin += enemy_offset
		body.global_transform = pose
	await physics_frame; await physics_frame
	check(not deployment.validate_placement(ally).is_empty(),"Other creatures block placement")
	enemy.global_position = enemy_origin
	for body: RigidBody3D in enemy_poses: body.global_transform = enemy_poses[body]
	await physics_frame; await physics_frame
	# A real enabled obstacle blocks placement; disabling its shape immediately permits it.
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 8
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE*0.1
	shape.shape = box
	obstacle.add_child(shape)
	host.add_child(obstacle)
	obstacle.global_position = ally.get_combat_anchor().global_position
	await physics_frame; await physics_frame
	check(not deployment.validate_placement(ally).is_empty(),"Enabled obstacle blocks the actual creature collider")
	shape.disabled = true
	await physics_frame; await physics_frame
	check(deployment.validate_placement(ally).is_empty(),"Disabled obstacle collider does not block placement: "+deployment.validate_placement(ally))
	shape.disabled = false
	await physics_frame; await physics_frame
	await action(app,&"MouseLeft")
	check(deployment.dragged == ally and not deployment.placement_error.is_empty(),"Illegal second click refuses placement and shows the reason")
	obstacle.free()
	cursor.set_cursor_world_position(Vector3(-500,0,0))
	await physics_frame; await physics_frame
	check(not deployment.place_dragged() and deployment.dragged == ally and cursor.visible,"Off-map carry stays green and cannot be placed")
	cursor.set_cursor_world_position(old_pointer+move_by)
	await physics_frame; await physics_frame
	await action(app,&"MouseLeft")
	check(deployment.dragged == null and not app.ui.start_battle_button.disabled,"Legal second click places the ally: "+deployment.placement_error)
	if deployment.dragged != null: return
	check(material.albedo_color.b > material.albedo_color.r,"Placed cursor returns to blue")
	check(app.session.monster_by_id("test_human") == saved,"Deployment does not edit warehouse/generator poses")
	await action(app,&"QPressed")
	check(app.free_mouse_enabled and not cursor.is_gameplay_cursor_active() and not paused,"Q releases the mouse so the Start button is clickable")
	if DisplayServer.get_name() != "headless":
		for tick: int in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/deployment_"+("delivery" if app.use_delivery_map else "legacy")+".png")
	await click(app.ui.start_battle_button)
	check(app.phase == "battle" and host.ready_for_combat and not app.free_mouse_enabled,"Actual Start button begins combat and returns to the terrain cursor")
	await process_frame
	check(not cursor.deployment_mode and not app.ui.start_battle_button.visible and host.deployment == null,"Deployment controls and boundary leave the scene")
	check(not app.use_delivery_map or host.has_node("BattleEnvironmentEffects"),"Environmental effects begin with combat")
	for actor: Node3D in host.actors:
		check(actor.can_process(),"Start enables both factions' AI")
		for body: PhysicalBodyPart3D in actor.find_children("*","PhysicalBodyPart3D",true,false): check(not body.freeze,"Start resumes physical bodies")
	await action(app,&"Space")
	check(paused and app.ui.pause_hint.visible,"Combat pause remains functional")
	await action(app,&"Space")
	check(not paused,"Combat resumes")
	host.finish("retreat")
	check(app.phase == "settlement","Battle can settle after deployment")

func _mixed_species() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var host := preload("res://Scripts/Application/BattleHost.gd").new()
	host.delivery_settings = preload("res://Resources/Application/FrontierDeliveryBattle.tres").duplicate(true)
	host.delivery_request = {"battle_map_id":"camp_battle_01","enemy_config_id":"deployment_mixed","deployment_id":""}
	var roster := EnemyRosterData.new()
	roster.definitions.assign(["wolf"])
	host.delivery_settings.enemy_rosters["deployment_mixed"] = roster
	viewport.add_child(host)
	var records: Array = []
	for species: String in FACTORY.SUMMON_POOL:
		var record := FACTORY.template(species)
		record.id = "deployment_"+species
		record.parts = record.parts.duplicate(true)
		record.poses = record.poses.duplicate(true)
		records.append(record)
	check(await host.deploy(records,"mixed_deployment"),"All five summon species fit the delivery deployment region")
	if host.deployment != null:
		for actor: Node3D in host.actors:
			if actor.get_faction_id() != 0: continue
			check(host.deployment.validate_placement(actor).is_empty(),"Initial full-body placement is valid: "+str(actor.name))
			var point: Vector3 = host.cursor._get_character_projection(actor).center
			host.cursor.set_cursor_world_position(point)
			check(host.deployment.pick_up(actor),"Pick mixed creature: "+str(actor.name))
			check(host.deployment.place_dragged(),"Place mixed creature without losing its pose: "+str(actor.name))
			if actor.get_meta(&"creature_instance_id") == "deployment_snake":
				check(host.deployment.pick_up(actor),"Pick Snake again")
				host.cursor.set_cursor_world_position(point+Vector3(1,0,0))
				check(host.deployment.place_dragged(),"Translate Snake before rebuilding its world path")
		check(host.start_combat(),"Moved mixed controllers rebase and activate")
		for tick: int in 12: await physics_frame
	viewport.queue_free()
	await process_frame; await process_frame
