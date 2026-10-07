extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird_NPC.tscn")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for index: int in range(count): await physics_frame
func run() -> void:
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	collision.shape = box
	floor.add_child(collision)
	floor.position.y = -0.5
	root.add_child(floor)
	var region := NavigationRegion3D.new()
	var navmesh := NavigationMesh.new()
	navmesh.vertices = PackedVector3Array([Vector3(-40,0,-40), Vector3(-40,0,40), Vector3(40,0,40), Vector3(40,0,-40)])
	navmesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = navmesh
	root.add_child(region)
	var bird := BIRD.instantiate()
	bird.generate_on_ready = false
	root.add_child(bird)
	var brain := bird.get_node("NPCStateMachine3D")
	brain.enabled = false
	brain.debug_logging_enabled = true
	var generator := bird.get_node("BirdGenerator")
	generator.overall_scale = 1.5
	generator.unsymmetrie = 0.0
	generator.inhomogeneity = 0.0
	generator._random.seed = 43
	check(bird.generate_creature(), "NPC must generate")
	var enemy := Node3D.new()
	enemy.set_script(CHARACTER)
	enemy.faction_id = 0
	enemy.require_head_and_torso_connectivity = false
	root.add_child(enemy)
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso])
	target.max_hp = 10000.0
	target.armor = 0.0
	target.freeze = true
	target.left_distance = 1.5
	target.right_distance = 1.5
	target.top_distance = 1.5
	target.bottom_distance = 1.5
	target.collision_thickness = 3.0
	enemy.add_child(target)
	target.global_position = Vector3(12, 2, 0)
	await frames(120)
	var flight := bird.get_node("BirdFlightController3D")
	flight._set_state(flight.State.GROUNDED, "test_ground_start")
	brain.enabled = true
	brain.move_to_node(target)
	await frames(3)
	check(brain._navigation_map_is_ready(), "NPC must use the level navigation map")
	check(not brain.get_movement_direction().is_zero_approx(), "Grounded NPC must produce a navigation movement direction")
	brain.resume_autonomous()
	var dive := bird.get_node("BirdDiveAttackController3D")
	dive.diagnostic_logging = true
	brain.enabled = true
	var airborne := false
	var aiming := false
	var cone_seen := false
	var pullup := false
	var preference_start_checked := false
	for index: int in range(1800):
		await physics_frame
		airborne = airborne or flight.is_airborne()
		aiming = aiming or dive.is_aiming()
		if dive.is_aiming() and not preference_start_checked:
			var preference: Dictionary = brain._attack_preference_check(target)
			check(preference.ready or preference.fallback_allowed, "NPC must respect attack preference before starting, except after its bounded wait")
			preference_start_checked = true
		cone_seen = cone_seen or not dive._temporary_weapons.is_empty()
		if not dive._temporary_weapons.is_empty():
			var weapon: SampleWeapon3D = dive._temporary_weapons[0]
			var own_torso: PhysicalBodyPart3D = flight._torso
			check(is_zero_approx(weapon.apply_contact_damage(own_torso, 10000.0)), "Cone weapon must never damage its owning generated character")
		pullup = pullup or dive.phase == dive.Phase.PULLING_UP
		if target.current_hp < target.max_hp and pullup: break
	check(airborne, "Ground-start NPC must take off autonomously")
	check(aiming, "NPC must automatically select an enemy and aim")
	check(cone_seen, "NPC dive must create a temporary cone weapon")
	check(target.current_hp < target.max_hp, "Autonomous NPC dive must damage the enemy")
	check(pullup, "Autonomous NPC must pull up after impact")
	dive.cancel_action(&"test_cleanup")
	await frames(2)
	check(dive._temporary_weapons.is_empty(), "Cancellation must remove cone weapons")
	check(not bird.get_node("GeneratedParts").find_children("DiveWeaponCone", "CollisionShape3D", true, false).size(), "No attack shapes may remain after cancellation")
	brain.enabled = false
	brain._route_frame = -1
	var query_count: int = brain._route_queries
	brain._flight_route_hit()
	brain._flight_route_hit()
	brain._flight_route_hit()
	check(brain._route_queries == query_count + 1, "Height and direction queries in one frame must share one ray cast")
	await physics_frame
	brain._flight_route_hit()
	check(brain._route_queries == query_count + 2, "New physics frames must refresh the ray result")
	var previous_mask: int = brain.flight_obstacle_mask
	brain.flight_obstacle_mask = 0
	brain._flight_route_hit()
	check(brain._route_queries == query_count + 3, "Changing obstacle mask must invalidate the cached ray")
	brain.flight_obstacle_mask = previous_mask
	var extra_part := PART.instantiate() as PhysicalBodyPart3D
	extra_part.freeze = true
	extra_part.position = Vector3(50, 10, 50)
	enemy.add_child(extra_part)
	brain._flight_route_hit()
	check(extra_part.get_rid() in brain._route_excluded, "Added enemy parts must enter ray exclusions immediately")
	extra_part.queue_free()
	await process_frame
	brain._flight_route_hit()
	check(brain._route_excluded.size() == bird.get_physical_body_rids().size() + enemy.get_physical_body_rids().size(), "Freed enemy parts must not leave stale ray exclusions")
	brain.set_performance_tracking_enabled(true)
	brain._set_agent_target(Vector3(4, 0, 2))
	var projections: int = brain._performance_map_projections
	brain._set_agent_target(Vector3(4.1, 0, 2))
	check(brain._performance_map_projections == projections, "Sub-threshold target motion must reuse the navigation projection")
	brain._set_agent_target(Vector3(4.5, 0, 2))
	check(brain._performance_map_projections == projections + 1, "Significant target motion must refresh navigation")
	var old_rids: Array[RID] = bird.get_physical_body_rids()
	var old_revision: int = bird.get_body_parts_revision()
	check(bird.generate_creature(), "Runtime regeneration must remain available")
	check(bird.get_body_parts_revision() > old_revision, "Regeneration must invalidate body caches")
	for rid: RID in bird.get_physical_body_rids(): check(rid not in old_rids, "Regenerated character must not return retired physics RIDs")
	brain._flight_route_hit()
	for rid: RID in old_rids: check(rid not in brain._route_excluded, "Regeneration must also refresh cached route exclusions")
	print("[bird_npc_test] hp=", target.current_hp, " state=", brain.get_state_diagnostics())
	print("BIRD_NPC_FAILED" if failed else "BIRD_NPC_PASSED")
	quit(1 if failed else 0)
