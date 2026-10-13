@tool
class_name WolfPhysicsData
extends Resource
@export var enabled: bool = true
@export var limb_terrain_collisions_enabled: bool = true
@export_group("Hind Leg Reference")
## Passive angular damping only; does not pull limbs toward the reference pose.
@export_range(0.0, 30.0, 0.1) var hind_limb_hinge_damping: float = 3.0
@export_range(80.0, 90.0, 0.5) var hind_knee_reference_degrees: float = 85.0
@export_group("Hind Lower Joint Spring")
@export var hind_lower_angle_limit_enabled: bool = true
## Interior angle between lower two limbs; 180 means fully straight.
@export_range(90.0, 180.0, 0.5) var hind_lower_maximum_angle_degrees: float = 160.0
@export var hind_lower_spring_enabled: bool = true
@export_range(0.0, 100.0, 0.5) var hind_lower_spring_strength: float = 8.0
@export_range(0.0, 30.0, 0.1) var hind_lower_spring_damping: float = 1.0
@export_range(0.0, 15.0, 0.5) var hind_lower_spring_dead_zone: float = 3.0
@export_range(0.0, 100.0, 0.5) var hind_lower_spring_maximum_acceleration: float = 12.0
## Torque at OverallScale=1; scales geometrically with scale^5.
@export_range(0.0, 10.0, 0.05, "or_greater") var hind_lower_spring_maximum_torque: float = 0.3
@export_range(0.0, 1.0, 0.05) var hind_lower_spring_step_multiplier: float = 0.25
@export_group("Foreleg Elbow")
@export var foreleg_anti_reverse_enabled: bool = true
@export_range(0.0, 30.0, 0.5) var foreleg_straight_buffer_degrees: float = 8.0
@export_range(0.0, 30.0, 0.1) var foreleg_straight_buffer_damping: float = 3.0
@export_range(0.0, 10.0, 0.05, "or_greater") var foreleg_straight_buffer_maximum_torque: float = 0.3
@export_group("Independent Torso Support")
@export var independent_torso_support: bool = true
@export_range(1.0, 3.0, 0.05) var torso_support_weight_limit: float = 1.5
@export_group("Joint Limits")
@export var foreleg_z_rotation_unlimited: bool = true
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

@export_group("Support Mass")
@export_range(0.0, 2.0, 0.01) var minimum_subtorso_mass: float = 0.15
@export_range(0.0, 1.0, 0.01) var subtorso_torso_mass_ratio: float = 0.1
