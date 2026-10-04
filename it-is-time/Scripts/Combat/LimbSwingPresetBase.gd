class_name LimbSwingPresetBase
extends Resource

## Shared charge, lift, and swing tuning inherited by concrete swing resources.

@export_group("Charge")
@export_range(0.0, 5.0, 0.01) var minimum_charge_time: float = 0.15
@export_range(0.01, 10.0, 0.01, "or_greater") var maximum_charge_time: float = 1.5
@export_range(1.0, 179.0, 1.0) var lift_angle_degrees: float = 115.0
@export_enum("X:0", "Y:1", "Z:2") var joint_axis: int = 2
@export_range(0.0, 1000.0, 1.0, "or_greater") var lift_spring_stiffness: float = 160.0
@export_range(0.0, 500.0, 1.0, "or_greater") var lift_spring_damping: float = 35.0

@export_group("Selected Target Aim")
@export var target_aim_enabled: bool = true
@export_range(0.0, 1000.0, 1.0, "or_greater") var target_aim_stiffness: float = 45.0
@export_range(0.0, 500.0, 0.1, "or_greater") var target_aim_damping: float = 8.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var maximum_target_aim_torque: float = 35.0

@export_group("Charge Angle Drag")
@export var charge_angle_drag_enabled: bool = true
## Degrees per horizontal mouse pixel; positive drags bank around the direction toward the target.
@export_range(0.01, 5.0, 0.01, "or_greater") var charge_angle_drag_sensitivity: float = 0.4
@export_range(0.0, 180.0, 1.0) var maximum_charge_bank_degrees: float = 180.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var charge_bank_stiffness: float = 80.0
@export_range(0.0, 500.0, 0.1, "or_greater") var charge_bank_damping: float = 12.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var maximum_charge_bank_torque: float = 100.0

@export_group("Swing")
@export_range(0.0, 1000.0, 1.0, "or_greater") var minimum_swing_torque: float = 30.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var maximum_swing_torque: float = 150.0
@export_range(0.01, 2.0, 0.01, "or_greater") var swing_duration: float = 0.3
@export_range(0.0, 2.0, 0.01) var cooldown_duration: float = 0.3

@export_group("Sustained Swing")
@export var sustained_swing_enabled: bool = true
@export_range(0.0, 2000.0, 1.0, "or_greater") var sustained_swing_torque: float = 30.0
## Starts at release and can continue past the initial explosive swing into follow through.
@export_range(0.0, 5.0, 0.01, "or_greater") var sustained_swing_duration: float = 0.25

@export_group("Follow Through")
@export_range(0.0, 1000.0, 1.0, "or_greater") var direction_hold_stiffness: float = 160.0
@export_range(0.0, 500.0, 0.1, "or_greater") var direction_hold_damping: float = 12.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var maximum_direction_hold_torque: float = 350.0
@export_range(0.0, 10.0, 0.1, "or_greater") var follow_through_ratio: float = 2.0
@export_range(0.0, 2.0, 0.01, "or_greater") var minimum_follow_through_time: float = 0.15

@export_group("Recovery")
@export_range(0.0, 2.0, 0.01, "or_greater") var recovery_duration: float = 0.3
@export_range(0.0, 5.0, 0.01, "or_greater") var maximum_recovery_extension: float = 0.7
@export_range(0.0, 1000.0, 1.0, "or_greater") var recovery_stiffness: float = 80.0
@export_range(0.0, 500.0, 0.1, "or_greater") var recovery_damping: float = 12.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var maximum_recovery_torque: float = 100.0
