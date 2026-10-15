@tool
class_name ItemGripIdlePose
extends Resource

## Arm names or paths relative to the character, resolved from the actual equipped grips.
@export var higher_arm_path: NodePath = ^"Arm_R"
@export var lower_arm_path: NodePath = ^"Arm_L"
@export var enabled: bool = true
## Desired difference between Arm origins along world Y, in world units.
@export_range(0.0, 5.0, 0.01, "or_greater") var height_difference: float = 0.25
## Signed inclination of the lower-to-higher Arm line above the world horizontal plane.
@export var use_line_angle: bool = false
@export_range(0.0, 75.0, 1.0) var line_angle_degrees: float = 30.0
@export_range(0.1, 8.0, 0.1) var frequency: float = 2.0
@export_range(0.1, 3.0, 0.05) var damping_ratio: float = 1.0
@export_range(1.0, 200.0, 1.0) var maximum_acceleration: float = 30.0
@export_range(1.0, 2000.0, 1.0, "or_greater") var maximum_force: float = 80.0
