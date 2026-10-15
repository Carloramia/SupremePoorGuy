@tool
class_name ItemGripSettings
extends Resource

@export var enabled: bool = true
## Physical spring frequency in Hz; higher values follow a moving grip more firmly.
@export_range(0.1, 12.0, 0.1) var position_frequency: float = 6.0
@export_range(0.1, 3.0, 0.05) var damping_ratio: float = 1.0
@export_range(1.0, 2000.0, 1.0, "or_greater") var maximum_force: float = 250.0
@export_range(1.0, 500.0, 1.0) var maximum_acceleration: float = 100.0
@export var follow_rotation: bool = false
@export_range(0.1, 12.0, 0.1) var rotation_frequency: float = 3.0
@export_range(1.0, 2000.0, 1.0, "or_greater") var maximum_torque: float = 150.0

func _init() -> void:
	resource_local_to_scene = true
