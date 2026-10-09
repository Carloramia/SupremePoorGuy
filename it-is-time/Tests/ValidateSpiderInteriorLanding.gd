extends SceneTree

const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Spider.tscn")
var failed := false

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var actor := ACTOR.instantiate()
	level.add_child(actor)
	await process_frame
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	actor.get_node("CreatureRecoveryStateMachine3D").set_physics_process(false)
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D: body.freeze = true
	await physics_frame
	for foot: RigidBody3D in movement.get_leg_parts():
		var torso: RigidBody3D = movement._chains[foot].root
		for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT]:
			torso.linear_velocity = direction * 0.8
			var hit: Dictionary = movement._find_structural_landing(foot, direction, 0.35)
			check(not hit.is_empty(), "Flat ground must provide an interior landing for " + str(foot.name))
			if hit.is_empty(): continue
			var frame: Dictionary = movement._structural_landing_frame(foot, direction, 0.35)
			var projection: float = (Vector3(hit.position) - Vector3(frame.reference)).dot(direction)
			check(projection >= frame.half * 0.2 - 0.001 and projection < frame.half, "Landing must leave rearward travel and forward margin")
			# Advance the root far enough to invalidate the old world target.
			movement._begin_leg_motion(foot, hit.position, Vector3.UP, direction)
			var catch_up: Dictionary = movement._current_step.extra.spider_catch_up
			check(catch_up.duration >= catch_up.nominal_duration, "Catch-up must not shorten the normal swing")
			check(catch_up.height > movement.get_leg_motion_profile(foot).lift, "Catch-up steps must have extra clearance")
			torso.position += direction * 0.3
			movement._refresh_structural_landing()
			var refreshed: Dictionary = movement._structural_landing_frame(foot, direction, movement._active_step_duration)
			var point: Vector3 = movement._current_step.extra.landing_surface_point
			var updated: float = (point - Vector3(refreshed.reference)).dot(direction)
			check(updated >= refreshed.half * 0.2 - 0.001 and updated < refreshed.half, "Airborne retargeting must follow root motion into the interior")
			movement.cancel_step(&"test_complete")
			torso.position -= direction * 0.3
			torso.linear_velocity = Vector3.ZERO
		# A physically grounded foot behind the interval must not count as an
		# effective step; release its slot and request supported recovery instead.
		var reference: Vector3 = movement._get_foot_world_position(foot)
		var verdict: Dictionary = movement._spider_landing_verdict(foot, reference + Vector3.RIGHT, {"reference": reference + Vector3.RIGHT, "direction": Vector3.RIGHT, "half": 0.3})
		check(not verdict.valid and not verdict.inside_interval, "Contact alone must not satisfy step completion")
		movement._begin_leg_motion(foot, reference + Vector3.RIGHT, Vector3.UP, Vector3.RIGHT)
		movement._current_step.extra.spider_completion = verdict
		movement._finish_current_step()
		check(movement._spider_recovery_steps.has(foot), "Early landing must queue a recovery without reporting successful touchdown")
		movement._begin_leg_motion(foot, reference + Vector3.RIGHT, Vector3.UP, Vector3.RIGHT)
		check(movement._current_step.extra.spider_catch_up.recovery, "Queued recovery must use its catch-up trajectory")
		var good: Dictionary = movement._spider_landing_verdict(foot, reference, {"reference": reference, "direction": Vector3.RIGHT, "half": 0.3})
		check(good.valid, "Contact at an interior target must satisfy completion")
		movement._current_step.extra.spider_completion = good
		movement._finish_current_step()
		check(not movement._spider_recovery_steps.has(foot), "Effective landing must clear recovery")
	actor.queue_free()
	await process_frame
	if not failed: print("PASS: Spider interior landing on both directions and airborne root-motion correction.")
	quit(1 if failed else 0)
