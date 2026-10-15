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
## Optional upper arm relative to the hand. Empty retains the single-body behavior.
@export var drive_body_path: NodePath
## Ordered shoulder-to-hand descendants, excluding the drive body itself.
@export var follower_paths: Array[NodePath] = []
@export_range(0.0, 500.0, 1.0) var chain_stiffness: float = 80.0
@export_range(0.0, 100.0, 0.5) var chain_damping: float = 16.0
@export_range(0.0, 1000.0, 1.0) var chain_maximum_torque: float = 150.0

func _init() -> void:
	resource_local_to_scene = true
