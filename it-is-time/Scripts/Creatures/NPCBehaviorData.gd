class_name NPCBehaviorData
extends Resource

const ATTACK = preload("res://Scripts/Creatures/NPCAttackData.gd")
@export var auto_find_enemies: bool = true
@export_range(0.1, 500.0, 0.5, "or_greater") var detection_radius: float = 60.0
@export_range(0.1, 1000.0, 0.5, "or_greater") var disengage_radius: float = 80.0
@export_range(0.05, 10.0, 0.05) var scan_interval: float = 0.4
@export_range(0.1, 50.0, 0.1) var preferred_distance: float = 5.0
@export_range(0.0, 100.0, 0.1) var maximum_vertical_difference: float = 15.0
@export var require_line_of_sight: bool = true
@export_flags_3d_physics var obstacle_mask: int = 1
@export var attacks: Array[ATTACK] = []
