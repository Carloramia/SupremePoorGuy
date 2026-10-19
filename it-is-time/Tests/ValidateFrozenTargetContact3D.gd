extends SceneTree
const PART = preload("res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn")
var results: Array[float] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	root.get_node("CombatAudio").settings.enabled = false
	for frozen: bool in [true,false]:
		var target := PART.instantiate() as PhysicalBodyPart3D
		target.mass_based_health = false
		target.max_hp = 1000.0
		target.armor = 0.0
		target.gravity_scale = 0.0
		target.freeze = frozen
		target.position = Vector3(0,5,0)
		root.add_child(target)
		var weapon := SampleWeapon3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		weapon.add_child(shape)
		weapon.gravity_scale = 0.0
		weapon.position = Vector3(-3,5,0)
		root.add_child(weapon)
		weapon.begin_damage_swing()
		weapon.linear_velocity = Vector3(20,0,0)
		for frame: int in 30: await physics_frame
		results.append(1000.0-target.current_hp)
		weapon.free(); target.free()
		await physics_frame
	print("FROZEN_CONTACT_PROBE frozen_damage=",results[0]," live_damage=",results[1])
	assert(results[0] == 0.0 and results[1] > 0.0,"Only live targets run the victim-side contact damage callback")
	print("FROZEN_CONTACT_PROBE_PASSED")
	quit()
