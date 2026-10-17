extends SceneTree
const ARROW = preload("res://Scenes/Items/Weapons/Arrow.tscn")
const FLIGHT = preload("res://Scripts/Items/ArrowWeapon3D.gd")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const TORSO = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn")
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func character(team: int, point: Vector3) -> Node3D:
	var actor := Node3D.new()
	actor.set_script(CHARACTER)
	actor.faction_id = team
	actor.require_head_and_torso_connectivity = false
	var part := TORSO.instantiate() as PhysicalBodyPart3D
	part.name = "Torso"
	part.freeze = true
	part.max_hp = 10000.0
	part.current_hp = 10000.0
	part.armor = 0.0
	actor.add_child(part)
	root.add_child(actor)
	actor.position = point
	return actor

func verify_impact(friendly: bool, wall: bool) -> void:
	# Own body lies directly on the shot line: the sweep must ignore all source parts.
	var source := character(1,Vector3(5,10,0))
	var enemy := character(1 if friendly else 2,Vector3(10,10,0))
	var body: PhysicalBodyPart3D = enemy.get_node("Torso")
	var obstacle: StaticBody3D
	if wall:
		obstacle = StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.1,5,5)
		shape.shape = box
		obstacle.add_child(shape)
		root.add_child(obstacle)
		obstacle.position = Vector3(8,10,0)
	var arrow := ARROW.instantiate() as FLIGHT
	arrow.freeze = true
	root.add_child(arrow)
	arrow.position = Vector3(0,10,0)
	var contacts: Array[Dictionary] = []
	arrow.impacted.connect(func(target: Object, damage: float, impulse: float) -> void: contacts.append({"target":target,"damage":damage,"impulse":impulse}))
	await physics_frame
	arrow.launch(source,Vector3(120,0,0),0.5)
	check(arrow.get_attack_debug_shapes().size()==1 and arrow.get_attack_debug_shapes()[0].shape is SphereShape3D,"Projectile visualization matches its actual swept tip collider")
	for tick: int in 20: await physics_frame
	check(contacts.size()==1,"One high-speed projectile creates exactly one impact")
	check(is_instance_valid(arrow) and not arrow.in_flight and arrow.freeze,"Impact ends flight and damage")
	check(body.current_hp==body.max_hp if friendly or wall else body.current_hp<body.max_hp,"Friendly filtering and terrain obstruction preserve HP; hostile hits damage")
	if wall and contacts.size()==1: check(contacts[0].target==obstacle,"A thin wall stops the arrow before the victim")
	if not wall and contacts.size()==1: check(contacts[0].target==body,"Source-body exclusion allows the arrow to reach the intended character")
	for tick: int in 20: await physics_frame
	check(not is_instance_valid(arrow),"Arrow lifetime cleans up impacted projectiles")
	source.free()
	enemy.free()
	if obstacle!=null: obstacle.free()
	await process_frame

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	for point: Vector3 in [Vector3(25,4,0),Vector3(-25,-3,1),Vector3(15,15,2)]:
		var solution := FLIGHT.solve_velocity(Vector3.ZERO,point,42.0,FLIGHT.gravity_vector())
		check(not solution.is_empty(),"Ballistic target must be reachable")
		if not solution.is_empty():
			var actual: Vector3 = Vector3(solution.velocity)*solution.time+FLIGHT.gravity_vector()*solution.time*solution.time*0.5
			check(actual.distance_to(point)<0.001,"Ballistic solver hits its mathematical target")
	check(FLIGHT.solve_velocity(Vector3.ZERO,Vector3(1000,1000,0),1.0,FLIGHT.gravity_vector()).is_empty(),"Unreachable ballistic targets are rejected")
	await verify_impact(false,false)
	await verify_impact(true,false)
	await verify_impact(false,true)
	print("BOW_PROJECTILES_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
