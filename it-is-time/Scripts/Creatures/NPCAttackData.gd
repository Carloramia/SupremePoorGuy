class_name NPCAttackData
extends Resource

@export var enabled: bool = true
@export var action_id: StringName = &"foreleg_stomp"
## Relative to the character, not the state machine.
@export var receiver_path: NodePath = ^"CreatureActionController3D"
@export_range(0.0, 100.0, 0.1, "or_greater") var minimum_range: float = 0.0
@export_range(0.1, 100.0, 0.1, "or_greater") var maximum_range: float = 8.0
## Negative uses NPCBehaviorData.preferred_distance, clamped to this attack's range.
@export_range(-1.0, 100.0, 0.1, "or_greater") var preferred_distance: float = -1.0
@export_range(0.0, 5.0, 0.05) var distance_tolerance: float = 0.3
@export_range(0.0, 20.0, 0.05) var cooldown: float = 2.0
@export_range(0.0, 20.0, 0.05) var charge_time: float = 0.6
@export_range(0.01, 100.0, 0.1) var selection_weight: float = 1.0
@export var allow_movement: bool = false
@export_group("Hit Prediction")
@export var prediction_enabled: bool = true
@export_range(8,48,1) var prediction_samples: int = 24
@export_range(0.0,0.5,0.01) var prediction_margin: float = 0.1
@export_range(0.1, 60.0, 0.1) var maximum_duration: float = 15.0
