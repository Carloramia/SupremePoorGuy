extends SceneTree
const DATA = preload("res://Scripts/Creatures/LegMovementData.gd")
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var data = DATA.new()
	data.automatic_motion = true
	data.target_speed = 5.0
	data.maximum_step_frequency = 16.0
	data.maximum_simultaneous_steps = 0
	var short: Dictionary = data.calculate_motion_profile(3.77,3.0,4,3.77)
	var long: Dictionary = data.calculate_motion_profile(5.4,5.0,4,3.77)
	assert(is_equal_approx(short.reachable_speed,5.0) and not short.speed_limited)
	assert(is_equal_approx(short.stride,long.stride) and is_equal_approx(short.cycle,long.cycle))
	assert(short.total_frequency <= 16.0)
	assert(short.total_frequency * (short.swing_duration + short.landing_reserve) <= short.support_capacity)
	assert(short.position_gain > 250.0 and short.step_acceleration > 250.0)
	for count: int in [2,4,6,10]:
		for cap: int in [0,1,2]:
			data.maximum_simultaneous_steps = cap
			var profile: Dictionary = data.calculate_motion_profile(3.77,3.0,count)
			assert(profile.total_frequency * (profile.swing_duration + profile.landing_reserve) <= profile.support_capacity + 0.0001)
	data.maximum_step_frequency = 4.0
	var slow_air: Dictionary = data.calculate_speed_gait_profile(3.77,6,1.0,1.0,5)
	var fast_air: Dictionary = data.calculate_speed_gait_profile(3.77,6,5.0,1.0,5)
	assert(is_equal_approx(fast_air.cycle,1.5) and is_equal_approx(fast_air.required_stride,7.5))
	assert(fast_air.air_duration > slow_air.air_duration)
	assert(is_equal_approx(fast_air.air_duration+fast_air.stance_duration+fast_air.landing_reserve,fast_air.cycle))
	assert(fast_air.air_duration+fast_air.landing_reserve <= fast_air.cycle*5.0/6.0+0.0001)
	assert(fast_air.requires_flight and fast_air.air_duration_limited)
	var rest_air: Dictionary = data.calculate_speed_gait_profile(3.77,6,0.0,1.0,5)
	assert(is_finite(rest_air.air_duration) and rest_air.air_duration > 0.0)
	var limited_support: Dictionary = data.calculate_speed_gait_profile(3.77,6,5.0,0.0,1)
	assert(limited_support.air_duration < fast_air.air_duration)
	assert(not data.calculate_speed_gait_profile(3.77,6,5.0,1.0,0).enabled)
	data.maximum_step_frequency = 60.0
	var crowded: Dictionary = data.calculate_speed_gait_profile(3.77,10,5.0,0.0,1)
	assert(crowded.total_frequency*(crowded.air_duration+crowded.landing_reserve) <= 1.0001)
	data.target_speed = 0.0
	assert(not data.calculate_speed_gait_profile(3.77,6,0.0,1.0,5).enabled)
	data.target_speed = 5.0
	data.maximum_simultaneous_steps = 0
	data.maximum_step_frequency = 6.0
	var limited: Dictionary = data.calculate_motion_profile(3.77,3.0,4)
	assert(limited.speed_limited and limited.total_frequency <= 6.0)
	assert(limited.stride <= limited.maximum_stride)
	data.maximum_stepping_ratio = 0.0
	assert(data.calculate_motion_profile(3.77,3.0,4).frequency == 0.0)
	data.maximum_stepping_ratio = 0.5
	data.target_speed = 0.0
	assert(data.calculate_motion_profile(3.77,3.0,4).frequency == 0.0)
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator._random.seed = 43
	generator.neck_number = 0
	generator.unsymmetrie = 0.0
	assert(actor.generate_creature())
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	var fixture_data = movement.slow_gait_data.duplicate()
	fixture_data.target_speed = 5.0
	fixture_data.maximum_step_frequency = 16.0
	movement.slow_gait_data = fixture_data
	var first: Dictionary = movement.get_leg_motion_profile(movement._legs[0])
	for foot: RigidBody3D in movement._legs:
		var profile: Dictionary = movement.get_leg_motion_profile(foot)
		assert(is_equal_approx(first.stride,profile.stride) and is_equal_approx(first.cycle,profile.cycle))
		assert(is_equal_approx(profile.reachable_speed,5.0))
	print("AUTOMATIC_SPEED_PROFILE ",first)
	actor.free()
	print("AUTOMATIC_TARGET_SPEED_PASSED")
	quit()
