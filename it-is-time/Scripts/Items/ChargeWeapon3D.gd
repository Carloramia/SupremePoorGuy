class_name ChargeWeapon3D
extends SampleWeapon3D
## Query-only damage box: never adds a solver shape to the character.
var attached_shape: CollisionShape3D
var attached_body: PhysicalBodyPart3D
var _previous_center := Vector3.ZERO
var _has_previous_center := false

func attach_to_body(body: PhysicalBodyPart3D, length_ratio: float, radius_ratio: float) -> void:
	freeze = true
	collision_layer = 0
	collision_mask = 0
	can_be_picked_up = false
	attached_body = body
	var character: Node = preload("res://Scripts/Player/PlayerControlContext.gd").character_of(body)
	set_wielder(character, character.get_faction_id())
	body.broken.connect(_on_body_broken)
	attached_shape = CollisionShape3D.new()
	attached_shape.name = "ChargeWeaponBox"
	var size: Vector3 = body.get_meta(&"generated_size", Vector3.ONE)
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size.x*length_ratio,0.1),maxf(size.y,0.1),maxf(maxf(size.y,size.z)*radius_ratio*2.0,0.1))
	attached_shape.shape = box
	attached_shape.disabled = true
	attached_shape.set_meta(&"equipped_item", self)
	add_child(attached_shape)
	attached_shape.top_level = true
	begin_damage_swing()

func update_ground_box(direction: float, terrain_mask: int, deal_damage: bool = true) -> void:
	if not is_instance_valid(attached_body) or not is_instance_valid(attached_shape): return
	var box := attached_shape.shape as BoxShape3D
	var body_size: Vector3 = attached_body.get_meta(&"generated_size",Vector3.ONE)
	var center := attached_body.global_position
	center.x += direction*(body_size.x*0.45 + box.size.x*0.5)
	var exclude: Array[RID] = [get_rid()]
	for part: RigidBody3D in wielder_character._get_physical_body_parts(): exclude.append(part.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(center+Vector3.UP*maxf(body_size.y,1.0),center-Vector3.UP*maxf(body_size.y*8.0,100.0),terrain_mask,exclude)
	var ground := {}
	# Dynamic characters are not terrain even if they share its collision layer.
	for attempt in range(32):
		ground = get_world_3d().direct_space_state.intersect_ray(ray)
		if ground.is_empty() or ground.collider is StaticBody3D: break
		var skipped := ray.exclude
		skipped.append(ground.rid)
		ray.exclude = skipped
	if ground.is_empty() or not ground.collider is StaticBody3D:
		_has_previous_center = false
		return
	center.y = ground.position.y + box.size.y*0.5
	attached_shape.global_transform = Transform3D(Basis.IDENTITY,center)
	if deal_damage and swing_damage_active:
		# Sweep the axis-aligned volume between ticks so fast charges do not skip thin parts.
		var query_box := BoxShape3D.new()
		query_box.size = box.size + (center-_previous_center).abs() if _has_previous_center else box.size
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = query_box
		query.transform = Transform3D(Basis.IDENTITY,(center+_previous_center)*0.5 if _has_previous_center else center)
		query.exclude = exclude
		query.collision_mask = 0xFFFFFFFF
		for contact: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,256):
			var target := contact.collider as PhysicalBodyPart3D
			if target == null or target.is_broken or target._is_friendly_weapon(self): continue
			var reduced_mass := attached_body.mass*target.mass/maxf(attached_body.mass+target.mass,0.001)
			var impulse := maxf((attached_body.linear_velocity-target.linear_velocity).dot(Vector3(direction,0,0)),0.0)*reduced_mass
			apply_contact_damage(target,impulse)
	_previous_center = center
	_has_previous_center = true

func _on_body_broken(_source: Node) -> void:
	if is_instance_valid(attached_shape): attached_shape.set_deferred("disabled", true)
	end_damage_swing()

func apply_contact_damage(target: PhysicalBodyPart3D, impulse: float) -> float:
	if not is_instance_valid(attached_body) or attached_body.is_broken or not swing_damage_active: return 0.0
	return super.apply_contact_damage(target, impulse)

func detach() -> void:
	if is_instance_valid(attached_shape):
		attached_shape.disabled = true
		attached_shape.queue_free()
	attached_shape = null
	end_damage_swing()

func _exit_tree() -> void:
	if is_instance_valid(attached_shape):
		attached_shape.set_deferred("disabled", true)
		attached_shape.queue_free()
