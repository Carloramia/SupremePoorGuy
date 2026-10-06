extends SceneTree
const BASE = preload("res://Scripts/Creatures/LegStepMovementControllerBase3D.gd")
class Harness extends BASE:
	var command := Vector3.RIGHT
	var blocked: Dictionary = {}
	var urgent: Dictionary = {}
	var paused := false
	func _ready() -> void: set_physics_process(false)
	func _update_active_step(_delta: float) -> void: pass
	func get_input_movement_direction() -> Vector3: return command
	func is_fast_speed_active() -> bool: return false
	func _walk_start_stagger_ready() -> bool: return not paused and super._walk_start_stagger_ready()
	func _walk_start_emergency(leg: RigidBody3D) -> bool: return urgent.has(leg)
	func _can_start_step_with_support(leg: RigidBody3D) -> bool:
		return not blocked.has(leg) and not is_leg_stepping(leg) and _active_steps.size()<3
	func find_landing_point(leg: RigidBody3D, direction: Vector3 = Vector3.RIGHT) -> Dictionary:
		return {"position":leg.global_position+direction*0.5,"normal":Vector3.UP}
	func attempt(leg: RigidBody3D) -> bool:
		_current_step = StepMotion.new()
		_next_leg_index = _legs.find(leg)
		return try_start_step(command)
var failed := false
func check(value: bool,message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func tick(h: Harness,count: int=1) -> void:
	for index: int in range(count):
		await physics_frame
		h._physics_elapsed += 1.0/60.0
		h._update_walk_start_stagger(1.0/60.0,h.command)
func run() -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var h := Harness.new()
	actor.add_child(h)
	var torso := RigidBody3D.new()
	torso.freeze = true
	actor.add_child(torso)
	h._torso = torso
	var data := BASE.GAIT_DATA.new()
	data.automatic_motion = false
	data.maximum_stepping_ratio = 1.0
	data.maximum_simultaneous_steps = 3
	data.minimum_support_feet = 1
	h.slow_gait_data = data
	for index: int in range(4):
		var foot := RigidBody3D.new()
		foot.name = "Foot_%d" % index
		foot.gravity_scale = 0.0
		foot.position = Vector3(index/2,0,-1 if index%2==0 else 1)
		actor.add_child(foot)
		h._legs.append(foot)
	await tick(h)
	check(h._walk_start_pending.size()==4,"Starting walk must include every available foot")
	var first: RigidBody3D = h._walk_start_pending[0]
	h.blocked[first] = true
	var second: RigidBody3D = h._walk_start_pending[1]
	check(not h.attempt(first),"Unsafe first foot must not launch")
	check(h.attempt(second),"First safe foot must launch without delay")
	h.blocked.clear()
	check(not h.attempt(first),"Same-frame startup launch must be blocked")
	await tick(h)
	check(not h.attempt(first),"Following foot must wait for stagger spacing")
	var count := h._walk_start_pending.size()
	h.command = Vector3.LEFT
	await tick(h)
	check(h._walk_start_pending.size()==count,"Direction reversal must preserve unstarted feet")
	check(h.is_leg_stepping(second),"Direction reversal must preserve active swing")
	await tick(h,ceili(h._walk_start_interval*60.0)+1)
	var next: RigidBody3D = h._walk_start_pending[0]
	check(h.attempt(next),"Next eligible foot must launch after spacing")
	await tick(h)
	var emergency: RigidBody3D = h._walk_start_pending[0]
	h.urgent[emergency] = true
	h.blocked[emergency] = true
	check(not h.attempt(emergency),"Emergency cannot bypass support requirements")
	check(is_equal_approx(h._walk_start_drive_scale(),0.35),"Blocked urgent foot must reduce target speed")
	h.blocked.clear()
	check(h.attempt(emergency),"Emergency must bypass only stagger delay")
	check(h._walk_start_bypasses>0,"Diagnostics must count emergency bypasses")
	var remaining: RigidBody3D = h._walk_start_pending[0]
	remaining.freeze = true
	await tick(h)
	check(h._walk_start_pending.is_empty(),"Unavailable foot must leave startup schedule")
	h.command = Vector3.ZERO
	await tick(h,15)
	check(not h._walk_start_input_active,"Confirmed stop must rearm startup")
	h.cancel_step(&"test")
	remaining.freeze = false
	h.urgent.clear()
	h.command = Vector3.RIGHT
	await tick(h)
	check(h._walk_start_pending.size()==4,"Repeated start must stagger again")
	h.paused = true
	await tick(h,30)
	check(h._walk_start_pending.is_empty(),"Suspended control must not accumulate stagger deadlines")
	h.paused = false
	await tick(h)
	check(h._walk_start_pending.size()==4 and h._walk_start_last_start==-INF,"Resumed control must start a fresh sequence")
	h.walk_start_stagger_enabled = false
	await tick(h)
	check(h._walk_start_pending.is_empty() and h._walk_start_stagger_allows(first),"Switch off must restore normal admission")
	h.cancel_step(&"test")
	h.walk_start_stagger_enabled = true
	h._reset_walk_start_stagger()
	await tick(h)
	var scheduled_first: RigidBody3D = h._walk_start_pending[0]
	h._update_resource_gait(1.0/60.0,h.command)
	check(h.is_leg_stepping(scheduled_first),"Resource scheduler must honor startup priority")
	var first_frame := h._walk_start_last_frame
	h._next_resource_step_time = h._physics_elapsed
	h._update_resource_gait(1.0/60.0,h.command)
	check(h._active_steps.size()==1,"Resource scheduler must not catch up starts in same frame")
	await tick(h,30)
	h._next_resource_step_time = h._physics_elapsed
	h._update_resource_gait(1.0/60.0,h.command)
	check(h._active_steps.size()==2 and h._walk_start_last_frame>first_frame,"Resource scheduler must admit the next separated start")
	h.cancel_step(&"test")
	h._reset_walk_start_stagger()
	data.automatic_motion = true
	data.maximum_step_frequency = 1.0
	h._last_shared_step_start = h._physics_elapsed
	await tick(h)
	check(h._automatic_step_cadence_allows(),"Previous cadence deadline must not delay first safe startup foot")
	actor.queue_free()
	await process_frame
	print("WALK_START_STAGGER_PASSED" if not failed else "WALK_START_STAGGER_FAILED")
	quit(1 if failed else 0)
