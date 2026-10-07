class_name NPCBehaviorData
extends Resource

const ATTACK = preload("res://Scripts/Creatures/NPCAttackData.gd")
@export var auto_find_enemies: bool = true
## Legacy preset values retained for compatibility; scene-wide perception ignores them.
var detection_radius: float = 60.0
var disengage_radius: float = 80.0
@export_range(0.05, 10.0, 0.05) var scan_interval: float = 0.4
## Keep tracking positions during this interval; only changing enemies is delayed.
@export_range(0.0, 10.0, 0.1) var target_switch_cooldown: float = 1.5
@export_range(0.0, 0.9, 0.05) var target_switch_distance_advantage: float = 0.25
@export_range(0.0, 1.0, 0.05) var prediction_reposition_ratio: float = 0.25
@export_range(0.1, 50.0, 0.1) var preferred_distance: float = 5.0
@export_range(0.0, 100.0, 0.1) var maximum_vertical_difference: float = 15.0
@export var require_line_of_sight: bool = true
@export_flags_3d_physics var obstacle_mask: int = 1
@export var attacks: Array[ATTACK] = []
