extends SceneTree
const GUARD = preload("res://Scripts/Creatures/WolfClawCollisionGuard3D.gd")
class AttackOwner:
	extends Node
	var active := true
var failed := false

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	var owner := AttackOwner.new()
	root.add_child(owner)
	var body := RigidBody3D.new()
	body.freeze = true
	body.collision_layer = 4
	body.collision_mask = 8
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	root.add_child(body)
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 8
	obstacle.collision_mask = 0
	var obstacle_shape := CollisionShape3D.new()
	obstacle_shape.shape = BoxShape3D.new()
	obstacle.add_child(obstacle_shape)
	root.add_child(obstacle)
	var guard := GUARD.new()
	body.add_child(guard)
	guard.acquire(body,owner,[])
	await create_timer(0.05).timeout
	check(body.collision_layer == 0 and body.collision_mask == 0,"Active claw has no physical contacts")
	check(guard._overlaps_external_body(),"Restoration detects the original collision mask even with obstacle mask zero")
	body.add_collision_exception_with(obstacle)
	check(not guard._overlaps_external_body(),"Existing collision exceptions are preserved")
	body.remove_collision_exception_with(obstacle)
	guard.release()
	await create_timer(0.05).timeout
	check(body.collision_layer == 0,"Overlapping external geometry delays restoration")
	# A new attack reuses the original snapshot while restoration is pending.
	guard.acquire(body,owner,[])
	guard.release()
	owner.free()
	obstacle.position.x = 10.0
	await create_timer(0.05).timeout
	check(body.collision_layer == 4 and body.collision_mask == 8,"Removal of the attack still restores original filters after separation")
	check(not is_instance_valid(guard),"Restoration releases the guard")
	body.free()
	obstacle.free()
	print("WOLF_CLAW_COLLISIONS ","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
