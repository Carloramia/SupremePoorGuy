extends SceneTree
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const DATA = preload("res://Scripts/VFX/StompShockwaveData.gd")
const WAVE = preload("res://Scenes/VFX/StompShockwave3D.tscn")
const MOVEMENT = preload("res://Scripts/Creatures/LegStepMovementControllerBase3D.gd")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func actor(id: int, at: Vector3, frozen: bool = true) -> Node3D:
	var node := Node3D.new()
	node.set_script(CHARACTER)
	node.faction_id = id
	var body := PhysicalBodyPart3D.new()
	body.name = "Torso"
	body.tags.append(PhysicalBodyPart3D.BodyPartTag.Torso)
	body.max_hp = 1000.0
	body.armor = 10.0
	body.gravity_scale = 0.0
	body.freeze = frozen
	body.collision_mask = 0
	body.damage_number_scene = null
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	body.add_child(sprite)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3.ONE
	shape.name = "CollisionShape3D"
	body.add_child(shape)
	node.add_child(body)
	root.add_child(node)
	node.position = at
	return node
func wave(source: Node3D, data: Resource, normal: Vector3 = Vector3.UP, measured_impulse: float = 55.0) -> Node3D:
	var node := WAVE.instantiate()
	node.setup(data,source,Vector3.ZERO,normal,measured_impulse)
	root.add_child(node)
	return node
func run() -> void:
	root.get_node("RuntimeConsole")._damage_tracking_enabled = true
	var source := actor(0,Vector3.ZERO)
	var ally := actor(0,Vector3(1,0.5,0))
	var enemy := actor(1,Vector3(3,0.5,0))
	var far := actor(1,Vector3(20,0.5,0))
	var airborne := actor(1,Vector3(2,4,0))
	var diagonal_far := actor(1,Vector3(7,8,0))
	var data := DATA.new()
	data.radius = 8.0
	data.duration = 1.0
	data.edge_strength = 1.0
	data.outward_speed = 0.0
	data.upward_speed = 0.0
	data.require_line_of_sight = false
	var effect := wave(source,data)
	check(effect.get_child_count() == 1,"Wave must create an independent visual mesh")
	check(effect.global_basis.y.is_equal_approx(Vector3.UP),"Ring must align to the contact normal")
	for frame: int in range(8): await physics_frame
	check(enemy.get_node("Torso").current_hp == 1000.0,"Enemy must not be damaged before the expanding wave reaches it")
	for frame: int in range(42): await physics_frame
	var expected_damage: float = root.get_node("DamageService").calculate_damage(55.0,10.0)
	check(enemy.get_node("Torso").current_hp == 1000.0-expected_damage,"Measured impulse must use global damage rules and Armor, once per wave")
	check(effect.hit_count == 2,"Sphere must also hit an airborne enemy inside its 3D radius")
	check(ally.get_node("Torso").current_hp == 1000.0 and source.get_node("Torso").current_hp == 1000.0,"Self and friendly factions must be ignored")
	check(far.get_node("Torso").current_hp == 1000.0 and diagonal_far.get_node("Torso").current_hp == 1000.0,"Enemies beyond the spherical radius must be ignored")
	check(airborne.get_node("Torso").current_hp == 1000.0-expected_damage,"Airborne enemies must receive spherical wave damage")
	for frame: int in range(20): await physics_frame
	check(not is_instance_valid(effect),"Wave must clean up after its duration")
	wave(source,data)
	for frame: int in range(65): await physics_frame
	check(enemy.get_node("Torso").current_hp == 1000.0-expected_damage*2.0,"A second foot's wave may damage the same target once again")
	# A terrain wall blocks both damage and impulse.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.2,4,10)
	wall.add_child(shape)
	wall.position = Vector3(1.5,1,0)
	root.add_child(wall)
	await physics_frame
	data.require_line_of_sight = true
	wave(source,data)
	for frame: int in range(65): await physics_frame
	check(enemy.get_node("Torso").current_hp == 1000.0-expected_damage*2.0,"Obstacle must block shockwave damage")
	wall.free()
	# Actual impulse and release of the real movement controller's stance pin.
	enemy.free()
	var moving := actor(1,Vector3(3,0.5,0),false)
	var controller := Node.new()
	controller.set_script(MOVEMENT)
	controller.input_enabled = false
	moving.add_child(controller)
	controller.set_physics_process(false)
	var pin := Generic6DOFJoint3D.new()
	controller.add_child(pin)
	controller._support_pins[moving.get_node("Torso")] = {"joint":pin}
	data.outward_speed = 3.0
	data.upward_speed = 2.0
	var impact_wave := wave(source,data)
	for frame: int in range(25): await physics_frame
	var body := moving.get_node("Torso") as RigidBody3D
	print("IMPACT_TEST hits=",impact_wave.hit_count," position=",body.global_position," velocity=",body.linear_velocity," release=",controller.get_adhesion_release_time_remaining())
	check(body.linear_velocity.x > 2.0 and body.linear_velocity.y > 1.0,"Shockwave must provide outward/upward physical impulse")
	check(controller._support_pins.is_empty() and controller.get_adhesion_release_time_remaining() > 0.0,"Impact must release ground pins and adhesion temporarily")
	var tilted := Vector3(0,1,1).normalized()
	var slope_wave := wave(source,data,tilted)
	check(slope_wave.global_basis.y.is_equal_approx(tilted),"Visual must align with sloped surfaces")
	slope_wave.free()
	var low_impact := wave(source,data,Vector3.UP,12.0)
	check(low_impact.raw_impact_damage < impact_wave.raw_impact_damage and low_impact.raw_impact_damage == root.get_node("DamageService").calculate_raw_damage(12.0),"Lower measured impulses must produce lower raw damage according to the global rules")
	low_impact.free()
	var zero_impact := wave(source,data,Vector3.UP,0.0)
	check(zero_impact.raw_impact_damage == 0.0,"No measured impulse must not manufacture fixed damage")
	zero_impact.free()
	print("STOMP_SHOCKWAVE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
