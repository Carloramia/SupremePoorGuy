extends SceneTree
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void:
	var data := LegMovementData.new()
	for count: int in [2,4,6,10]:
		for speed: float in [0.5,5.0,10.0]:
			for frequency: float in [1.0,4.0,16.0]:
				data.target_speed = speed
				data.maximum_step_frequency = frequency
				var plan := data.calculate_adaptive_flight_profile(8.0,count,speed,2.0,count)
				check(plan.total_frequency<=frequency+0.001,"Cadence must respect its ceiling")
				check(is_equal_approx(plan.required_stride,speed*plan.cycle),"World stride budget")
				check(plan.required_capacity==mini(count,ceili(plan.total_frequency*(plan.air_duration+plan.landing_confirmation+0.02)-0.000001)),"Reserve capacity for flight AND landing confirmation")
				check(plan.required_capacity<=count,"Capacity cannot exceed available feet")
				check(plan.lease_duration>0 and plan.lease_duration<=2.0,"Flight authorization must expire")
				check(plan.distance_deficit>=0 and is_finite(plan.air_duration),"Infeasible distance must be reported without invalid math")
				data.gallop_landing_confirmation = 0.8
				data.gallop_maximum_stepping_ratio = 0.1
				var changed := data.calculate_adaptive_flight_profile(8.0,count,speed,2.0,count)
				check(changed == plan,"Manual flight numbers must not constrain automatic timing")
	data.target_speed = 5.0
	data.maximum_step_frequency = 4.0
	var ample := data.calculate_adaptive_flight_profile(8,4,5,3,4)
	var near_limit := data.calculate_adaptive_flight_profile(8,4,5,0.2,4)
	check(is_equal_approx(near_limit.air_duration,ample.air_duration),"Current extension must not compress or stretch the reference swing")
	check(near_limit.required_capacity>=ample.required_capacity,"Longer flight must reserve additional slots")
	var delayed := data.calculate_adaptive_flight_profile(8,4,5,0.2,4,0.35)
	check(delayed.landing_reserve>near_limit.landing_reserve,"Actual touchdown delay must reserve scheduler occupancy")
	check(is_equal_approx(delayed.air_duration,near_limit.air_duration),"A slow landing must never squeeze the next swing")
	check(is_equal_approx(delayed.landing_confirmation,near_limit.landing_confirmation),"Planning reserve must not lengthen the required stable-contact confirmation")
	var slow_landing := data.calculate_adaptive_flight_profile(8,4,5,0.2,4,0.7)
	check(slow_landing.landing_reserve>=0.7,"Do not clip actual landing time to 40 percent of the cycle")
	check(is_equal_approx(slow_landing.total_frequency,near_limit.total_frequency),"Measured landing delays must not change reference cadence")
	check(is_equal_approx(ample.air_duration,ample.base_air_duration*1.12),"Add twelve percent flight time when geometry allows it")
	check(is_equal_approx(ample.lift,slow_landing.lift),"Landing/flight duration changes must not raise clearance")
	check(is_equal_approx(slow_landing.required_stride,data.target_speed*slow_landing.cycle),"Recompute world stride after cadence adjustment")
	var shared_a := data.calculate_adaptive_flight_profile(8,4,5,3,4,0)
	var shared_b := data.calculate_adaptive_flight_profile(8,4,5,0.2,4,0.7)
	check(is_equal_approx(shared_a.cycle,shared_b.cycle),"One character must use one shared cycle")
	check(is_equal_approx(shared_a.total_frequency,shared_b.total_frequency),"Different landing delays must not create conflicting cadence")
	var reserved_foot := data.calculate_adaptive_flight_profile(8,4,5,0,3,0.7)
	check(reserved_foot.required_capacity<=3,"Reserve-one-foot admission must retain its capacity")
	check(not data.calculate_adaptive_flight_profile(8,1,5,1,0).enabled,"No legal swing when support reservation consumes the only foot")
	data.target_speed = 0
	check(not data.calculate_adaptive_flight_profile(8,4,0,1,4).enabled,"No movement at zero target speed")
	print("ADAPTIVE_FLIGHT_BUDGET_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
