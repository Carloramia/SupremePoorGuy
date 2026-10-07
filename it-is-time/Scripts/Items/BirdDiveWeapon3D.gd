class_name BirdDiveWeapon3D
extends SampleWeapon3D
## A weapon identity whose physical shape is rigidly attached to the Head.
var attached_shape: CollisionShape3D
var attached_head: PhysicalBodyPart3D

func attach_to_head(head: PhysicalBodyPart3D, length_ratio: float, radius_ratio: float) -> void:
	freeze = true
	collision_layer = 0
	collision_mask = 0
	can_be_picked_up = false
	attached_head = head
	var character: Node = preload("res://Scripts/Player/PlayerControlContext.gd").character_of(head)
	set_wielder(character, character.get_faction_id())
	head.broken.connect(_on_head_broken)
	attached_shape = CollisionShape3D.new()
	attached_shape.name = "DiveWeaponCone"
	attached_shape.shape = make_cone_shape(head, length_ratio, radius_ratio)
	attached_shape.set_meta(&"equipped_item", self)
	head.add_child(attached_shape)
	begin_damage_swing()

static func make_cone_shape(head: PhysicalBodyPart3D, length_ratio: float, radius_ratio: float) -> ConvexPolygonShape3D:
	var size: Vector3 = head.get_meta(&"generated_size", Vector3.ONE)
	var points := PackedVector3Array()
	var base_x := size.x * 0.45
	points.append(Vector3(base_x + size.x * length_ratio, 0, 0))
	var radius := maxf(size.y, size.z) * radius_ratio
	for index: int in range(16):
		var angle := TAU * index / 16.0
		points.append(Vector3(base_x, cos(angle) * radius, sin(angle) * radius))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape

func _on_head_broken(_source: Node) -> void:
	if is_instance_valid(attached_shape): attached_shape.set_deferred("disabled", true)
	end_damage_swing()

func apply_contact_damage(target: PhysicalBodyPart3D, impulse: float) -> float:
	if not is_instance_valid(attached_head) or attached_head.is_broken or not swing_damage_active: return 0.0
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
