extends Resource
@export_range(0.0, 20.0, 0.01, "or_greater") var damage_multiplier: float = 1.0
## Distances scale with the equipped character's actual arm reach (reference 4.5 units).
@export_group("Holding Pose")
@export_range(0.1,1.0,0.01) var holding_reach_ratio := 0.8
@export_range(-0.5,0.5,0.01) var holding_height_ratio := 0.1
@export_range(0.02,0.6,0.01) var draw_reach_ratio := 0.4
## Maximum posture-only draw as a fraction of the full drawing distance.
@export_range(0.0,0.9,0.01) var posture_draw_ratio := 0.85
@export_range(0.01,1.0,0.01) var pose_tolerance_ratio := 0.12
@export_range(1.0,30.0,0.5) var aim_tolerance_degrees := 4.0
@export_range(1.0,20.0,0.5) var maximum_prepare_time := 6.0
@export_range(0.5,8.0,0.1) var pose_frequency := 3.5
@export_range(0.1,2.0,0.1) var pose_damping_ratio := 1.1
@export_range(1.0,500.0,1.0) var maximum_pose_acceleration := 140.0
@export_range(1.0,5000.0,1.0,"or_greater") var maximum_pose_torque := 1500.0
## Rate of joint pose targets; physical bodies still respond through damped torques.
@export_range(30.0,720.0,5.0) var joint_target_speed_degrees := 180.0
@export_group("Pose Transitions")
@export_range(10.0,180.0,5.0) var aim_transition_speed_degrees := 60.0
@export_range(1.0,90.0,1.0) var settled_angular_speed_degrees := 20.0
@export_range(0.0,1.0,0.01) var settle_time := 0.1
@export_range(0.05,0.5,0.01) var string_release_time := 0.12
@export_range(1.0,10.0,0.1) var maximum_recovery_time := 3.0
@export_group("Anatomical Pose")
@export var anatomical_pose_enabled := true
@export_range(0.0,5.0,0.05) var anatomical_pose_weight := 1.0
## Elbow elevation above the shoulder, rather than a world-axis shoulder joint angle.
@export_range(-30.0,60.0,1.0) var maximum_elbow_elevation_degrees := 15.0
@export_range(60.0,170.0,1.0) var bow_arm_elbow_degrees := 130.0
@export_range(60.0,170.0,1.0) var string_arm_elbow_degrees := 105.0
@export_range(5.0,60.0,1.0) var maximum_wrist_bend_degrees := 35.0
@export_range(0.0,30.0,1.0) var preferred_joint_margin_degrees := 12.0
@export_group("Shot")
@export_range(0.1,5.0,0.05) var draw_time := 0.8
@export_range(0.1,5.0,0.05) var recovery_time := 0.5
@export_range(0.0,10.0,0.1) var cooldown := 1.5
@export_range(1.0,200.0,1.0) var minimum_arrow_speed := 24.0
## Reference full-draw speed; distant targets automatically require a faster ballistic shot.
@export_range(1.0,200.0,1.0) var maximum_arrow_speed := 42.0
@export var arrow_speed_curve: Curve
## Minimum lifetime; extended when the predicted flight takes longer.
@export_range(0.1,20.0,0.1) var arrow_lifetime := 6.0
@export_group("NPC Range")
## Selection allowance is independent of the tighter settled pose required for release.
@export_range(1.0,30.0,0.5) var target_plane_tolerance_degrees := 12.0
@export_range(0.0,100.0,0.5) var minimum_range := 10.0
@export_range(1.0,200.0,0.5) var preferred_range := 35.0
@export_range(0.1,5.0,0.1) var distance_tolerance := 2.0

func arrow_speed(draw_ratio: float) -> float:
	var value := clampf(draw_ratio,0.0,1.0)
	if arrow_speed_curve != null: value = clampf(arrow_speed_curve.sample_baked(value),0.0,1.0)
	return lerpf(minimum_arrow_speed,maximum_arrow_speed,value)
