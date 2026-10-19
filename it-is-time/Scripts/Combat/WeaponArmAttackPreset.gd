class_name WeaponArmAttackPreset
extends LimbSwingPresetBase

enum Motion { SWEEP, THRUST }

@export_group("Weapon Motion")
@export var motion: Motion = Motion.THRUST
@export var aim_in_3d: bool = false
## Fractions of the actual shoulder-to-hand chain length.
@export_range(0.1, 0.99, 0.01) var preparation_reach: float = 0.45
@export_range(0.1, 0.99, 0.01) var strike_reach: float = 0.96
@export_range(-0.8, 0.8, 0.01) var preparation_height: float = 0.15
@export_range(-0.8, 0.8, 0.01) var strike_height: float = 0.0
@export_range(0.5, 8.0, 0.1) var pose_frequency: float = 3.0
@export_range(0.1, 2.0, 0.05) var pose_damping_ratio: float = 1.0
@export_range(1.0, 500.0, 1.0) var maximum_pose_acceleration: float = 100.0
## Applied after inertia scaling, including the equipped weapon's mass.
@export_range(1.0, 5000.0, 1.0, "or_greater") var maximum_pose_torque: float = 350.0
@export_range(0.1, 1.0, 0.01) var npc_preferred_reach_ratio: float = 0.8

@export_group("Thrust Preparation")
## NPC charge-start envelope relative to actual thrust reach; striking reach stays unchanged.
@export_range(1.0, 2.0, 0.05) var npc_charge_range_multiplier: float = 1.0
## Scales position and rotation response frequencies only while charging.
@export_range(0.05, 1.0, 0.05) var preparation_speed_ratio: float = 1.0
## Scales charging acceleration and the final force/torque caps after mass/inertia conversion.
@export_range(0.05, 1.0, 0.05) var preparation_force_ratio: float = 1.0
## Keep physical collisions, but deal damage only during the released attack window.
@export var damage_only_during_swing: bool = false

@export_group("Hand Driven Thrust")
## Multi-link arms pull the chain from the hand instead of driving every link toward an IK pose.
@export var hand_driven_motion: bool = false
@export_range(0.5, 12.0, 0.1) var hand_position_frequency: float = 6.0
@export_range(0.1, 3.0, 0.05) var hand_position_damping: float = 1.2
@export_range(1.0, 500.0, 1.0) var hand_maximum_acceleration: float = 120.0
@export_range(1.0, 5000.0, 1.0, "or_greater") var hand_maximum_force: float = 250.0
@export_range(0.0, 30.0, 0.1) var passive_limb_damping: float = 4.0
## Weak elbow assistance only near straight or on the wrong side of the planned bend.
@export_range(0.0, 100.0, 1.0) var passive_bend_acceleration: float = 12.0
