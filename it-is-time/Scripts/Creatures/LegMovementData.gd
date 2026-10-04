class_name LegMovementData
extends Resource
## Shared configuration only; all per-character timers and states stay in the controller.
@export_group("Stride")
@export var use_limb_length_ratios: bool = false
@export_range(0.01, 20.0, 0.01, "or_greater") var step_distance: float = 0.35
@export_range(0.01, 1.0, 0.01) var stride_length_ratio: float = 0.12
@export_range(0.0, 10.0, 0.01, "or_greater") var step_height: float = 0.25
@export_range(0.0, 1.0, 0.01) var lift_length_ratio: float = 0.1
@export_group("Timing")
## Total step starts per second, not cycles per foot. Support and landing may reduce actual frequency.
@export_range(0.1, 30.0, 0.1) var step_frequency: float = 2.0
@export_range(0.01, 5.0, 0.01) var swing_duration: float = 0.35
@export_group("Support")
@export_range(0.0, 1.0, 0.01) var maximum_stepping_ratio: float = 0.5
## Zero removes the additional absolute cap. One preserves sequential walking.
@export_range(0, 10, 1) var maximum_simultaneous_steps: int = 1
@export_range(0, 10, 1) var minimum_support_feet: int = 1
@export_group("Landing")
@export_range(0.001, 1.0, 0.001) var landing_tolerance: float = 0.18
@export_range(0.01, 5.0, 0.01) var landing_timeout: float = 1.0

func is_valid() -> bool:
	for value: float in [step_distance, step_frequency, swing_duration, landing_tolerance, landing_timeout]:
		if not is_finite(value) or value <= 0.0: return false
	for value: float in [stride_length_ratio, step_height, lift_length_ratio, maximum_stepping_ratio]:
		if not is_finite(value) or value < 0.0: return false
	return maximum_stepping_ratio <= 1.0 and maximum_simultaneous_steps >= 0 and minimum_support_feet >= 0
