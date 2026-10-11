extends SceneTree

class Command:
	extends Node
	var direction := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func is_fast_movement_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0,1.0,100.0)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	for name: String in ["Generate_Wolf","Generate_Wolf_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/"+name+".tscn").instantiate()
		root.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var movement = actor.get_node("GeneratedLegStepMovementController3D")
		assert(movement.get_script().resource_path.ends_with("WolfLegStepMovementController3D.gd"))
		var command := Command.new()
		actor.add_child(command)
		movement.command_source = command
		movement._startup_pending = false
		movement._walk_start_pending.clear()
		for body: Node in actor.get_node("GeneratedParts").get_children():
			if body is RigidBody3D: body.freeze = true
		await physics_frame
		for foot: RigidBody3D in movement._chains:
			var original := foot.global_transform
			for direction: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
				command.direction = direction
				var bounds: Dictionary = movement._wolf_stride_bounds(foot,direction)
				assert(bounds.radius>=0.0)
				if absf(direction.x)>0.5: assert(bounds.radius>0.0)
				var root_body: RigidBody3D = movement._chains[foot].root
				var data = movement._get_gait_data()
				var expected_offset: float = data.foreleg_stride_forward_offset if movement._has_body_tag(foot,movement.FORELEG_TAG) else -data.hindleg_stride_backward_offset
				assert(is_equal_approx((Vector3(bounds.center)-root_body.global_position).dot(direction),expected_offset))
				assert(is_equal_approx(float(bounds.offset),expected_offset))
				assert(bounds.radius<=float(movement._chains[foot].length)*movement._get_gait_data().maximum_foot_extension_ratio+0.0001)
				var first: Vector3 = movement._get_projected_landing_rest_position(foot,direction)+direction*movement.get_leg_step_distance(foot)
				var projection := (first-Vector3(bounds.center)).dot(direction)
				assert(projection >= -float(bounds.radius)*0.6-0.0001 and projection <= float(bounds.radius)*0.8+0.0001)
				assert(projection >= -0.0001,"Landing must be ahead of its torso-based interval center")
				# Changing the foot's longitudinal position cannot accumulate into the next target.
				for offset: float in [-0.9, -0.3, 0.3]:
					foot.global_position = original.origin + direction * float(bounds.radius) * offset
					movement._begin_ground_probe_frame()
					var recentered: Vector3 = movement._get_projected_landing_rest_position(foot,direction)+direction*movement.get_leg_step_distance(foot)
					assert(recentered.slide(Vector3.UP).is_equal_approx(first.slide(Vector3.UP)),"Foot drift changed torso-relative landing")
				movement._wolf_recovery_steps[foot] = 4
				var recovery_target: Vector3 = movement._get_projected_landing_rest_position(foot,direction)+direction*movement.get_leg_step_distance(foot)
				var recovery_forward := (recovery_target-Vector3(bounds.center)).dot(direction)
				assert(recovery_forward >= -0.0001 and recovery_forward <= projection+0.0001,"Recovery must shorten forward reach without inheriting a rearward foot offset")
				movement._wolf_recovery_steps.erase(foot)
				foot.global_transform = original
				movement._begin_ground_probe_frame()
				var target: Dictionary = movement.find_landing_point(foot,direction)
				if is_zero_approx(bounds.radius):
					assert(target.is_empty(),"No structural reach must not produce an out-of-range landing")
					continue
				assert(not target.is_empty(),"No legal Wolf landing: "+str(foot.name)+" "+str(direction))
				var position: Vector3 = movement._body_position_for_ground_contact(foot,target.position)
				assert(absf((position-Vector3(bounds.center)).dot(direction))<=float(bounds.radius)+0.0001)
				foot.global_position = Vector3(bounds.center)-direction*float(bounds.radius)*0.95
				root_body.linear_velocity = Vector3.ZERO
				movement._begin_ground_probe_frame()
				var demand: Dictionary = movement._get_extension_step_demand(foot,direction)
				assert(demand.requested,"Rear boundary should request a step: "+str(foot.name)+" "+str(demand))
				assert(demand.reason in ["distance_limit","extension_emergency"])
				root_body.linear_velocity = Vector3.ZERO
				foot.global_transform = original
				movement._action_feet[foot] = true
				assert(not movement._wolf_stride_enabled(foot))
				movement._action_feet.erase(foot)
			foot.global_transform = original
		# Sustained applied drive plus a rearward foot must recover even at zero body speed.
		movement._startup_pending = false
		movement._walk_start_pending.clear()
		command.direction = Vector3.RIGHT
		var test_foot: RigidBody3D = movement._chains.keys()[0]
		var saved := test_foot.global_transform
		var chain: Dictionary = movement._chains[test_foot]
		test_foot.global_position = movement._get_leg_rest_world_position(test_foot)-Vector3.RIGHT*float(chain.length)*0.2
		chain.root.linear_velocity = Vector3.ZERO
		movement._begin_ground_probe_frame()
		movement._contact_drive_frame = Engine.get_physics_frames()
		movement._contact_drive_rows.assign([{"foot":test_foot.name,"applied":Vector3.RIGHT*20.0,"carried_mass":1.0}])
		movement._update_wolf_traction(0.1)
		assert(not movement._wolf_traction[test_foot].confirmed)
		movement._update_wolf_traction(0.1)
		assert(movement._wolf_traction[test_foot].confirmed)
		var traction_demand: Dictionary = movement._get_extension_step_demand(test_foot,Vector3.RIGHT)
		assert(traction_demand.requested and traction_demand.reason=="traction_recovery")
		assert(traction_demand.step_priority>0.0)
		movement._wolf_traction[test_foot].cooldown = 0.25
		movement._update_wolf_traction(0.1)
		assert(not movement._wolf_traction[test_foot].confirmed)
		movement._update_wolf_traction(0.4)
		assert(movement._wolf_traction[test_foot].confirmed)
		movement._contact_drive_rows[0].applied = Vector3.ZERO
		movement._update_wolf_traction(0.1)
		assert(not movement._wolf_traction[test_foot].confirmed)
		command.direction = Vector3.ZERO
		movement._update_wolf_traction(0.1)
		assert(movement._wolf_traction.is_empty())
		test_foot.global_transform = saved
		actor.free()
	print("PASS: Wolf/NPC bounded landings, stationary distance trigger, confirmed traction recovery, cooldown, idle reset and action exclusion")
	quit()
