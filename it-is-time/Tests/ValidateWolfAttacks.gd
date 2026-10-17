extends SceneTree
const WEAPON = preload("res://Scripts/Items/WolfAttackHitbox3D.gd")
class LaunchFixture:
	extends Node
	var _chains: Dictionary = {}
	var support: RigidBody3D
	var grounded := true
	var galloping := true
	var recovery_control_active := false
	func is_action_turn_blocked() -> bool: return false
	func _gallop_active() -> bool: return galloping
	func get_action_support_feet() -> Array[RigidBody3D]: return [support] if grounded else []
	func get_leg_parts() -> Array[RigidBody3D]: return []
	func _gravity_acceleration() -> Vector3: return Vector3.DOWN*9.8
var _failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(500,1,500)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -1.0
	root.add_child(floor_body)
	var wolf = load("res://Scenes/Creatures/Characters/Generate_Wolf.tscn").instantiate()
	wolf.generate_on_ready = false
	root.add_child(wolf)
	var npc = load("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn").instantiate()
	npc.generate_on_ready = false
	npc.position.z = 100.0
	root.add_child(npc)
	wolf.process_mode = Node.PROCESS_MODE_DISABLED
	npc.process_mode = Node.PROCESS_MODE_DISABLED
	for actor: Node in [wolf,npc]:
		for body: RigidBody3D in actor._get_physical_body_parts(): body.freeze = true
	await physics_frame
	var attacks = npc.get_node("WolfAttackController3D")
	var movement = attacks.movement
	var bite = attacks.get_node("Bite")
	var pounce = attacks.get_node("Pounce")
	check(wolf.get_node("WolfAttackController3D").has_npc_attack(&"wolf_claw") == false,"Player Wolf must not accept attack commands")
	check(npc.get_node("NPCStateMachine3D").attack_execution_enabled,"Wolf NPC AI attacks enabled")
	check(npc.get_node("NPCStateMachine3D").behavior.attacks.size() == 2,"Only pounce and bite registered")
	check(not attacks.has_node("Claw") and not attacks.has_npc_attack(&"wolf_claw"),"Claw module is removed")
	for part: RigidBody3D in npc._get_physical_body_parts(): part.freeze = false
	movement.recovery_control_active = false
	var target: PhysicalBodyPart3D = wolf.get_node("GeneratedParts/Torso")
	wolf.faction_id = 2
	# Place a large target across the predicted melee path, without advancing physics.
	target.global_position = bite.jaw.global_position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20,20,20)
	collision.shape = shape
	target.add_child(collision)
	await physics_frame
	check(attacks._target_valid(target),"Enemy target recognized")
	check(not pounce.predict(target,16,0.1).hit,"Pounce requires gallop")
	var bite_range: float = attacks.get_npc_attack_maximum_range(&"wolf_bite",target)
	var original_target_position := target.global_position
	target.global_position = attacks.torso.global_position+attacks.forward()*(bite_range+5.0)
	target.linear_velocity = -attacks.forward()*3.0
	var incoming_range: float = attacks.get_npc_attack_maximum_range(&"wolf_bite",target)
	check(is_equal_approx(incoming_range-bite_range,3.0*(bite.data.bite_plant_prediction_time+maxf(bite.data.bite_retract_time,bite.data.jaw_open_time))),"Incoming bite admission reserves the actual foot planting and charging delay")
	check(attacks.is_npc_target_in_attack_range(&"wolf_bite",target),"Incoming targets can be prepared for before entering static mouth reach")
	check(attacks.is_target_in_bite_distance(target),"Incoming targets inside the bite preparation envelope cannot trigger pounce")
	target.linear_velocity = attacks.forward()*3.0
	check(is_equal_approx(attacks.get_npc_attack_maximum_range(&"wolf_bite",target),bite_range),"Receding targets do not gain fictitious physical reach")
	target.linear_velocity = Vector3.ZERO
	target.global_position = attacks.torso.global_position+attacks.forward()*(bite_range-0.01)
	bite.cooldown_remaining = 5.0
	check(attacks.is_target_in_bite_distance(target),"Bite distance exclusion remains active during cooldown")
	check(not attacks.is_npc_target_in_attack_range(&"wolf_pounce",target),"AI rejects pounce inside bite distance")
	check(pounce.predict(target,16,0.1).get("reason") == &"within_bite_range","Pounce module rejects bite distance independently of AI selection")
	check(not pounce.start(target),"Direct pounce start cannot bypass bite distance")
	target.global_position = attacks.torso.global_position+attacks.forward()*(bite_range+0.01)
	check(not attacks.is_target_in_bite_distance(target),"Outside bite distance remains eligible for other pounce gates")
	bite.cooldown_remaining = 0.0
	var near_part: PhysicalBodyPart3D = wolf.get_node("GeneratedParts/SubTorso_ForeLeg_1")
	var near_original := near_part.global_position
	target.global_position = attacks.torso.global_position+attacks.forward()*(attacks.get_npc_attack_minimum_range(&"wolf_pounce")+10.0)
	near_part.global_position = attacks.torso.global_position+attacks.forward()*bite_range*0.5
	var blocked: Dictionary = attacks.get_pounce_distance_check(target)
	check(not blocked.hit and blocked.reason == &"within_bite_range" and blocked.blocking_part == str(near_part.get_path()),"A farther target Torso cannot bypass another nearby Torso of the same enemy")
	check(not attacks.is_npc_attack_distance_candidate(&"wolf_pounce",target),"Near enemies cannot reserve pounce approach distance")
	check(not attacks.is_npc_target_in_attack_range(&"wolf_pounce",target) and not pounce.intercept_plan(target).hit,"AI and ballistic planning share the whole-enemy distance gate")
	near_part.global_position = near_original
	target.global_position = attacks.torso.global_position+attacks.forward()*(attacks.get_npc_attack_minimum_range(&"wolf_pounce")-0.01)
	check(pounce.intercept_plan(target).reason == &"pounce_too_close","Distances below the enlarged minimum are rejected outside bite reach too")
	target.global_position = original_target_position
	var distance_ai = npc.get_node("NPCStateMachine3D")
	distance_ai._target = target
	var preferred_bite: float = distance_ai._preferred_attack_distance(distance_ai.behavior.attacks[1])
	var preferred_pounce: float = distance_ai._preferred_attack_distance(distance_ai.behavior.attacks[0])
	var scaled_tolerance: float = distance_ai._attack_distance_tolerance(distance_ai.behavior.attacks[0])
	check(preferred_bite+scaled_tolerance < bite_range,"Bite stopping band stays inside dynamic bite range")
	check(preferred_pounce-scaled_tolerance > bite_range,"Pounce stopping band remains outside bite exclusion")
	target.global_position = attacks.torso.global_position+attacks.forward()*preferred_bite
	distance_ai._plan_attack_distance(preferred_bite,distance_ai.behavior.attacks)
	check(distance_ai._distance_attack.action_id == &"wolf_bite","Distance planning selects bite within its range")
	var initial_size: Vector3 = attacks.torso.get_meta(&"generated_size")
	attacks.torso.set_meta(&"generated_size",initial_size*2.0)
	check(is_equal_approx(attacks.get_npc_attack_distance_tolerance(&"wolf_bite"),scaled_tolerance*2.0),"Stopping tolerance scales with actual torso size")
	attacks.torso.set_meta(&"generated_size",initial_size)
	target.global_position = original_target_position
	distance_ai._target = null
	distance_ai._distance_attack = null
	bite.enabled = false
	var authored_scale: float = attacks.pounce_scale()
	var torso_size: Vector3 = attacks.torso.get_meta(&"generated_size")
	attacks.torso.set_meta(&"generated_size",torso_size*1.5)
	check(is_equal_approx(attacks.pounce_scale(),authored_scale*1.5),"Pounce follows actual body size without changing generator scale")
	check(is_equal_approx(attacks.get_npc_attack_maximum_range(&"wolf_pounce"),pounce.data.maximum_range*authored_scale*1.5*(1.0-pounce.data.pounce_range_margin_ratio)+pounce.landing_standoff()+pounce._planned_charge_offset().dot(attacks.forward())),"AI uses the safe travel range plus landing standoff")
	attacks.torso.set_meta(&"generated_size",torso_size)
	var launch_fixture := LaunchFixture.new()
	launch_fixture.support = attacks.torso
	attacks.movement = launch_fixture
	launch_fixture.grounded = false
	target.global_position = attacks.torso.global_position+attacks.forward()*12.0*attacks.pounce_scale()
	var planting_plan: Dictionary = pounce.intercept_plan(target)
	check(planting_plan.hit and is_equal_approx(planting_plan.charge_duration,pounce.data.pounce_charge_time+pounce.data.pounce_plant_prediction_time),"Ungrounded prediction includes foot planting before charge")
	launch_fixture.grounded = true
	pounce.tick(0.01)
	launch_fixture.galloping = false
	pounce.tick(0.1)
	check(pounce.predict(target,16,0.1).hit,"Recent running qualification survives braking for grounded preparation")
	pounce.tick(pounce.data.pounce_gallop_grace_time+0.01)
	check(pounce.predict(target,16,0.1).get("reason") == &"not_galloping","Expired running qualification cannot authorize a standing pounce")
	launch_fixture.galloping = true
	pounce.tick(0.01)
	pounce.reserve_preparation(target)
	launch_fixture.galloping = false
	pounce.tick(pounce.data.pounce_gallop_grace_time+0.01)
	check(pounce.predict(target,16,0.1).hit,"Committed running preparation survives the ordinary gallop grace")
	var reservation: float = pounce._preparation_remaining
	pounce.reserve_preparation(target)
	check(is_equal_approx(reservation,pounce._preparation_remaining),"Repeated AI preparation checks cannot renew an expired running approach")
	pounce.tick(reservation+0.01)
	check(pounce.predict(target,16,0.1).get("reason") == &"not_galloping","Committed preparation still has a bounded timeout")
	launch_fixture.galloping = true
	bite.enabled = true
	for part: RigidBody3D in npc._get_physical_body_parts(): part.freeze = true
	check(pounce.start(target),"A genuinely distant running approach can still prepare pounce")
	near_part.global_position = attacks.torso.global_position+attacks.forward()*2.0
	var velocity_before: Vector3 = attacks.torso.linear_velocity
	var committed_endpoint: Vector3 = pounce.locked_position
	pounce._launch()
	check(pounce.active and pounce._phase == &"flying" and pounce.locked_position == committed_endpoint,"A target entering bite range after admission cannot cancel or redirect pounce")
	check(pounce.launch_velocity.is_finite() and pounce.launch_velocity.length() <= pounce.data.maximum_launch_speed*sqrt(pounce.body_scale)+0.001,"Committed pounce retains finite bounded launch speed")
	check(attacks.torso.linear_velocity == velocity_before,"Frozen fixture parts never receive launch impulses")
	pounce.finish()
	near_part.global_position = near_original
	bite.enabled = false
	pounce.cooldown_remaining = 0.0
	for part: RigidBody3D in npc._get_physical_body_parts(): part.freeze = false
	var target_position: Vector3 = attacks.torso.global_position+attacks.forward()*8.0*attacks.pounce_scale()
	for size_ratio: float in [0.5,1.0,2.0,4.0]:
		attacks.torso.set_meta(&"generated_size",torso_size*size_ratio)
		var scale: float = attacks.pounce_scale()
		target.global_position = attacks.torso.global_position+attacks.forward()*12.0*scale
		var prediction: Dictionary = pounce.predict(target,16,0.1)
		var ai = npc.get_node("NPCStateMachine3D")
		check(is_equal_approx(ai._attack_maximum_range(ai.behavior.attacks[0],target),pounce.data.maximum_range*scale*(1.0-pounce.data.pounce_range_margin_ratio)+pounce._planned_charge_offset().dot(attacks.forward())),"AI stop band uses safe scaled pounce range")
		check(prediction.hit,"Pounce remains valid at different body sizes")
		if prediction.hit:
			check(is_equal_approx(float(prediction.duration)/sqrt(scale),maxf(pounce.data.flight_time,sqrt(8.0*pounce.data.minimum_lift_height/9.8))),"Pounce duration scales with sqrt(size)")
			var lift: float = pow(Vector3(prediction.velocity).y,2.0)/(2.0*9.8)
			check(lift >= pounce.data.minimum_lift_height*scale,"Scaled pounce retains required lift height")
			var brake: float = minf(pounce.data.combo_window*sqrt(scale),float(prediction.duration)*0.4)
			check(is_equal_approx(Vector3(prediction.velocity).slide(Vector3.UP).length()*(float(prediction.duration)-brake*0.5),float(prediction.planned_distance)),"Scaled ballistic travel matches destination")
		var duration: float = pounce._flight_duration(scale)
		var maximum: float = pounce.data.maximum_range*scale*(1.0-pounce.data.pounce_range_margin_ratio)
		var speed := 4.0*sqrt(scale)
		target.linear_velocity = -attacks.forward()*speed
		target.global_position = attacks.torso.global_position+attacks.forward()*(maximum*0.99+speed*(duration+pounce.data.pounce_charge_time)+pounce._planned_charge_offset().dot(attacks.forward()))
		pounce._target_velocities.clear()
		var incoming: Dictionary = pounce.predict(target,16,0.1)
		check(attacks.torso.global_position.distance_to(target.global_position) > pounce.data.maximum_range*scale,"Incoming fixture begins beyond the old maximum range")
		check(incoming.hit and attacks.is_npc_target_in_attack_range(&"wolf_pounce",target),"Incoming target can trigger an early pounce through the AI gate")
		if incoming.hit:
			check(is_equal_approx(float(incoming.planned_distance),maximum*0.99),"Early pounce uses almost the full safe travel range")
			check(Vector3(incoming.predicted_target_position).distance_to(target.global_position+target.linear_velocity*(duration+pounce.data.pounce_charge_time)) < 0.001,"Intercept includes charging time and flight time")
			var brake := minf(pounce.data.combo_window*sqrt(scale),duration*0.4)
			var end: Vector3 = pounce._trajectory_point(incoming.launch_origin,incoming.velocity,Vector3.DOWN*9.8,duration,duration,brake)
			check(end.distance_to(incoming.endpoint) < 0.001,"Obstacle prediction includes the scheduled final braking")
			for part: RigidBody3D in npc._get_physical_body_parts(): part.freeze = true
			pounce.cooldown_remaining = 0.0
			check(pounce.start(target),"Incoming target can actually start pounce")
			check(pounce._phase == &"charging" and not pounce.combo_checked,"Pounce first enters charge without firing its combo")
			var torso_position: Vector3 = attacks.torso.global_position
			var offset: Vector3 = pounce._charge_offset
			check(pounce._charge_target(torso_position,0.0) == torso_position,"Charge starts at the current torso pose")
			check(pounce._charge_target(torso_position,pounce.data.pounce_charge_time).distance_to(torso_position+offset) < 0.001,"Charge smoothly lowers and retracts the torso")
			attacks.torso.global_position += offset
			target.global_position += target.linear_velocity*pounce.data.pounce_charge_time
			pounce._launch()
			check(pounce._phase == &"flying","Charge launches the admitted plan from the actual torso pose")
			var locked: Vector3 = pounce.locked_position
			var launched_velocity: Vector3 = pounce.launch_velocity
			target.global_position += Vector3(2.0,0.0,1.0)
			target.linear_velocity = Vector3.BACK*30.0
			pounce.tick(0.01)
			check(pounce.locked_position == locked and pounce.launch_velocity == launched_velocity,"Target changes after takeoff cannot retarget the locked pounce")
			pounce.finish()
			attacks.torso.global_position = torso_position
			pounce.cooldown_remaining = 0.0
			for part: RigidBody3D in npc._get_physical_body_parts(): part.freeze = false
			target.global_position = attacks.torso.global_position+attacks.forward()*(maximum*0.99+speed*(duration+pounce.data.pounce_charge_time)+pounce._planned_charge_offset().dot(attacks.forward()))
		target.linear_velocity = attacks.forward()*speed
		pounce._target_velocities.clear()
		check(not pounce.predict(target,16,0.1).hit and not attacks.is_npc_target_in_attack_range(&"wolf_pounce",target),"Receding target beyond reach cannot trigger early pounce")
		target.linear_velocity = Vector3.ZERO
		pounce._target_velocities.clear()
		check(not pounce.predict(target,16,0.1).hit,"Stationary target beyond reach is rejected")
		target.global_position = attacks.torso.global_position+attacks.forward()*8.0*scale
		target.linear_velocity = -attacks.forward()*(20.0*sqrt(scale))
		pounce._target_velocities.clear()
		check(not pounce.predict(target,16,0.1).hit,"Target predicted to pass Wolf before landing is rejected")
		target.linear_velocity = Vector3.ZERO
		pounce._target_velocities.clear()
	attacks.torso.set_meta(&"generated_size",torso_size)
	for part: RigidBody3D in npc._get_physical_body_parts(): part.freeze = true
	target.global_position = attacks.torso.global_position+attacks.forward()*12.0*attacks.pounce_scale()
	target.linear_velocity = Vector3.ZERO
	pounce._target_velocities.clear()
	pounce.cooldown_remaining = 0.0
	check(pounce.start(target),"Pounce can prepare another valid intercept")
	committed_endpoint = pounce.locked_position
	target.global_position += attacks.forward()*1000.0
	pounce._launch()
	check(pounce.active and pounce._phase == &"flying" and pounce.locked_position == committed_endpoint,"An escaped target cannot revoke the admitted pounce endpoint")
	pounce.finish()
	check(pounce.owned_feet.is_empty() and pounce.owned_bodies.is_empty(),"Completion releases action ownership")
	pounce.active = true
	pounce._intercept.clear()
	pounce._launch()
	check(not pounce.active and pounce._phase == &"idle","Missing committed physics data still aborts safely")
	pounce.cooldown_remaining = 0.0
	for part: RigidBody3D in npc._get_physical_body_parts(): part.freeze = false
	target.linear_velocity = Vector3.RIGHT*4.0
	pounce._target_velocities.clear()
	pounce._target_velocity(target)
	target.linear_velocity = Vector3.LEFT*4.0
	pounce.tick(0.05)
	var smoothed: Vector3 = pounce._target_velocity(target)
	check(smoothed.x > -4.0 and smoothed.x < 4.0,"Brief target velocity changes are smoothed")
	check(smoothed == pounce._target_velocity(target),"Repeated predictions in one frame use the same velocity")
	target.linear_velocity = Vector3.ZERO
	pounce._target_velocities.clear()
	target.global_position = target_position
	attacks.movement = movement
	bite.enabled = true
	launch_fixture.free()
	validate_bite_frame(bite)
	check(bite.predict(target,16,0.1).hit,"Bite predicts an intersecting target")
	var reachable_position := target.global_position
	var hp_before_prediction := target.current_hp
	target.linear_velocity = attacks.forward()*1000.0
	check(not bite._closing_prediction(target,16,0.1,true,0.7).hit,"Fixture exercises an uncertain future outside the sweep")
	bite.target = target
	check(bite._closing_prediction(target,16,0.1,true,0.7,false).hit,"Current geometry can still detect a reachable target")
	target.global_position += attacks.forward()*10000.0
	await physics_frame
	check(not bite._closing_prediction(target,16,0.1,true,0.7,false).hit,"Admission geometry still rejects an unreachable target")
	check(target.current_hp == hp_before_prediction,"Prediction fallback never creates damage without actual contact")
	target.global_position = reachable_position
	target.linear_velocity = Vector3.ZERO
	bite.target = null
	await physics_frame
	var original_limit: bool = bite.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT)
	var original_lower: float = bite.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
	var original_y: bool = bite.joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT)
	bite.data = bite.data.duplicate()
	var spacing_target := target.global_position
	target.global_position = bite.head.global_position
	check(bite._spacing_for(target) > 0.0,"Close target requests a body-scaled retreat")
	target.global_position = bite.head.global_position+Vector3.RIGHT*100.0
	check(bite._spacing_for(target) == 0.0,"Distant target does not request a retreat")
	target.global_position = spacing_target
	bite.data.bite_close_distance_ratio = 0.0
	check(attacks.try_start_npc_attack(&"wolf_bite",target,0.0),"AI bite starts")
	check(not attacks.try_start_npc_attack(&"wolf_bite",target,0.0),"Active bite cannot restart")
	check(not pounce.available(),"Pounce cannot overlap bite")
	check(movement._action_feet.size() == 4 and bite._phase == &"planting","Bite owns all legs before body motion")
	check(not bite.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT),"Bite releases jaw Z only")
	check(bite.joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT) == original_y,"Bite preserves jaw Y constraint")
	var flight_row := {"start":Vector3(0,-4,0),"folded":Vector3(-2,-2,0),"extended":Vector3(3,-4,0)}
	check(pounce._foreleg_offset(flight_row,0.0) == flight_row.start,"Pounce foreleg motion begins at the actual pose")
	check(pounce._foreleg_offset(flight_row,0.5) == flight_row.folded,"Pounce forelegs retract at midflight")
	check(pounce._foreleg_offset(flight_row,1.0) == flight_row.extended,"Pounce forelegs extend at the end of flight")
	check(pounce.data.minimum_lift_height >= 1.5,"Pounce uses a higher ballistic arc")
	check(bite._foot_plans.size() == 4,"Bite replans every foot before pinning")
	check(bite._support_count == 0 and movement._support_pins.is_empty(),"Replanning does not pin the old foot positions")
	check(bite.data.bite_lunge_acceleration_time >= 0.3 and bite.data.bite_lunge_speed >= 10.0,"Bite preset supplies a stronger sustained burst")
	for row: Dictionary in bite._foot_plans: row.elapsed = 0.6
	bite._foot_plans[0].best_error = 0.0
	bite._foot_plans[0].stalled_time = 0.39
	bite._reposition_feet(0.02)
	check(bite._repositioned_feet >= 1 and bite._foot_plans[0].skipped,"Blocked foot is skipped without waiting for the attack timeout")
	check(bite._foot_plans.all(func(row: Dictionary) -> bool: return is_equal_approx(row.elapsed,0.62)),"All unfinished feet advance their own trajectory in the same tick")
	var completed_elapsed: float = bite._foot_plans[0].elapsed
	bite._reposition_feet(0.02)
	check(is_equal_approx(bite._foot_plans[0].elapsed,completed_elapsed) and is_equal_approx(bite._foot_plans[1].elapsed,0.64),"Completed foot stops tracking while other feet continue independently")
	bite._begin_charge()
	check(bite._phase == &"charging" and bite._crouch > 0.0,"Bite begins a crouching backward charge after planting")
	var torso_row: Dictionary = bite._torsos[0]
	var charge_duration: float = maxf(bite.data.bite_retract_time,bite.data.jaw_open_time)
	var charge_start: Vector3 = bite._body_target(torso_row,0.0)
	var charge_end: Vector3 = bite._body_target(torso_row,charge_duration)
	check(charge_start == torso_row.origin,"Charge begins at the settled torso position")
	check(is_equal_approx(charge_start.y-charge_end.y,bite._crouch),"Charge lowers the torso by the planned amount")
	check(is_equal_approx((charge_end-charge_start).dot(bite._forward),-bite._retract),"Charge retracts opposite to the current facing")
	check(bite._body_target(torso_row,charge_duration*0.5).distance_to(charge_start.lerp(charge_end,0.5)) < 0.001,"Charge target moves smoothly through its midpoint")
	for foot: RigidBody3D in bite.owned_feet:
		var chain: Dictionary = movement._chains[foot]
		var relative: Vector3 = foot.global_position-chain.root.to_global(chain.anchor)
		var radius := maxf(float(chain.length)*0.98,relative.length()+0.001)
		check((relative-(charge_end-charge_start)).length() <= radius+0.001,"Combined crouch and retraction remain inside chain reach")
	var before_escape: Vector3 = target.global_position
	target.global_position += Vector3(1000,0,1000)
	bite._phase_time = charge_duration
	bite.tick(0.01)
	check(bite.active and bite._phase == &"lunging","An admitted bite strikes even when the target escapes during charge")
	target.global_position = before_escape
	bite._set_phase(&"recovering")
	check(bite._body_target(torso_row,0.0) == torso_row.body.global_position,"Recovery starts at the actual torso pose")
	check(bite._body_target(torso_row,bite.data.recovery_time).distance_to(torso_row.origin) < 0.001,"Recovery returns smoothly to the original pose")
	attacks.cancel_npc_attack()
	check(not attacks.is_npc_attack_active() and movement._action_feet.is_empty(),"Cancel releases feet")
	check(bite.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT) == original_limit,"Jaw Z flag restored")
	check(is_equal_approx(bite.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),original_lower),"Jaw limits restored")
	bite.cooldown_remaining = 0.0
	pounce.active = true
	attacks.try_end_combo(target)
	check(attacks._combo_pending == [&"wolf_bite"] and not bite.active,"Flight queues only bite and waits for landing")
	pounce.finish()
	attacks._update_combo(0.06)
	check(bite.active and attacks._combo_pending.is_empty(),"Pounce can transition into bite when prediction hits")
	attacks.cancel_npc_attack()
	bite.cooldown_remaining = 0.0
	target.global_position += Vector3(1000,0,0)
	await physics_frame
	attacks.try_end_combo(target)
	check(not bite.active,"Pounce combo cannot bypass missed prediction")
	attacks.cancel_action()
	wolf.faction_id = npc.faction_id
	check(not attacks._target_valid(target),"Friendly attacks rejected")
	wolf.faction_id = 2
	# Damage registration uses global damage/armor and cannot hit friendlies or repeat a Part.
	var weapon := WEAPON.new()
	weapon.setup(bite.jaw,npc,Vector3.ONE,Vector3.ZERO,1.0)
	root.add_child(weapon)
	target.armor = 0.0
	target.max_hp = 100000.0
	target.current_hp = 100000.0
	var hp := target.current_hp
	var dealt := weapon.apply_contact_damage(target,100.0)
	check(dealt > 0.0 and target.current_hp < hp,"Global damage settles temporary weapon hits")
	check(weapon.apply_contact_damage(target,100.0) == 0.0,"One hit per target Part")
	wolf.faction_id = npc.faction_id
	weapon.end_damage_swing()
	weapon.begin_damage_swing()
	check(weapon.apply_contact_damage(target,100.0) == 0.0,"No friendly damage")
	wolf.faction_id = 2
	weapon.end_damage_swing()
	weapon.begin_damage_swing()
	weapon.body.freeze = true
	target.global_position = weapon.body.global_position+Vector3.RIGHT*0.2
	await physics_frame
	weapon.body.linear_velocity = Vector3.RIGHT*10.0
	hp = target.current_hp
	weapon.update_hitbox(1.0/60.0,true)
	check(target.current_hp < hp and weapon.hit_count > 0,"Actual shape query settles contact damage")
	hp = target.current_hp
	weapon.update_hitbox(1.0/60.0,true)
	check(target.current_hp == hp,"Repeated query cannot double hit")
	weapon.dispose()
	weapon.body.freeze = false
	bite.cooldown_remaining = 0.0
	check(bite.start(target),"Bite can repeat after its own cooldown")
	attacks.cancel_npc_attack()
	bite.cooldown_remaining = 0.0
	check(bite.start(target),"Bite can restart after cooldown")
	attacks.refresh_physics_query_cache()
	check(not bite.active and bite._joint_state.is_empty(),"Regeneration refresh cancels active jaw control")
	check(bite.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT) == original_limit,"Regeneration restores jaw limits")
	bite.cooldown_remaining = 0.0
	check(bite.start(target),"Bite restarts for character shutdown check")
	attacks.set_character_control_enabled(false)
	check(not attacks.is_npc_attack_active() and movement._action_feet.is_empty(),"Character shutdown releases all attack claims")
	attacks.set_character_control_enabled(true)
	var console := root.get_node("RuntimeConsole")
	check(console.execute_command("help").contains("trackwolfattacks"),"Help includes attack tracking")
	check(console.execute_command("trackwolfattacks on GenerateWolfNPC").contains("enabled"),"Attack log switch enabled")
	check(attacks.diagnostic_logging,"Filtered tracking applies")
	console.execute_command("trackwolfattacks off")
	npc.free(); wolf.free()
	print("WOLF_ATTACK_VALIDATION ","FAILED" if _failed else "PASSED")
	quit(1 if _failed else 0)

