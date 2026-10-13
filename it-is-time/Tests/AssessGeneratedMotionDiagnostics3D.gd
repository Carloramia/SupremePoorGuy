extends "res://Tests/AssessGeneratedCreatureMotion3D.gd"

func sample(time: float) -> Dictionary:
	var row := super.sample(time)
	row["torsos"] = []
	for body: RigidBody3D in torsos:
		row.torsos.append({"name":body.name,"yaw":rad_to_deg(atan2(-body.global_basis.x.z,body.global_basis.x.x)),"yaw_rate":rad_to_deg(body.angular_velocity.y)})
	row["feet"] = []
	for foot: RigidBody3D in movement.get_leg_parts():
		row.feet.append({"name":foot.name,"grounded":movement.is_leg_grounded(foot),"stepping":movement.is_leg_stepping(foot),"position":foot.global_position,"velocity":foot.linear_velocity,"motion":movement.get_leg_step_diagnostics(foot)})
	row["turn_drive"] = movement._turn_drive_diagnostics.duplicate(true)
	return row

func finish(code: int = 0) -> void:
	if is_instance_valid(movement) and movement.has_method("get_spider_stride_limits"):
		result["structural_geometry"] = []
		for foot: RigidBody3D in movement.get_leg_parts():
			var geometry: Dictionary = movement._spider_reach_geometry.get(foot,{})
			var rolls: Dictionary = {}
			for point: Dictionary in geometry.get("samples",[]):
				var key := str(point.get("root_roll",0.0))
				rolls[key] = int(rolls.get(key,0))+1
			result.structural_geometry.append({"foot":foot.name,"interval":movement.get_spider_stride_limits(foot),"hip_sway":geometry.get("hip_sway",-1),"roll_samples":rolls,"reason":geometry.get("reason","")})
	await super.finish(code)
