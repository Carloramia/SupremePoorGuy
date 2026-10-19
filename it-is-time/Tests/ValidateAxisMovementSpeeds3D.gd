extends SceneTree

const AXIS = preload("res://Scripts/Creatures/AxisMovement3D.gd")
const GAIT = preload("res://Scripts/Creatures/LegMovementData.gd")
const SNAKE_DATA = preload("res://Scripts/Creatures/SnakeMotionData.gd")

class Commands extends Node:
	var direction := Vector3.ZERO
	var arrival_scale := 1.0
	func get_movement_direction() -> Vector3: return direction
	func get_npc_movement_speed_scale(_speed: float) -> float: return arrival_scale

class Charge extends Node:
	func owns_velocity() -> bool: return true

class Walker extends "res://Scripts/Creatures/LegStepMovementControllerBase3D.gd":
	var x_speed := 8.0
	func _ready() -> void: set_physics_process(false)
	func get_input_movement_direction() -> Vector3: return command_source.get_movement_direction()
	func get_player_command_source() -> Node: return command_source
	func _get_expected_horizontal_speed() -> float: return x_speed

class Snake extends "res://Scripts/Creatures/SnakeMovementController3D.gd":
	var commands: Node
	func _ready() -> void: set_physics_process(false)
	func _source() -> Node: return commands
	func get_input_movement_direction() -> Vector3: return commands.get_movement_direction()

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	for x_speed: float in [0.5, 3.0, 8.0, 20.0]:
		check(AXIS.target_velocity(Vector3.RIGHT,x_speed).is_equal_approx(Vector3.RIGHT*x_speed), "X must retain its existing target")
		check(AXIS.target_velocity(Vector3.LEFT,x_speed).is_equal_approx(Vector3.LEFT*x_speed), "Negative X must be symmetric")
		check(AXIS.target_velocity(Vector3.BACK,x_speed).is_equal_approx(Vector3.BACK*2.0), "Z must not inherit X speed")
		check(AXIS.target_velocity(Vector3.FORWARD,x_speed).is_equal_approx(Vector3.FORWARD*2.0), "Negative Z must be symmetric")
		var diagonal := Vector3(1,0,1).normalized()
		check(AXIS.target_velocity(diagonal,x_speed).is_equal_approx(Vector3(diagonal.x*x_speed,0,diagonal.z*2.0)), "Diagonal input must retain its original magnitude convention")
	check(AXIS.target_velocity(Vector3.ZERO,8).is_zero_approx(), "Idle must not request motion")
	check(AXIS.target_velocity(Vector3.BACK*0.5,8).is_equal_approx(Vector3.BACK), "Analog input must retain partial speed")
	check(AXIS.target_velocity(Vector3.BACK,8,0).is_zero_approx(), "Zero Z speed must disable lateral locomotion")
	check(AXIS.target_velocity(Vector3.INF,8).is_zero_approx(), "Invalid input must not submit invalid physics forces")
	check(AXIS.braking_correction(Vector3(10,0,4),Vector3(8,0,2)).is_equal_approx(Vector3(-2,0,-2)), "Braking must use each axis's own target")
	check(AXIS.braking_correction(Vector3(7,0,3),Vector3(8,0,2)).is_equal_approx(Vector3(0,0,-1)), "Z overspeed must not brake an X component below its target")
	check(AXIS.braking_correction(Vector3(-10,0,-4),Vector3(-8,0,-2)).is_equal_approx(Vector3(2,0,2)), "Negative-axis braking must be symmetric")
	var commands := Commands.new()
	root.add_child(commands)
	var walker := Walker.new()
	walker.command_source = commands
	root.add_child(walker)
	commands.direction = Vector3.BACK
	check(walker.get_expected_horizontal_velocity().is_equal_approx(Vector3.BACK*2), "Legacy walker must use the Z fallback")
	var gait := GAIT.new()
	gait.target_speed = 8.0
	var lateral_profile := gait.calculate_motion_profile(6.0,3.0,4,6.0,2.0)
	check(is_equal_approx(lateral_profile.target_speed,2.0), "Sideways gait planning must use the Z target")
	check(is_equal_approx(gait.target_speed,8.0), "Directional planning must not modify the shared X preset")
	var forward_profile := gait.calculate_motion_profile(6.0,3.0,4,6.0)
	check(is_equal_approx(forward_profile.target_speed,8.0), "Forward planning must preserve the original preset")
	var lateral_flight := gait.calculate_adaptive_flight_profile(6.0,4,0.0,2.0,4,0.0,2.0)
	check(is_equal_approx(lateral_flight.required_stride,2.0*lateral_flight.cycle), "Airborne stride must use the directional target")
	var rat_data := preload("res://Scripts/Creatures/RatsMovementData.gd").new()
	rat_data.target_speed = 8.0
	check(is_equal_approx(rat_data.calculate_motion_profile(2.0,1.0,4,2.0,2.0).target_speed,2.0), "Rat gait override must accept the directional speed")
	gait.target_z_speed = 1.25
	walker.slow_gait_data = gait
	check(walker.get_expected_horizontal_velocity().is_equal_approx(Vector3.BACK*1.25), "Assigned gait must own the Z setting")
	var charge := Charge.new()
	charge.name = "ChargeAttackController3D"
	root.add_child(charge)
	check(is_equal_approx(walker._get_requested_movement_speed(),gait.target_speed), "Attack-owned charge planning must retain its attack speed despite a lateral navigation request")
	charge.free()
	commands.arrival_scale = 0.5
	check(walker.get_expected_horizontal_velocity().is_equal_approx(Vector3.BACK*0.625), "NPC arrival braking must affect Z once")
	commands.arrival_scale = 1.0
	walker.set_turn_movement_multiplier(0.5)
	check(walker.get_expected_horizontal_velocity().is_equal_approx(Vector3.BACK*0.625), "Turn slowdown must apply to Z")
	walker.set_turn_movement_multiplier(1.0)
	walker.input_enabled = false
	check(walker.get_expected_horizontal_velocity().is_zero_approx(), "Disabled movement must remain idle")
	walker.input_enabled = true
	commands.direction = Vector3.RIGHT
	check(walker.get_expected_horizontal_velocity().is_equal_approx(Vector3.RIGHT*8), "Walker X must retain the existing speed calculation")
	var snake := Snake.new()
	snake.commands = commands
	snake.locomotion_enabled = true
	snake.motion_data = SNAKE_DATA.new()
	var navigation_origin := Node3D.new()
	navigation_origin.name = "NavigationOrigin"
	snake.add_child(navigation_origin)
	root.add_child(snake)
	commands.direction = Vector3.FORWARD
	check(snake.get_expected_horizontal_velocity().is_equal_approx(Vector3.FORWARD*2), "Snake must use independent Z speed")
	commands.direction = Vector3.RIGHT
	check(snake.get_expected_horizontal_velocity().is_equal_approx(Vector3.RIGHT*snake.motion_data.target_speed), "Snake X must retain its preset")
	var bird: Node = load("res://Scripts/Creatures/BirdFlightController3D.gd").new()
	bird.horizontal_speed = 12.0
	check(bird.get_horizontal_target_velocity(Vector3.BACK).is_equal_approx(Vector3.BACK*2), "Airborne Bird must use independent Z speed")
	check(bird.get_horizontal_target_velocity(Vector3.RIGHT).is_equal_approx(Vector3.RIGHT*12), "Airborne Bird X must retain its flight preset")
	for path: String in ["WolfWalk", "GeneratedMultiLegWalk", "SnakeMotion"]:
		var preset: Resource = load("res://Resources/Movement/"+path+".tres")
		check(is_equal_approx(preset.target_z_speed,2.0), path+" must inherit the new Z default")
		check(preset.is_valid(), path+" must remain valid")
	gait.target_z_speed = -1
	check(not gait.is_valid(), "Negative gait Z speed must be rejected")
	snake.motion_data.target_z_speed = NAN
	check(not snake.motion_data.is_valid(), "Invalid Snake Z speed must be rejected")
	bird.free()
	snake.free()
	walker.free()
	commands.free()
	print("AXIS_MOVEMENT_SPEEDS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
