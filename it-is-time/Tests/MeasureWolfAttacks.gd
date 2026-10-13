extends SceneTree
class Command:
	extends Node
	var direction := Vector3.ZERO
	func get_movement_direction() -> Vector3: return direction
	func is_fast_movement_requested() -> bool: return false
	func is_jump_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300,1,100)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = 0.5
	root.add_child(floor_body)
	var actor = load("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn").instantiate()
	actor.generate_on_ready = false
	actor.position.y = 4.0
	root.add_child(actor)
	var command := Command.new()
	actor.add_child(command)
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	movement.command_source = command
	var ai = actor.get_node("NPCStateMachine3D")
	ai.set_physics_process(false)
	actor.get_node("CreatureRecoveryStateMachine3D").set_physics_process(false)
	movement.recovery_control_active = false
	var attacks = actor.get_node("WolfAttackController3D")
	attacks.diagnostic_logging = "--verbose" in OS.get_cmdline_user_args()
	var measure_spacing := "--spacing" in OS.get_cmdline_user_args()
	if measure_spacing:
		var bite = attacks.get_node("Bite")
		bite.data = bite.data.duplicate()
		bite.data.bite_close_distance_ratio = 1.0
	var enemy = load("res://Scenes/Creatures/Characters/Generate_Wolf.tscn").instantiate()
	enemy.generate_on_ready = false
	enemy.position = Vector3(70,4,0)
	enemy.faction_id = 2
	root.add_child(enemy)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	for body: RigidBody3D in enemy._get_physical_body_parts():
		body.freeze = true
		body.max_hp = 100000.0
		body.current_hp = 100000.0
	var target: PhysicalBodyPart3D = enemy.get_node("GeneratedParts/Torso")
	var measure_plant := "--plant" in OS.get_cmdline_user_args()
	var plant_seen := false
	var priority_checked := false
	var started := false
	var finished := false
	var combo_bite := false
	var bite_stages: Array[StringName] = []
	var bite_lunge_start := Vector3.ZERO
	var bite_lunge_travel := 0.0
	var bite_burst_elapsed := 0.0
	var charge_feet_checked := false
	var spacing_travel := 0.0
	var spacing_seen := false
	var foreleg_mid: Dictionary = {}
	var foreleg_late: Dictionary = {}
	var maximum_lift := 0.0
	var launch_height := 0.0
	var locked := Vector3.ZERO
	var launched := false
	var end_frame := -1
	for frame: int in range(1200):
		await physics_frame
		movement.input_enabled = true
		movement.set_physics_process(true)
		if frame == 120: command.direction = Vector3.RIGHT
		if frame == 210:
			# Real NPC selector, real prediction, real solver; approach travel is supplied by fixture.
			var displacement: Vector3 = movement._torso.global_position+Vector3.RIGHT*maxf(16.0,attacks.get_npc_attack_maximum_range(&"wolf_bite",target)+6.0)-target.global_position
			for body: RigidBody3D in enemy._get_physical_body_parts(): body.global_position += displacement
			ai._enemy = enemy
			ai._target = target
			ai.behavior = ai.behavior.duplicate(true)
			ai.behavior.attacks.resize(1)
		if frame >= 212 and not started:
			if measure_plant:
				for foot: RigidBody3D in movement.get_leg_parts(): movement._release_support_pin(foot)
			var distance: float = movement._torso.global_position.distance_to(target.global_position)
			if attacks.should_prepare_npc_attack(&"wolf_pounce",target):
				ai._attack_retry = 0.4
				assert(not ai._plan_attack_distance(distance,ai.behavior.attacks),"Viable pounce must hold ordinary distance repositioning")
				assert(ai._distance_attack.action_id == &"wolf_pounce" and ai._attack_retry <= 0.05,"Pounce preparation must promptly retry the normal attack selector")
				priority_checked = true
			started = ai._try_attack(distance)
			if started and measure_plant:
				plant_seen = attacks.get_node("Pounce")._phase == &"planting"
				assert(plant_seen,"Missing support pins must enter planting instead of waiting for normal gait")
			if started:
				launch_height = movement._torso.global_position.y
				locked = attacks.get_node("Pounce").locked_position
		if started:
			maximum_lift = maxf(maximum_lift,movement._torso.global_position.y-launch_height)
			combo_bite = combo_bite or attacks.get_node("Bite").active
			var bite = attacks.get_node("Bite")
			if bite.active and not bite_stages.has(bite._phase): bite_stages.append(bite._phase)
			if bite.active and bite._phase == &"spacing_retreat":
				spacing_seen = true
				assert(bite._foot_plans.is_empty(),"Foot planning must wait until retreat completes")
				assert(movement._support_pins.is_empty(),"Retreat must release ground pins")
				spacing_travel = maxf(spacing_travel,(bite._spacing_origin-movement._torso.global_position).dot(bite._forward))
			if bite.active and bite._phase == &"charging" and not charge_feet_checked:
				assert(bite._repositioned_feet == bite.owned_feet.size(),"Every foot must finish repositioning before charge")
				assert(bite._support_count > 0,"Charge needs grounded support after blocked feet are skipped")
				charge_feet_checked = true
			if bite.active and bite._phase == &"lunging":
				if bite_lunge_start == Vector3.ZERO: bite_lunge_start = movement._torso.global_position
				bite_lunge_travel = maxf(bite_lunge_travel,(movement._torso.global_position-bite_lunge_start).dot(bite._forward))
				bite_burst_elapsed = maxf(bite_burst_elapsed,bite._phase_time)
			if attacks.is_pouncing() and attacks.get_node("Pounce")._phase == &"flying":
				if not launched:
					var launching = attacks.get_node("Pounce")
					assert(launching._support_count >= maxi(1,ceili(launching.owned_feet.size()*0.5)),"Launch requires half the feet in real grounded support")
					locked = launching.locked_position
					launched = true
				assert(attacks.get_node("Pounce").locked_position == locked,"Airborne pounce destination must remain fixed")
				var pounce = attacks.get_node("Pounce")
				var progress: float = pounce._phase_time/pounce.flight_duration
				for row: Dictionary in pounce._foreleg_flight:
					var chain: Dictionary = movement._chains[row.foot]
					var relative: Vector3 = row.foot.global_position-chain.root.to_global(chain.anchor)
					if progress >= 0.45 and progress <= 0.55: foreleg_mid[row.foot.name] = relative.dot(pounce._flight_forward)
					if progress >= 0.85 and progress <= 0.95: foreleg_late[row.foot.name] = relative.dot(pounce._flight_forward)
			if not attacks.is_npc_attack_active() and not finished:
				finished = true
				end_frame = frame
		if finished and frame > end_frame+60: break
		assert(movement._torso.global_position.is_finite())
	var forelegs_moved := foreleg_mid.size() == 2 and foreleg_late.size() == 2
	for key: StringName in foreleg_mid:
		forelegs_moved = forelegs_moved and foreleg_late.get(key,-INF)>float(foreleg_mid[key])+0.3
	print("WOLF_POUNCE_FORELEGS mid=",foreleg_mid," late=",foreleg_late," moved=",forelegs_moved)
	var damage := 0.0
	for body: RigidBody3D in enemy._get_physical_body_parts(): damage += 100000.0-body.current_hp
	print("WOLF_ATTACK_PHYSICS started=",started," finished=",finished," lift=",maximum_lift," bite=",combo_bite," bite_stages=",bite_stages," damage=",damage," spacing_travel=",spacing_travel," bite_lunge_travel=",bite_lunge_travel," burst_elapsed=",bite_burst_elapsed," rejection=",ai._attack_block_reason," predictions=",ai._attack_predictions)
	var passed: bool = priority_checked and (not measure_plant or plant_seen) and started and launched and finished and maximum_lift>0.05 and combo_bite and damage>0.0 and movement._action_feet.is_empty() and &"lunging" in bite_stages and &"closing" in bite_stages and charge_feet_checked and bite_lunge_travel>0.5 and bite_burst_elapsed>=0.25 and forelegs_moved and (not measure_spacing or spacing_seen and spacing_travel>0.1)
	actor.free(); enemy.free()
	quit(0 if passed else 1)
