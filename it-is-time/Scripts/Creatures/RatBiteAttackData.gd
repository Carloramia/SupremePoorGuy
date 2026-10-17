@tool
extends "res://Scripts/Creatures/CreatureAttackData.gd"

@export_group("Preparation")
@export var head_key: StringName = &"Head"
@export var jaw_key: StringName = &"LowerJaw"
@export_range(0.05,2.0,0.01) var preparation_time := 0.3
@export_range(0.0,0.5,0.01) var preparation_extra_wait := 0.2
@export_range(0.0,75.0,0.5) var jaw_open_degrees := 32.0
@export_range(0.01,1.0,0.01) var jaw_close_time := 0.12
@export_range(0.0,0.5,0.01) var jaw_close_extra_wait := 0.2
@export_range(0.0,0.5,0.01) var foreleg_lift_ratio := 0.1

@export_group("Static Target Strike")
## Distances follow the generated Torso length. Target velocity is never extrapolated.
@export_range(0.05,2.0,0.01) var maximum_extension_ratio := 0.5
@export_range(0.05,3.0,0.05) var strike_speed_body_lengths := 1.8
@export_range(0.1,5.0,0.05) var strike_timeout := 1.5
@export_range(0.005,0.2,0.005) var arrival_tolerance_ratio := 0.04
@export_range(0.1,1.0,0.01) var preferred_range_ratio := 0.7
@export_range(0.001,0.1,0.001) var distance_tolerance_body_ratio := 0.025

@export_group("Physical Tracking")
@export_range(1.0,300.0,1.0) var position_gain := 120.0
@export_range(1.0,100.0,1.0) var velocity_gain := 24.0
@export_range(1.0,500.0,1.0) var maximum_acceleration := 120.0
@export_range(1.0,500.0,1.0) var angular_strength := 160.0
@export_range(1.0,100.0,1.0) var angular_damping := 20.0
@export_range(1.0,500.0,1.0) var maximum_angular_acceleration := 180.0
@export_range(0.0,1000.0,1.0,"or_greater") var maximum_torque := 250.0

@export_group("Damage Box")
@export var box_size_ratio := Vector3(1.1,1.1,4.0)
@export var box_center_ratio := Vector3(0.15,0.05,0)
@export_range(0.01,30.0,0.01) var impulse_multiplier := 12.0
@export_range(0.0,5.0,0.05) var hit_ragdoll_duration := 1.0
