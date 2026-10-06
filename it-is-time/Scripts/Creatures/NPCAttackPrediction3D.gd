extends RefCounted
## Read-only collision queries. No copied bodies, forces, or temporary scenes.
static func shapes(body: Node3D) -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	for child: Node in body.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape != null: result.append(child)
	return result

static func velocity(target: Node3D) -> Vector3:
	return target.linear_velocity if target is RigidBody3D else Vector3.ZERO

static func target_hit(space: PhysicsDirectSpaceState3D, shape: Shape3D, pose: Transform3D, target: Node3D, time: float, margin: float) -> bool:
	if not target is PhysicsBody3D: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = pose
	query.transform.origin -= velocity(target)*time
	query.margin = margin
	query.collision_mask = target.collision_layer
	for row: Dictionary in space.intersect_shape(query,64):
		if row.collider == target: return true
	return false

static func surface_distance(point: Vector3, target: Node3D, time: float) -> float:
	var best := INF
	for collision: CollisionShape3D in shapes(target):
		var pose := collision.global_transform
		pose.origin += velocity(target)*time
		var bounds := collision.shape.get_debug_mesh().get_aabb()
		var local := pose.affine_inverse()*point
		var closest := local.clamp(bounds.position,bounds.end)
		best = minf(best, point.distance_to(pose*closest))
	return best

static func terrain_blocked(space: PhysicsDirectSpaceState3D, shape: Shape3D, pose: Transform3D, excluded: Array[RID]) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = pose
	query.exclude = excluded
	for row: Dictionary in space.intersect_shape(query,32):
		if row.collider is StaticBody3D: return true
	return false
