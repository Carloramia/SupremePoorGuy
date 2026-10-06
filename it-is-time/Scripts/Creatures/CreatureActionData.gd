extends Resource

@export var action_id: StringName = &"foreleg_stomp"
@export var input_action: StringName = &"MouseLeft"
@export var enabled: bool = true
@export_group("Shockwave")
@export var shockwave: StompShockwaveData = preload("res://Resources/Actions/ForeLegStompShockwave.tres")
@export_group("Lift")
## Heights scale with each participating leg's chain length.
@export_range(0.01,2.0,0.01,"or_greater") var foot_lift_ratio: float = 0.18
@export_range(0.0,2.0,0.01,"or_greater") var torso_lift_ratio: float = 0.06
@export_range(0.05,2.0,0.01) var rise_time: float = 0.45
@export_range(0.1,5.0,0.01) var rise_timeout: float = 1.2
## Stop lifting immediately without rear support; recover if it stays lost.
@export_range(0.0,1.0,0.01) var support_loss_timeout: float = 0.25
@export_range(0.1,1.0,0.01) var height_confirmation_ratio: float = 0.6
@export_group("Forward Extension")
## Relative to leg-chain length; ignore small rearward offsets from solver noise.
@export_range(0.0,0.2,0.005) var rearward_tolerance_ratio: float = 0.02
## Fraction of the available forward reach used by the landing target.
@export_range(0.05,0.9,0.01) var forward_extension_ratio: float = 0.45
@export_group("Stomp")
@export_range(0.05,2.0,0.01) var stomp_time: float = 0.3
@export_range(0.0,200.0,0.1) var downward_acceleration: float = 25.0
@export_range(0.1,5.0,0.01) var landing_timeout: float = 1.0
@export_range(0.0,0.3,0.01) var contact_confirmation_time: float = 0.08
@export_group("Force")
@export_range(1.0,500.0,1.0) var position_gain: float = 80.0
@export_range(0.1,3.0,0.05) var damping_ratio: float = 1.0
@export_range(1.0,500.0,1.0) var maximum_acceleration: float = 100.0
@export_range(1.0,20000.0,1.0) var maximum_force: float = 5000.0
@export_group("Recovery")
@export_range(0.05,2.0,0.01) var recovery_time: float = 0.3
@export_range(0.0,5.0,0.01) var cooldown: float = 0.4

func is_valid() -> bool:
	for value: float in [foot_lift_ratio,torso_lift_ratio,rise_time,rise_timeout,support_loss_timeout,height_confirmation_ratio,rearward_tolerance_ratio,forward_extension_ratio,stomp_time,downward_acceleration,landing_timeout,contact_confirmation_time,position_gain,damping_ratio,maximum_acceleration,maximum_force,recovery_time,cooldown]:
		if not is_finite(value) or value < 0.0: return false
	return foot_lift_ratio > 0.0 and forward_extension_ratio > 0.0 and forward_extension_ratio <= 0.9 and rise_time > 0.0 and rise_timeout >= rise_time and height_confirmation_ratio > 0.0 and height_confirmation_ratio <= 1.0 and stomp_time > 0.0 and landing_timeout >= stomp_time and position_gain > 0.0 and damping_ratio > 0.0 and maximum_acceleration > 0.0 and maximum_force > 0.0 and recovery_time > 0.0
