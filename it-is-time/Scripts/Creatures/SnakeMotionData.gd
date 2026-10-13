@tool
class_name SnakeMotionData
extends Resource

@export_group("Movement")
@export_range(0.0, 50.0, 0.1, "or_greater") var target_speed: float = 5.0
@export_range(0.05, 2.0, 0.01) var velocity_response_time: float = 0.35
@export_range(0.0, 100.0, 0.1, "or_greater") var maximum_acceleration: float = 18.0

@export_group("Raised Pose")
## Angular/position acceleration gains; strength is independent of part mass.
@export_range(0.0, 200.0, 0.5) var raised_pose_strength: float = 35.0
@export_range(0.0, 50.0, 0.1) var raised_pose_damping: float = 12.0
@export_range(0.0, 200.0, 0.5) var maximum_pose_acceleration: float = 40.0
@export_range(0.0, 200.0, 0.5) var maximum_angular_acceleration: float = 30.0
## Final torque cap, applied after inertia scaling.
@export_range(0.0, 1000000.0, 10.0, "or_greater") var maximum_pose_torque: float = 1000000.0
@export_range(0.0, 0.5, 0.01) var support_release_time: float = 0.12

@export_group("Turning")
@export_range(0.0, 360.0, 1.0) var turn_speed_degrees: float = 90.0
@export_range(0.05, 2.0, 0.01) var turn_response_time: float = 0.5

@export_group("Trajectory Following")
@export var trajectory_following_enabled: bool = true
## Used only by the optional legacy local-frame follower, not the shared ground path.
@export_range(0.0, 0.5, 0.01) var trajectory_follow_delay: float = 0.05

@export_group("Ground S Path")
## Requires Sway and Trajectory Following enabled, Head Orbit disabled. Keeps idle upper sway.
@export var ground_path_enabled: bool = true
## One spatial cycle relative to the authored raised-chain length; independent of speed.
@export_range(0.5, 4.0, 0.05, "or_greater") var path_wavelength_ratio: float = 1.0
## Fraction of the joint-safe lateral amplitude reserved for the route.
@export_range(0.0, 1.0, 0.01) var path_amplitude_ratio: float = 0.8
## Relative Z sliding in actual PartWidth units, only while the shared route owns motion.
@export_range(1.0, 10.0, 0.1, "or_greater") var path_joint_slide_widths: float = 4.0
@export_range(0.1, 2.0, 0.05) var path_transition_time: float = 0.5

@export_group("Path Execution")
## Smooth the physical reference without changing the sharp world route.
@export_range(0.1, 1.0, 0.01) var path_execution_response_time: float = 0.25
## Horizontal reference and combined drive acceleration change per second.
@export_range(1.0, 1000.0, 1.0, "or_greater") var path_maximum_jerk: float = 180.0
## Physical rounding allowance in generated PartWidth units; not a teleport/clamp.
@export_range(0.1, 10.0, 0.1, "or_greater") var path_corner_rounding_widths: float = 2.0

@export_group("Segment Spacing Wave")
## Stretch arc-length spacing only between parts authored as the grounded body.
@export var spacing_wave_enabled: bool = true
## Fraction of the fifteen-percent arc-length allowance, reduced for tracking acceleration.
@export_range(0.0, 0.8, 0.01) var spacing_wave_amplitude_ratio: float = 0.8
@export_range(0.5, 8.0, 0.1) var spacing_wave_frequency_ratio: float = 2.0
@export_range(-180.0, 180.0, 1.0) var spacing_wave_phase_degrees: float = 0.0

@export_group("Head Orbit")
@export var head_orbit_enabled: bool = false
## Radius in generated physical PartWidth units, in the character's local XY plane.
@export_range(0.0, 10.0, 0.1, "or_greater") var head_orbit_radius_widths: float = 2.0
@export_range(0.2, 10.0, 0.05, "or_greater") var head_orbit_period: float = 4.0

@export_group("Z Wave")
@export var sway_enabled: bool = true
## Idle/legacy cycle spans Head to the first originally grounded Torso; period = links * delay.
@export_range(0.05, 2.0, 0.01, "or_greater") var sway_segment_delay: float = 0.2
## Fraction of the maximum sine amplitude compatible with every relative joint limit.
@export_range(0.0, 1.0, 0.01) var sway_amplitude_ratio: float = 0.8
@export_range(0.1, 2.0, 0.05, "or_greater") var sway_transition_time: float = 0.5
@export_range(0.0, 2.0, 0.01) var sway_stop_speed: float = 0.15

func is_valid() -> bool:
	for value: float in [target_speed, maximum_acceleration,
		raised_pose_strength, raised_pose_damping, maximum_pose_acceleration,
		maximum_angular_acceleration, maximum_pose_torque, support_release_time, turn_speed_degrees,
		sway_stop_speed, trajectory_follow_delay, head_orbit_radius_widths]:
		if not is_finite(value) or value < 0.0: return false
	return is_finite(velocity_response_time) and velocity_response_time >= 0.05 \
		and is_finite(turn_response_time) and turn_response_time >= 0.05 \
		and is_finite(sway_segment_delay) and sway_segment_delay >= 0.05 \
		and is_finite(sway_amplitude_ratio) and sway_amplitude_ratio >= 0.0 and sway_amplitude_ratio <= 1.0 \
		and is_finite(sway_transition_time) and sway_transition_time >= 0.1 \
		and is_finite(head_orbit_period) and head_orbit_period >= 0.2 \
		and is_finite(path_wavelength_ratio) and path_wavelength_ratio >= 0.5 \
		and is_finite(path_amplitude_ratio) and path_amplitude_ratio >= 0.0 and path_amplitude_ratio <= 1.0 \
		and is_finite(path_joint_slide_widths) and path_joint_slide_widths >= 1.0 \
		and is_finite(path_transition_time) and path_transition_time >= 0.1 \
		and is_finite(path_execution_response_time) and path_execution_response_time >= 0.1 \
		and is_finite(path_maximum_jerk) and path_maximum_jerk >= 1.0 \
		and is_finite(path_corner_rounding_widths) and path_corner_rounding_widths >= 0.1 \
		and is_finite(spacing_wave_amplitude_ratio) and spacing_wave_amplitude_ratio >= 0.0 and spacing_wave_amplitude_ratio <= 0.8 \
		and is_finite(spacing_wave_frequency_ratio) and spacing_wave_frequency_ratio >= 0.5 and spacing_wave_frequency_ratio <= 8.0 \
		and is_finite(spacing_wave_phase_degrees) and absf(spacing_wave_phase_degrees) <= 180.0