func validate_bite_frame(bite: Node) -> void:
	var head_pose: Transform3D = bite.head.global_transform
	var jaw_pose: Transform3D = bite.jaw.global_transform
	var closed: Transform3D = bite._closure_pose(1.0,true)
	check(bite._closure_pose(0.0,false).is_equal_approx(jaw_pose),"Remaining closure starts at the actual Jaw pose")
	var opened: Transform3D = bite._closure_pose(0.0,true)
	bite.jaw.global_transform = opened
	check(bite._closure_pose(0.0,false).is_equal_approx(opened),"An already open jaw is not opened twice by prediction")
	check(bite._closure_pose(1.0,false).is_equal_approx(closed),"Actual and admission sweeps reach the same closed pose")
	var turn := Transform3D(Basis(Vector3.UP,0.7),Vector3(100,3,-25))
	var authored_joint: Transform3D = bite.joint.global_transform
	bite.head.global_transform = turn*head_pose
	bite.jaw.global_transform = turn*opened
	check(bite.joint.global_transform == authored_joint,"Regression leaves the static Joint node behind")
	var expected := turn*closed
	var actual: Transform3D = bite._closure_pose(1.0,false)
	check(actual.origin.distance_to(expected.origin)<0.0001 and actual.basis.is_equal_approx(expected.basis),"Closure follows Head translation and rotation instead of the authored Joint node")
	bite.head.global_transform = head_pose
	bite.jaw.global_transform = jaw_pose
