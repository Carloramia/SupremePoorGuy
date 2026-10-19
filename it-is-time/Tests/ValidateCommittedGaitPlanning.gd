extends SceneTree

var failed := false
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var scenes := ["Generate_Wolf_NPC","Generate_StumpBeast_NPC","Generate_HornedBeast_NPC","Generate_Spider_NPC","Generate_Rat_1_NPC","Generate_Human_NPC","Generate_Bird_NPC","Character_Test_NPC"]
	for scene: String in scenes:
		var actor: Node3D = load("res://Scenes/Creatures/Characters/"+scene+".tscn").instantiate()
		if "generate_on_ready" in actor: actor.generate_on_ready = false
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(actor)
		var movement: Node = actor.get_node_or_null("GeneratedLegStepMovementController3D")
		if movement == null: movement = actor.get_node("NPCLegStepMovementController3D")
		for body: Node in actor.find_children("*","RigidBody3D",true,false): body.freeze = true
		var foot: RigidBody3D = movement.get_leg_parts()[0]
		movement._begin_leg_motion(foot,foot.global_position+Vector3.RIGHT,Vector3.UP,Vector3.RIGHT)
		movement._step_elapsed = movement._active_step_duration*0.7
		movement._landing_elapsed = 0.08
		movement._grounded_confirmation_elapsed = 0.03
		var motion = movement._current_step
		var target: Vector3 = motion.target
		var duration: float = motion.duration
		var elapsed: float = motion.elapsed
		var start: Vector3 = motion.start
		var profile: Dictionary = motion.extra.get("automatic_profile",{}).duplicate(true)
		var specialized: Dictionary = motion.extra.get("wolf_step",{}).duplicate(true)
		for phase in [movement.StepState.MOVING,movement.StepState.LANDING]:
			movement._step_state = phase
			for i in 40:
				movement._physics_elapsed += 1.0/60.0
				var direction := Vector3.LEFT if i%2==0 else Vector3.FORWARD
				check(not movement.replan_active_step(direction),scene+": direction changes wait until landing")
				check(movement._current_step==motion and motion.target==target and motion.start==start,scene+": keep the same committed trajectory")
				check(motion.elapsed==elapsed and motion.duration==duration and is_equal_approx(motion.landing_elapsed,0.08) and is_equal_approx(motion.confirmation,0.03),scene+": never reset swing, descent or braking timers")
			check(motion.extra.get("automatic_profile",{})==profile and motion.extra.get("wolf_step",{})==specialized,scene+": retain species-specific stages and force budgets")
		var diag: Dictionary = movement.get_leg_step_diagnostics(foot)
		check(diag.plan.deferred_replans==80 and diag.plan.age>1.0,scene+": expose deferred input changes and true plan age")
		movement.cancel_step()
		movement._begin_leg_motion(foot,foot.global_position+Vector3.FORWARD,Vector3.UP,Vector3.FORWARD)
		check(movement._current_step.direction==Vector3.FORWARD,scene+": the next step accepts the latest input")
		actor.free()
		await process_frame
	print("COMMITTED_GAIT_PLANNING_", "FAILED" if failed else "PASSED", " checks=",checks," presets=",scenes.size())
	quit(1 if failed else 0)
