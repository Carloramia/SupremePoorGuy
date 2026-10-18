extends RefCounted

static func intersect(space: PhysicsDirectSpaceState3D, ray_from: Vector3, ray_to: Vector3,
		collision_mask: int, terrain_group: StringName, maximum_exclusions: int,
		performance: RefCounted) -> Dictionary:
	var excluded: Array[RID] = []
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for attempt: int in range(maximum_exclusions):
		performance.count(&"terrain_ray_queries")
		var result := space.intersect_ray(query)
		if result.is_empty(): return {}
		var collider := result.get("collider") as Node
		if collider is StaticBody3D or (collider != null and not terrain_group.is_empty() and collider.is_in_group(terrain_group)):
			return result
		if not collider is CollisionObject3D: return {}
		excluded.append(collider.get_rid())
		query.exclude = excluded
	return {}
