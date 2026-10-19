@tool
extends "res://Scripts/Creatures/WolfLegMovementData.gd"

func calculate_motion_profile(length: float, radius: float, foot_count: int, shared_length: float = -1.0) -> Dictionary:
	var profile := super.calculate_motion_profile(length,radius,foot_count,shared_length)
	# Small pinned feet need a faster response to overcome joint/ground resistance.
	profile.contact_gain = clampf(8.0+target_speed*4.0,8.0,20.0)
	profile.contact_acceleration = clampf(target_speed*4.0,4.0,16.0)
	return profile
