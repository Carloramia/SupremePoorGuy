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
