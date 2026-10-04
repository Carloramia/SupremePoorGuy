class_name ArmSwingBinding
extends Resource

## Assigns one Arm part to one controller input group. Add multiple bindings to
## the same Arm when it should be available to multiple control groups.

@export var enabled: bool = true
@export var control_group_name: StringName = &"PrimaryArm"
@export var swing_preset: LimbSwingPresetBase
## Optional path relative to the BodyPart. Leave empty to auto-discover the
## single Generic6DOFJoint3D connecting this Arm to another BodyPart.
@export var joint_path: NodePath

func _init() -> void:
	resource_local_to_scene = true
