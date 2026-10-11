extends Node
## Lives on the physical part so cancellation or removal of the attack cannot lose restoration.
var body: RigidBody3D
var owner_module: WeakRef
var original_layer := 0
var original_mask := 0
var excluded: Array[RID] = []
var released := false

func acquire(part: RigidBody3D, module: Node, own_rids: Array[RID]) -> void:
	if body == null:
		body = part
		original_layer = body.collision_layer
		original_mask = body.collision_mask
	owner_module = weakref(module)
	excluded = own_rids.duplicate()
	released = false
	body.collision_layer = 0
	body.collision_mask = 0
	process_mode = Node.PROCESS_MODE_PAUSABLE

func release() -> void:
	released = true

func _overlaps_external_body() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var exclusions: Array[RID] = excluded.duplicate()
	if not exclusions.has(body.get_rid()): exclusions.append(body.get_rid())
	for other: PhysicsBody3D in body.get_collision_exceptions():
		if is_instance_valid(other): exclusions.append(other.get_rid())
	query.exclude = exclusions
	query.collision_mask = 0xFFFFFFFF
	for shape_owner: int in body.get_shape_owners():
		if body.is_shape_owner_disabled(shape_owner): continue
		query.transform = body.global_transform * body.shape_owner_get_transform(shape_owner)
		for index: int in range(body.shape_owner_get_shape_count(shape_owner)):
			query.shape = body.shape_owner_get_shape(shape_owner,index)
			var contacts := body.get_world_3d().direct_space_state.intersect_shape(query,128)
			if contacts.size() == 128: return true
			for contact: Dictionary in contacts:
				var other := contact.collider as PhysicsBody3D
				if other == null or other.get_collision_exceptions().has(body): continue
				if (original_mask & other.collision_layer) != 0 or (original_layer & other.collision_mask) != 0: return true
	return false

func _physics_process(_delta: float) -> void:
	var module: Node = owner_module.get_ref() if owner_module != null else null
	var broken: bool = body is PhysicalBodyPart3D and body.is_broken
	if not released and not broken and is_instance_valid(module) and module.active: return
	if not broken and _overlaps_external_body(): return
	body.collision_layer = original_layer
	body.collision_mask = original_mask
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(body):
		body.collision_layer = original_layer
		body.collision_mask = original_mask
