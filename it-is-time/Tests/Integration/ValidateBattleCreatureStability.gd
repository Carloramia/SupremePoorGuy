extends SceneTree
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value and not failed: failed = true; push_error(message)
func run() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var host := preload("res://Scripts/Application/BattleHost.gd").new()
	host.definition = preload("res://Content/Maps/IntegrationFrontier_v1/camp_battle_01/SceneDefinition.tres")
	host.monster_config_definitions = {"demo_guard":"human"}
	viewport.add_child(host)
	var records: Array = []
	for species: String in ["snake","wolf","snake"]:
		var record := FACTORY.template(species)
		record.merge({"id":"stability_"+str(records.size()),"position":"team","traits":[]},true)
		records.append(record)
	check(await host.deploy(records,"creature_stability"),"Mixed battle deploys")
	if host.actors.size()!=4: quit(1); return
	host.ended = true
	for actor: Node3D in host.actors:
		for body: Node in actor.get_node("GeneratedParts").get_children():
			if body is PhysicalBodyPart3D: body.max_hp = 100000.0; body.current_hp = body.max_hp
	var plane_peak := 0.0
	var heading_peak := 0.0
	var rejoin_frames := 0
	var wolf_reported := false
	var snake_reported := [false,false]
	var center_ratios := [0.0,0.0]
	for tick: int in 1800:
		await physics_frame
		if tick<120: continue
		var wolf := host.actors[1].get_node("GeneratedLegStepMovementController3D")
		var diagnostics: Dictionary = wolf.get_stance_support_diagnostics()
		heading_peak = maxf(heading_peak,absf(diagnostics.wolf_heading.error_degrees))
		for row: Dictionary in diagnostics.wolf_limb_planes.parts: plane_peak = maxf(plane_peak,row.plane_error_degrees)
		if plane_peak>40.0 and not wolf_reported:
			wolf_reported = true
			print("BATTLE_WOLF_DEVIATION heading=",diagnostics.wolf_heading," recovery=",wolf.recovery_control_active," action_feet=",wolf._action_feet.size()," ragdoll=",host.actors[1].is_temporarily_ragdolled()," planes=",diagnostics.wolf_limb_planes)
		for snake_index: int in 2:
			var snake := host.actors[snake_index*2].get_node("SnakeMovementController3D")
			if snake.is_connection_recovering(): rejoin_frames += 1
			for index: int in range(1,snake._parts.size()):
				var a: Dictionary = snake._parts[index-1]
				var b: Dictionary = snake._parts[index]
				check(b.body.global_position.is_finite() and b.body.linear_velocity.is_finite(),"Snake physics stays finite")
				if b.ground_pair:
					var ratio: float = a.body.global_position.distance_to(b.body.global_position)/maxf(b.rest_gap,0.01)
					center_ratios[snake_index] = maxf(center_ratios[snake_index],ratio)
					if ratio>1.4 and not snake_reported[snake_index]:
						snake_reported[snake_index] = true
						print("BATTLE_SNAKE_DEVIATION actor=",snake_index," pair=",b.body.name," ratio=",ratio," state=",snake.get_snake_motion_diagnostics(false))
		if tick%300==0: print("BATTLE_STABILITY_PROGRESS frame=",tick," wolf_plane_peak=",plane_peak," wolf_heading_peak=",heading_peak," snake_center_ratios=",center_ratios)
	print("BATTLE_CREATURE_STABILITY wolf_plane_peak=",plane_peak," wolf_heading_peak=",heading_peak," snake_center_ratios=",center_ratios," rejoin_frames=",rejoin_frames)
	check(plane_peak<90.0,"Wolf limbs do not invert their torso plane")
	check(center_ratios[0]<1.5 and center_ratios[1]<1.5,"Snakes keep adjacent ground bodies within their structural span")
	viewport.queue_free()
	await process_frame; await process_frame
	print("BATTLE_CREATURE_STABILITY_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
