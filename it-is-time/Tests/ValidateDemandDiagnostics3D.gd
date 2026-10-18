extends SceneTree
const MOVEMENT = preload("res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd")
const MODE = preload("res://Resources/Settings/PerformanceOptimization.tres")
var failed := false

# Fixed contacts isolate allocation/diagnostic work from solver and AI timing.
class SupportFixture extends MOVEMENT:
	func _stance_chain_can_support(foot: RigidBody3D) -> bool: return _chains.has(foot)
	func _get_stance_chain_contact(foot: RigidBody3D) -> Dictionary:
		return {"body":foot, "index":0, "position":foot.global_position}
	func _connected_body_segments(id: int) -> Array[int]: return [id]
	func _chain_is_intact(foot: RigidBody3D) -> bool: return _chains.has(foot)

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)

func body(parent: Node3D, name_value: String, at: Vector3, tag: int) -> PhysicalBodyPart3D:
	var part := PhysicalBodyPart3D.new()
	part.name = name_value
	part.tags = [tag]
	part.position = at
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	part.add_child(shape)
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	part.add_child(sprite)
	parent.add_child(part)
	return part

func fixture(index: int) -> SupportFixture:
	var host := Node3D.new()
	host.position.x = index * 10.0
	root.add_child(host)
	var parts := Node3D.new()
	parts.name = "GeneratedParts"
	host.add_child(parts)
	var torso := body(parts,"Torso",Vector3(0,2,0),0)
	var left := body(parts,"LegL",Vector3(-1,0,0),1)
	var right := body(parts,"LegR",Vector3(1,0,0),1)
	var controller := SupportFixture.new()
	controller.name = "GeneratedLegStepMovementController3D"
	controller.parts_root_path = NodePath("../GeneratedParts")
	controller.torso_path = NodePath("../GeneratedParts/Torso")
	host.add_child(controller)
	controller.set_physics_process(false)
	controller._torso = torso
	controller._legs.assign([left,right])
	controller._chains.clear()
	for foot in [left,right]:
		var joint := Generic6DOFJoint3D.new()
		joint.position = Vector3(foot.position.x * 0.5,1,0)
		parts.add_child(joint)
		controller._chains[foot] = {"bodies":[foot,torso], "joints":[joint], "root":torso, "stance_torques":[]}
	controller._segments = {0:{"mass":3.0, "center":torso.global_position, "bodies":[torso], "feet":[left,right], "auxiliary_force":0.0, "balanced":false}}
	controller._movement_perf.set_enabled(true)
	return controller

func batch(controllers: Array, enabled: bool) -> Dictionary:
	MODE.set("enabled",true)
	var started := Time.get_ticks_usec()
	for index: int in 40:
		for controller in controllers:
			controller._update_stance_allocation(0.2)
			if not enabled: controller._sample_stance_joint_loads()
	var result := {"usec":Time.get_ticks_usec()-started, "allocations":0, "diagnostic_updates":0, "joint_estimates":0}
	for controller in controllers:
		var counters: Dictionary = controller.consume_control_performance_stats().counters
		result.allocations += int(counters.get(&"stance_allocation_updates",0))
		result.diagnostic_updates += int(counters.get(&"stance_joint_diagnostic_updates",0))
		result.joint_estimates += int(counters.get(&"stance_joint_diagnostic_joints",0))
	return result

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var controllers: Array = []
	for index: int in 8: controllers.append(fixture(index))
	var original := batch(controllers,false)
	var weights: Array = controllers.map(func(controller): return controller._stance_support_weights.duplicate())
	var balanced: Array = controllers.map(func(controller): return controller._segments[0].balanced)
	var optimized := batch(controllers,true)
	check(original.allocations == 320 and optimized.allocations == 320, "Both modes must retain every real support allocation")
	check(original.joint_estimates == 640 and optimized.joint_estimates == 0, "Optimized idle controllers must skip unrequested joint estimates")
	for index: int in controllers.size():
		var controller = controllers[index]
		check(controller._stance_support_weights == weights[index] and controller._segments[0].balanced == balanced[index], "Diagnostic deferral preserves physical support weights and balance")
		var velocity: Vector3 = controller._torso.linear_velocity
		var torque_velocity: Vector3 = controller._torso.angular_velocity
		var sampled: Dictionary = controller.get_generated_movement_diagnostics()
		check(not sampled.feet.is_empty() and controller._stance_joint_loads.size() == 2, "Requested snapshot still contains joint loads")
		controller.get_generated_movement_diagnostics()
		check(controller.consume_control_performance_stats().counters.get(&"stance_joint_diagnostic_updates",0) == 1, "Repeated snapshots reuse one allocation's diagnostic result")
		check(controller._torso.linear_velocity == velocity and controller._torso.angular_velocity == torque_velocity, "Reading diagnostics never applies motion")
	MODE.set("enabled",false)
	controllers[0]._update_stance_allocation(0.2)
	check(controllers[0].consume_control_performance_stats().counters.get(&"stance_joint_diagnostic_updates",0) == 1, "Disabling performance mode restores eager diagnostics")
	MODE.set("enabled",true)
	for controller in controllers:
		controller.get_parent().queue_free()
	await process_frame
	print("DEMAND_DIAGNOSTIC_BENCHMARK eager=",original," optimized=",optimized," controllers=8 isolated_allocation_only=true")
	print("DEMAND_DIAGNOSTICS_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
