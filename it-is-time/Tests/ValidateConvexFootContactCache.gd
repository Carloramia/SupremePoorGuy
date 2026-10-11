extends SceneTree

const CONTROLLER = preload("res://Scripts/Creatures/LegStepMovementControllerBase3D.gd")
const PART = preload("res://Scenes/Creatures/Bodyparts/Spider/FrameFitted/Legs/Left_1/LowerLeg.tscn")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func reference(collision: CollisionShape3D, up: Vector3, tolerance: float) -> Vector3:
	var lowest := INF
	for point: Vector3 in collision.shape.points:
		lowest = minf(lowest, collision.to_global(point).dot(up))
	var sum := Vector3.ZERO
	var count := 0
	for point: Vector3 in collision.shape.points:
		var world := collision.to_global(point)
		if world.dot(up) <= lowest + tolerance:
			sum += world
			count += 1
	return sum / float(count) if count > 0 else collision.global_position

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var controller := CONTROLLER.new()
	root.add_child(controller)
	controller.set_physics_process(false)
	var part := PART.instantiate()
	part.freeze = true
	root.add_child(part)
	var collision: CollisionShape3D = part.get_node("CollisionShape3D")
	collision.shape = collision.shape.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91827
	for index: int in 50:
		part.transform = Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf(), rng.randf())), Vector3(rng.randf(), rng.randf(), rng.randf()))
		for up: Vector3 in [Vector3.UP, Vector3(0.2, 0.8, 0.4).normalized()]:
			for tolerance: float in [0.001, 0.00001]:
				check(controller._get_convex_foot_world_position(collision, up, tolerance).is_equal_approx(reference(collision, up, tolerance)), "Cached contact must retain the original lowest-point average")
	controller._movement_perf.set_enabled(true)
	controller._invalidate_convex_foot_cache()
	for index: int in 100: controller._get_convex_foot_world_position(collision, Vector3.UP, 0.00001)
	var stats: Dictionary = controller._movement_perf.consume()
	check(stats.counters.get(&"foot_contact_builds", 0) == 1 and stats.counters.get(&"foot_contact_cache_hits", 0) == 99, "Repeated same-frame queries must build only once")
	part.position += Vector3(1.0, 0.0, 0.0)
	check(controller._get_convex_foot_world_position(collision, Vector3.UP, 0.00001).is_equal_approx(reference(collision, Vector3.UP, 0.00001)), "Same-frame position changes must invalidate contact")
	var points: PackedVector3Array = collision.shape.points
	points.append(Vector3(0, -20, 0))
	collision.shape.points = points
	check(controller._get_convex_foot_world_position(collision, Vector3.UP, 0.00001).is_equal_approx(reference(collision, Vector3.UP, 0.00001)), "Same-frame point edits must invalidate contact")
	var replacement := ConvexPolygonShape3D.new()
	replacement.points = PackedVector3Array([Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(0,-1,1), Vector3(0,1,0)])
	collision.shape = replacement
	check(controller._get_convex_foot_world_position(collision, Vector3.UP, 0.00001).is_equal_approx(reference(collision, Vector3.UP, 0.00001)), "Replacing the collision resource must invalidate contact")
	controller._movement_perf.consume()
	await physics_frame
	controller._get_convex_foot_world_position(collision, Vector3.UP, 0.00001)
	check(controller._movement_perf.consume().counters.get(&"foot_contact_builds", 0) == 1, "A new physics frame must rebuild contact")
	part.free()
	controller.free()
	if not failed: print("PASS: Convex contact equivalence, cache hits, transform/shape/gravity/tolerance changes and frame invalidation.")
	quit(1 if failed else 0)
