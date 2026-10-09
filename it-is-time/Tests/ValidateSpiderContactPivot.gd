extends SceneTree

class TestFoot extends RigidBody3D:
	var is_slipping: bool = false

class PivotController extends "res://Scripts/Creatures/SpiderLegStepMovementController3D.gd":
	var terrain: StaticBody3D
	func _chain_is_intact(_leg: RigidBody3D) -> bool: return true
	func is_leg_grounded(_leg: RigidBody3D) -> bool: return true
	func _get_surface_below_leg(leg: RigidBody3D, _distance: float) -> Dictionary:
		return {"position": _get_foot_world_position(leg), "normal": Vector3.UP, "collider": terrain}

var failed := false

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var terrain := StaticBody3D.new()
	level.add_child(terrain)
	var foot := TestFoot.new()
	foot.gravity_scale = 0.0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 4.0, 0.2)
	collision.shape = shape
	foot.add_child(collision)
	level.add_child(foot)
	foot.rotation.z = PI / 4.0
	foot.position.y = 2.0
	var movement := PivotController.new()
	movement.terrain = terrain
	level.add_child(movement)
	movement.set_physics_process(false)
	await physics_frame
	movement._update_support_foot_lock(foot, Vector3.UP)
	check(movement._support_pins.has(foot), "A grounded foot must receive a contact pivot")
	if movement._support_pins.has(foot):
		var entry: Dictionary = movement._support_pins[foot]
		var anchor: Vector3 = movement._support_anchors[foot]
		var start := foot.global_position
		check(anchor.distance_to(start) > 1.9, "Pin must be on the toe, not at the body centre")
		for tick: int in 60:
			foot.apply_torque(Vector3(0, 0, 0.5))
			await physics_frame
		var point := foot.to_global(entry.foot_local_anchor)
		check(point.distance_to(anchor) < 0.04, "The same material contact point must remain anchored while rotating")
		check(foot.global_position.distance_to(start) > 0.05, "The leg centre must be allowed to move around the contact pivot")
		check(float(movement.get_support_foot_diagnostics(foot).drift) < 0.04, "Logs must measure contact drift instead of centre movement")
		check(movement._get_ground_contact_velocity(foot, {"collider": terrain}).length() < foot.linear_velocity.length(), "Pivot rotation must not be reported as centre-speed sliding")
		var torso := RigidBody3D.new()
		torso.freeze = true
		level.add_child(torso)
		movement._chains[foot] = {"root": torso}
		var stance: Dictionary = movement._get_spider_stance_travel(foot, Vector3.RIGHT)
		check(is_zero_approx(stance.progress), "Touchdown pose must start a new stance")
		foot.position.x += 0.2
		check(is_zero_approx(movement._get_spider_stance_travel(foot, Vector3.RIGHT).progress), "Lower-leg centre displacement must not consume stance travel")
		torso.position.x += 0.3
		check(is_equal_approx(movement._get_spider_stance_travel(foot, Vector3.RIGHT).progress, 0.3), "Root travel relative to the ground anchor must consume stance travel")
		foot.position.x -= 0.2
		var support_points := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
		check(is_zero_approx(movement._support_polygon_error(support_points, Vector2.ZERO)), "A surrounding support polygon must contain the centre")
		check(movement._support_polygon_error(PackedVector2Array([Vector2(1, -1), Vector2(1, 1)]), Vector2.ZERO) > 0.9, "One-sided contacts must not count as balanced support")
		movement._turn_planning_active = true
		movement._update_support_foot_lock(foot, Vector3.UP)
		check(not movement._support_pins.has(foot), "Turning must release the pivot")
		movement._turn_planning_active = false
		movement._update_support_foot_lock(foot, Vector3.UP)
		foot.is_slipping = true
		movement._update_support_foot_lock(foot, Vector3.UP)
		check(not movement._support_pins.has(foot), "Slipping must release the pivot")
		foot.is_slipping = false
		foot.linear_velocity = Vector3(1.0, 0.0, 0.0)
		foot.angular_velocity = Vector3.ZERO
		movement._active_leg = foot
		movement._step_state = movement.StepState.MOVING
		movement._step_has_lifted = true
		movement._step_target = foot.global_position + Vector3(100, 0, 0)
		movement._active_steps.append(movement._current_step)
		movement._update_active_step(1.0 / 60.0)
		check(movement._current_step.extra.has("spider_touchdown"), "A returning foot must start contact braking immediately")
		check(movement._step_target.is_equal_approx(foot.global_position), "Touchdown must discard the obsolete distant target")
		check(movement._tracking_force.x < 0.0, "Touchdown must brake instead of pursuing the target")
		check(movement._keep_touchdown_support_pin(foot), "Contact pivot must survive the landing phase")
		foot.linear_velocity = Vector3.ZERO
		for tick: int in 3: movement._update_active_step(1.0 / 60.0)
		check(movement._step_state == movement.StepState.IDLE and movement._failed_step_count == 0, "Stable actual contact must complete the step regardless of the old target")
		movement._release_support_pin(foot)
		movement._chains[foot] = {"root": torso, "bodies": [foot, torso]}
		movement._active_leg = foot
		movement._step_state = movement.StepState.MOVING
		movement._step_start = foot.global_position
		movement._step_start.y -= 2.0
		torso.linear_velocity = Vector3.RIGHT
		foot.linear_velocity = Vector3.RIGHT
		movement._step_has_lifted = false
		movement._current_step.extra["spider_liftoff_elapsed"] = 0.8
		movement._update_active_step(1.0 / 60.0)
		var assist: Dictionary = movement._current_step.extra.spider_liftoff
		check(movement._tracking_position_error.y > 0.0, "A raised centre with a grounded toe must still request upward clearance")
		check(absf(movement._tracking_force.x) < 0.001, "Liftoff must not brake a foot already travelling with its root")
		check(assist.assist_force.y > 0.0 and assist.assist_force.length() <= foot.mass * movement.liftoff_assist_acceleration + 0.001, "Stalled liftoff assistance must stay within its mass-scaled acceleration budget")
		movement._update_active_step(0.3)
		check(movement._step_state == movement.StepState.IDLE and movement._failed_step_count == 1, "Liftoff assistance must retain a finite timeout")
	level.free()
	if not failed: print("PASS: Spider toe stays anchored while its body rotates; turning and slipping release the pin.")
	quit(1 if failed else 0)
