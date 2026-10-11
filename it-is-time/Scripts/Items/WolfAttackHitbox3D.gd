extends SampleWeapon3D
## Query-only weapon. Damage uses estimated contact impulse, as with ChargeWeapon3D.
var body: PhysicalBodyPart3D
var box := BoxShape3D.new()
var center_offset := Vector3.ZERO
var impulse_multiplier := 1.0
var hit_ragdoll_duration := 1.0
var _previous_pose := Transform3D.IDENTITY
var _has_previous := false
var hit_count := 0
var _excluded: Array[RID] = []
var _debug_shape: CollisionShape3D

func setup(part: PhysicalBodyPart3D, character: Node, size: Vector3, offset: Vector3, multiplier: float, ragdoll_duration: float = 1.0) -> void:
	body = part
	freeze = true
	collision_layer = 0
	collision_mask = 0
	can_be_picked_up = false
	box.size = size.max(Vector3.ONE*0.02)
	center_offset = offset
	impulse_multiplier = multiplier
	hit_ragdoll_duration = ragdoll_duration
	set_wielder(character, character.get_faction_id())
	for other: RigidBody3D in character._get_physical_body_parts(): _excluded.append(other.get_rid())
	_debug_shape = CollisionShape3D.new()
	_debug_shape.name = "DamageBox"
	_debug_shape.shape = box
	_debug_shape.disabled = true
	_debug_shape.set_meta(&"equipped_item",self)
	add_child(_debug_shape)
	begin_damage_swing()

func pose() -> Transform3D:
	return Transform3D(body.global_basis.orthonormalized(),body.to_global(center_offset))

func update_hitbox(delta: float, damaging: bool) -> void:
	if not is_instance_valid(body) or body.is_broken: return
	var current := pose()
	global_transform = current
	var samples := 1
	if _has_previous:
		samples = clampi(ceili(current.origin.distance_to(_previous_pose.origin)/maxf(minf(box.size.x,box.size.y)*0.5,0.05)),1,8)
		var angle := _previous_pose.basis.get_rotation_quaternion().angle_to(current.basis.get_rotation_quaternion())
		samples = maxi(samples,clampi(ceili(angle/deg_to_rad(5.0)),1,8))
	if damaging:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = box
		query.exclude = _excluded
		query.collision_mask = 0xFFFFFFFF
		for index: int in range(1,samples+1):
			query.transform = _previous_pose.interpolate_with(current,float(index)/samples) if _has_previous else current
			for contact: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,64):
				var other := contact.collider as PhysicalBodyPart3D
				if other == null or other.is_broken or other._is_friendly_weapon(self) or _swing_hit_parts.has(other.get_instance_id()): continue
				var point: Vector3 = query.transform.origin
				var velocity := body.linear_velocity+body.angular_velocity.cross(point-body.global_position)
				if _has_previous:
					var sweep_velocity := (current.origin-_previous_pose.origin)/maxf(delta,0.0001)
					if sweep_velocity.length_squared() > velocity.length_squared(): velocity = sweep_velocity
				var other_velocity := other.linear_velocity+other.angular_velocity.cross(point-other.global_position)
				var normal := (other.global_position-point).normalized()
				var closing_speed := maxf((velocity-other_velocity).dot(normal),0.0)
				var reduced_mass := body.mass*other.mass/maxf(body.mass+other.mass,0.001)
				var impulse := closing_speed*reduced_mass*impulse_multiplier
				var damage := apply_contact_damage(other,impulse)
				if damage_logging_enabled:
					print("[wolf_attack_hit] weapon=",name," attached_part=",body.name," target=",other.get_path()," estimated_impulse=",impulse," hp_damage=",damage)
				if damage > 0.0: hit_count += 1
	_previous_pose = current
	_has_previous = true

func dispose() -> void:
	end_damage_swing()
	queue_free()

func apply_contact_damage(other: PhysicalBodyPart3D, impulse: float) -> float:
	if not is_instance_valid(body) or body.is_broken or not swing_damage_active: return 0.0
	var victim: Node = preload("res://Scripts/Player/PlayerControlContext.gd").character_of(other)
	var compare_mass := hit_ragdoll_duration > 0.0 and is_instance_valid(victim) and is_instance_valid(wielder_character) and victim.has_method("apply_timed_hit_ragdoll")
	var own_mass := _character_mass(wielder_character) if compare_mass else 0.0
	var victim_mass := _character_mass(victim) if compare_mass else 0.0
	var damage := super.apply_contact_damage(other,impulse)
	if damage > 0.0 and compare_mass and victim.is_combat_alive():
		if victim_mass < own_mass:
			victim.apply_timed_hit_ragdoll(hit_ragdoll_duration)
			var attacks := wielder_character.get_node_or_null("WolfAttackController3D")
			if attacks != null: attacks.log_event(&"Hit",&"ragdoll_applied",{"target":victim.get_path(),"attached_part":body.name,"wolf_mass":own_mass,"target_mass":victim_mass,"duration":hit_ragdoll_duration,"damage":damage})
	return damage

func _character_mass(character: Node) -> float:
	var total := 0.0
	for part: RigidBody3D in character._get_physical_body_parts():
		if is_instance_valid(part) and not part.is_broken: total += part.mass
	return total
