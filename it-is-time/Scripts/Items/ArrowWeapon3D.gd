extends "res://Scripts/Items/SampleWeapon3D.gd"
## One swept flight query owns impacts, avoiding duplicate solver/contact damage.
const HALF_LENGTH := 1.8
signal impacted(target: Object, damage: float, impulse: float)
var in_flight := false
var elapsed := 0.0
var lifetime := 6.0
var previous_tip := Vector3.ZERO
var excluded: Array[RID] = []
var _flight_shape := SphereShape3D.new()

static func solve_velocity(origin: Vector3, target: Vector3, speed: float, gravity: Vector3) -> Dictionary:
	var offset := target-origin
	if not origin.is_finite() or not target.is_finite() or not is_finite(speed) or speed<=0.0 or offset.length()<0.001: return {}
	var time := offset.length()/speed
	if gravity.length_squared()>0.00001:
		var a := 0.25*gravity.length_squared()
		var b := -(offset.dot(gravity)+speed*speed)
		var c := offset.length_squared()
		var discriminant := b*b-4.0*a*c
		if discriminant<0.0: return {}
		time = sqrt(2.0*c/(-b+sqrt(discriminant)))
	return {"velocity":offset/time-gravity*time*0.5,"time":time}

static func gravity_vector() -> Vector3:
	return Vector3(ProjectSettings.get_setting("physics/3d/default_gravity_vector"))*float(ProjectSettings.get_setting("physics/3d/default_gravity"))

func launch(character: Node3D, velocity: Vector3, seconds: float) -> void:
	set_wielder(character,character.get_faction_id())
	can_be_picked_up = false
	lifetime = maxf(seconds,0.1)
	elapsed = 0.0
	# The rigid body integrates gravity; sweeps resolve hits and transfer momentum explicitly.
	collision_layer = 0
	collision_mask = 0
	freeze = false
	gravity_scale = 1.0
	# The ballistic predictor assumes no drag, including the World's default damping.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	lock_rotation = true
	linear_velocity = velocity
	excluded = [get_rid()]
	if character.has_method("get_physical_body_rids"): excluded.append_array(character.get_physical_body_rids())
	_flight_shape.radius = 0.06
	previous_tip = global_position+global_basis.x*HALF_LENGTH
	in_flight = true
	begin_damage_swing()
	add_to_group(&"bow_projectiles")

func _physics_process(delta: float) -> void:
	if not is_in_group(&"bow_projectiles"): return
	elapsed += delta
	if elapsed>=lifetime: queue_free(); return
	if not in_flight: return
	if not linear_velocity.is_zero_approx(): global_basis = Basis(Quaternion(Vector3.RIGHT,linear_velocity.normalized()))
	var tip := global_position+global_basis.x*HALF_LENGTH
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _flight_shape
	query.transform.origin = previous_tip
	query.collision_mask = 0xFFFFFFFF
	query.exclude = excluded
	var space := get_world_3d().direct_space_state
	var overlaps := space.intersect_shape(query,1)
	var contact: Dictionary = {}
	if not overlaps.is_empty():
		contact = overlaps[0]
	else:
		query.motion = tip-previous_tip
		var sweep := space.cast_motion(query)
		if sweep[0]<1.0:
			query.transform.origin += query.motion*minf(sweep[1]+0.001,1.0)
			query.motion = Vector3.ZERO
			contact = space.get_rest_info(query)
			if not contact.is_empty(): contact["collider"] = instance_from_id(contact.collider_id)
	if not contact.is_empty(): _impact(contact,query.transform.origin)
	previous_tip = tip

func _impact(contact: Dictionary, point: Vector3) -> void:
	if not in_flight: return
	in_flight = false
	var target: Object = contact.get("collider")
	var impulse := mass*linear_velocity.length()
	var damage := 0.0
	if target is RigidBody3D:
		var relative: Vector3 = linear_velocity-target.linear_velocity
		impulse = relative.length()/(1.0/mass+(0.0 if target.freeze else 1.0/target.mass))
		if target is PhysicalBodyPart3D: damage = apply_contact_damage(target,impulse)
		if is_instance_valid(target) and not target.freeze: target.apply_impulse(relative.normalized()*impulse,point-target.global_position)
	global_position = point-global_basis.x*HALF_LENGTH
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	end_damage_swing()
	impacted.emit(target if is_instance_valid(target) else null,damage,impulse)

func get_attack_debug_shapes() -> Array[Dictionary]:
	if not in_flight: return []
	return [{"shape":_flight_shape,"transform":Transform3D(Basis.IDENTITY,global_position+global_basis.x*HALF_LENGTH),"active":true}]
