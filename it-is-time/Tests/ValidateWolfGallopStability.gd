extends SceneTree

class Command:
	extends Node
	func get_movement_direction() -> Vector3: return Vector3.RIGHT
	func is_fast_movement_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 100)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	for scene in ["Generate_Wolf", "Generate_Wolf_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var movement = actor.get_node("GeneratedLegStepMovementController3D")
		var data = movement.slow_gait_data.duplicate()
		data.target_speed = 8.0
		data.maximum_step_frequency = 4.0
		movement.slow_gait_data = data
		movement.fast_gait_data = data
		movement.input_enabled = true
		movement.recovery_control_active = false
		var command := Command.new()
		actor.add_child(command)
		movement.command_source = command
		movement._wolf_auto_gallop = true
		assert(movement._gallop_active())
		assert(movement._height_support_weight_share() >= 1.0)
		var originals := {}
		var total_mass := 0.0
		for body in actor.get_node("GeneratedParts").get_children():
			if body is RigidBody3D:
				originals[body] = body.global_transform
				body.global_position.y += 10.0
				total_mass += body.mass
		await physics_frame
		movement._begin_ground_probe_frame()
		movement._support_delta = 1.0 / 60.0
		movement.sub_torso_force_smoothing_time = 0.0
		movement._update_segment_metrics()
		for segment: Dictionary in movement._segments.values():
			segment.reference_height = Vector3(segment.torso_center).y + 1.0
			segment.support_blend = 1.0
		for foot: RigidBody3D in movement._legs:
			movement._gallop_contacts[foot] = {"time": movement._physics_elapsed, "position": Vector3.ZERO, "normal": Vector3.UP, "duration": 1.0}
		movement._apply_torso_response()
		var carried := 0.0
		for segment: Dictionary in movement._segments.values(): carried += float(segment.support_mass)
		var independent_mass: float = movement._height_support_external_gravity_mass()
		assert(is_equal_approx(carried+independent_mass, total_mass), "Assembly support includes every intact part without duplicating the Head gravity servo")
		assert(movement._last_auxiliary_support_force.y > (total_mass-independent_mass) * movement._gravity_acceleration().length(), "Height recovery must have force above its share of assembly weight")
		movement._physics_elapsed += 2.0
		movement._apply_torso_response()
		assert(movement._gallop_contacts.is_empty())
		assert(movement._last_auxiliary_support_force.is_zero_approx(), "Expired real-ground contacts must not permit hovering")
		for body: RigidBody3D in originals:
			body.global_transform = originals[body]
			body.freeze = true
		var foot: RigidBody3D = movement._legs[0]
		foot.global_position.y -= movement._get_foot_world_position(foot).y
		await physics_frame
		movement._begin_ground_probe_frame()
		foot.freeze = false
		movement._gallop_contacts[foot] = {"time": movement._physics_elapsed, "position": Vector3.ZERO, "normal": Vector3.UP, "duration": 1.0}
		var timestamp: float = movement._gallop_contacts[foot].time
		var bounds: Dictionary = movement._wolf_stride_bounds(foot, Vector3.RIGHT)
		var target: Vector3 = movement._get_projected_landing_rest_position(foot, Vector3.RIGHT) + Vector3.RIGHT * movement.get_leg_step_distance(foot)
		assert((target - Vector3(bounds.center)).x <= float(bounds.radius) * 0.8 + 0.001)
		assert(movement._landing_reach_attachment(foot).is_equal_approx(movement._chains[foot].root.to_global(movement._chains[foot].anchor)))
		var landing: Dictionary = movement.find_landing_point(foot, Vector3.RIGHT)
		assert(not landing.is_empty(), "Gallop reach must validate against the same root frame as its target")
		movement._begin_leg_motion(foot, target, Vector3.UP, Vector3.RIGHT)
		assert(movement._current_step.extra.has("wolf_step") and movement._current_step.extra.gallop_step)
		assert(movement._active_step_duration >= float(movement._current_step.extra.speed_gait.air_duration))
		assert(movement._gallop_contacts[foot].duration <= 3.0)
		assert(is_equal_approx(movement._gallop_contacts[foot].time, timestamp), "Planning must not renew a contact timestamp")
		foot.global_position.y += 0.8
		movement._begin_ground_probe_frame()
		movement._update_active_step(1.0 / 60.0)
		assert(movement._current_step.extra.wolf_step.phase == "swing")
		var body_root: RigidBody3D = movement._chains[foot].root
		body_root.global_position.x += 2.0
		movement._begin_ground_probe_frame()
		movement._update_active_step(1.0 / 60.0)
		bounds = movement._wolf_stride_bounds(foot, Vector3.RIGHT)
		assert(absf((movement._step_target - Vector3(bounds.center)).x) <= float(bounds.radius) * 0.8 + 0.001)
		assert(movement._current_step.extra.gallop_retargets == 0, "Wolf trajectory must not also run parent flight prediction")
		assert(movement._tracking_force.length() <= movement._tracking_force_limit + 0.001)
		movement._step_elapsed = movement._active_step_duration * 0.8
		foot.global_position = movement._step_target + Vector3.UP * 0.06
		foot.linear_velocity = Vector3.ZERO
		movement._begin_ground_probe_frame()
		movement._update_active_step(1.0 / 60.0)
		assert(movement._current_step.extra.wolf_step.phase == "descend", "Flying Wolf must use the one-way descent stage")
		assert(movement._tracking_position_error.y < 0.0)
		actor.free()
	var generic = load("res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd").new()
	assert(not generic._height_support_carries_limb_weight(), "Other creatures retain their support policy")
	generic.free()
	print("PASS: Wolf/NPC high-speed full-mass support, finite ground leases, safe gallop trajectory, bounded root-relative landing and force caps.")
	quit()
