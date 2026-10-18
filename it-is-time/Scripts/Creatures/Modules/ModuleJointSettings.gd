@tool
class_name CreatureModuleJointSettings
extends Resource
## Limits are in template units and degrees. Runtime actions may temporarily override them.
@export var linear_lower := Vector3.ZERO
@export var linear_upper := Vector3.ZERO
@export var angular_lower_degrees := Vector3.ZERO
@export var angular_upper_degrees := Vector3.ZERO
@export var angular_spring_enabled := false
@export_range(0.0, 10000.0, 0.1, "or_greater") var spring_stiffness := 30.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var spring_damping := 5.0

func _init() -> void: resource_local_to_scene = true

func is_valid() -> bool:
	if not linear_lower.is_finite() or not linear_upper.is_finite() or not angular_lower_degrees.is_finite() or not angular_upper_degrees.is_finite(): return false
	for axis: int in 3:
		if linear_lower[axis]>linear_upper[axis] or angular_lower_degrees[axis]>angular_upper_degrees[axis]: return false
		if angular_lower_degrees[axis]<-180.0 or angular_upper_degrees[axis]>180.0: return false
	return is_finite(spring_stiffness) and spring_stiffness>=0.0 and is_finite(spring_damping) and spring_damping>=0.0

func apply_to(joint: Generic6DOFJoint3D, multiplier: float) -> void:
	for axis: int in 3:
		var suffix: String = ["x","y","z"][axis]
		joint.call("set_flag_"+suffix,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,true)
		joint.call("set_param_"+suffix,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,linear_lower[axis]*multiplier)
		joint.call("set_param_"+suffix,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,linear_upper[axis]*multiplier)
		joint.call("set_flag_"+suffix,Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,true)
		joint.call("set_param_"+suffix,Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,deg_to_rad(angular_lower_degrees[axis]))
		joint.call("set_param_"+suffix,Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,deg_to_rad(angular_upper_degrees[axis]))
		joint.call("set_flag_"+suffix,Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING,angular_spring_enabled)
		joint.call("set_param_"+suffix,Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS,spring_stiffness)
		joint.call("set_param_"+suffix,Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING,spring_damping)
