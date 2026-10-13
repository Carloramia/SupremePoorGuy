@tool
extends "res://Scripts/Creatures/CreatureAttackData.gd"
## Pounce distances/time/speed are reference values for reference_body_length.
## Melee timing stays in seconds; pounce time and speed scale with sqrt(body size).
@export_group("AI Distance")
## Fraction of the dynamic legal range used as the preferred stopping distance.
@export_range(0.0, 1.0, 0.01) var preferred_range_ratio := 0.8
@export_range(0.001, 0.1, 0.001) var distance_tolerance_body_ratio := 0.025
@export_group("Pounce")
## Authored torso length at scale 1; distances follow the generated torso, not the generator setting.
@export_range(0.01, 100.0, 0.01, "or_greater") var reference_body_length := 6.5
@export_range(0.1, 100.0, 0.1) var minimum_range := 3.0
@export_range(0.1, 100.0, 0.1) var maximum_range := 12.0
@export_range(0.2, 3.0, 0.01) var flight_time := 0.7
@export_range(0.0, 5.0, 0.01) var minimum_lift_height := 0.5
@export_range(0.1, 1.0, 0.01) var landing_reach_ratio := 0.8
@export_range(0.0, 50.0, 0.5) var landing_braking_gain := 15.0
@export_range(0.0, 1.0, 0.01) var combo_window := 0.22
## Predict over the full flight; smooth target velocity without delaying the first observation.
@export_range(0.0, 1.0, 0.01) var pounce_velocity_smoothing_time := 0.15
@export_range(0.0, 0.2, 0.01) var pounce_range_margin_ratio := 0.03
@export_range(1.0, 100.0, 0.1) var maximum_launch_speed := 25.0
@export_range(0.0, 1.0, 0.01) var landing_timeout := 0.5
## Settle stepping feet before charge; forecast this delay, abort if terrain cannot support launch.
@export_range(0.0, 1.0, 0.01) var pounce_plant_prediction_time := 0.25
@export_range(0.1, 3.0, 0.01) var pounce_plant_timeout := 1.0
## Retain running qualification while AI brakes to prepare a grounded launch.
@export_range(0.0, 1.0, 0.01) var pounce_gallop_grace_time := 0.5
## Grounded preparation before launch; included in target interception prediction.
@export_range(0.05, 2.0, 0.01) var pounce_charge_time := 0.6
@export_range(0.0, 0.3, 0.01) var pounce_charge_retract_ratio := 0.06
@export_range(0.0, 0.3, 0.01) var pounce_charge_crouch_ratio := 0.06
## Airborne foreleg targets relative to the leg root, scaled by chain length.
@export_range(0.0, 0.8, 0.01) var pounce_foreleg_retract_ratio := 0.25
@export_range(0.0, 0.8, 0.01) var pounce_foreleg_extend_ratio := 0.45
@export_range(0.1, 0.9, 0.01) var pounce_foreleg_fold_drop_ratio := 0.35
@export_group("Physical Tracking")
@export_range(0.0, 200.0, 1.0) var position_gain := 80.0
@export_range(0.0, 100.0, 1.0) var velocity_gain := 16.0
@export_range(1.0, 500.0, 1.0) var maximum_acceleration := 120.0
@export_group("Bite")
## Bite recovery timing only; claw recovery uses measured completion.
@export_range(0.01, 2.0, 0.01) var recovery_time := 0.2
@export var jaw_key: StringName = &"LowerJaw"
@export var head_key: StringName = &"Head"
@export_range(0.0, 75.0, 0.5) var jaw_open_degrees := 30.0
@export_range(0.01, 2.0, 0.01) var jaw_open_time := 0.2
@export_range(0.01, 2.0, 0.01) var jaw_close_time := 0.12
@export_range(0.0, 500.0, 1.0) var angular_strength := 160.0
@export_range(0.0, 100.0, 1.0) var angular_damping := 20.0
@export_range(0.0, 500.0, 1.0) var maximum_angular_acceleration := 180.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var maximum_torque := 250.0
@export_group("Bite Body Motion")
@export_range(0.05, 10.0, 0.01) var bite_plant_timeout := 4.0
## Horizontal head-to-target distance, retreat distance and duration before planting.
@export_range(0.0, 1.0, 0.01) var bite_close_distance_ratio := 0.25
@export_range(0.0, 0.3, 0.01) var bite_spacing_retreat_ratio := 0.08
@export_range(0.05, 1.0, 0.01) var bite_spacing_retreat_time := 0.25
@export_range(0.01, 0.5, 0.01) var bite_retract_ratio := 0.08
## Torso descent as a fraction of body length during the backward charge.
@export_range(0.0, 0.3, 0.01) var bite_crouch_ratio := 0.08
## Duration of the combined crouch and backward charge.
@export_range(0.05, 2.0, 0.01) var bite_retract_time := 0.35
@export_range(0.01, 0.5, 0.01) var bite_advance_ratio := 0.18
@export_range(0.1, 30.0, 0.1) var bite_lunge_speed := 6.0
@export_range(0.05, 2.0, 0.01) var bite_lunge_timeout := 0.6
## Duration and acceleration of the sustained forward burst, after the initial impulse.
@export_range(0.01, 1.0, 0.01) var bite_lunge_acceleration_time := 0.3
@export_range(0.0, 200.0, 1.0) var bite_lunge_acceleration := 45.0
@export_group("Damage Box")
## Positive HP damage knocks lighter enemies into ragdoll; repeated hits refresh it.
@export_range(0.0, 5.0, 0.05, "or_greater") var hit_ragdoll_duration := 1.0
@export var box_size_ratio := Vector3(1.1, 1.1, 1.5)
@export var box_center_ratio := Vector3.ZERO
@export_range(0.01, 10.0, 0.01) var impulse_multiplier := 1.0
