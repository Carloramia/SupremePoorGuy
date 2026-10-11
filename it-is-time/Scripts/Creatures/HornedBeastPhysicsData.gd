@tool
class_name HornedBeastPhysicsData
extends Resource
@export var enabled: bool = true
@export_range(0.0, 2.0, 0.01) var minimum_limb_mass: float = 0.15
@export_range(0.0, 45.0, 0.5) var hip_x_limit: float = 12.0
@export_range(0.0, 90.0, 0.5) var hip_z_limit: float = 45.0
@export_range(0.0, 90.0, 0.5) var knee_z_limit: float = 50.0
@export_range(0.0, 90.0, 0.5) var ankle_z_limit: float = 30.0

@export_range(0.0, 90.0, 0.5) var action_z_limit: float = 60.0

@export_group("Grounded Standing Pose")
@export var standing_pose_enabled: bool = true
@export_range(0.0, 200.0, 1.0) var standing_strength: float = 80.0
@export_range(0.0, 30.0, 0.1) var standing_damping: float = 6.0
@export_range(0.0, 20.0, 0.5) var standing_dead_zone_degrees: float = 5.0
@export_range(0.01, 1.0, 0.01) var standing_blend_time: float = 0.2
@export_range(0.0, 400.0, 1.0) var standing_maximum_acceleration: float = 80.0
## Torque at OverallScale=1; geometric scaling uses scale^5.
@export_range(0.0, 20.0, 0.1, "or_greater") var standing_maximum_torque: float = 4.0
