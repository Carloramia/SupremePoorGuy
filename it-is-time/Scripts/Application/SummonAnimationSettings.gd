class_name SummonAnimationSettings
extends Resource

@export_range(1.0, 16.0, 0.5) var preparation_budget_ms := 6.0
@export var stage_scene: PackedScene = preload("res://Scenes/Application/SummonBattleStage3D.tscn")
@export var diagnostic_logging := false
@export_group("Emission Area")
## Map-centered assembly/debris circle. Zero chooses a radius from the complete batch.
## An undersized requested radius expands only when needed to preserve creature spacing.
@export_range(0.0, 1000.0, 0.5, "or_greater") var emission_radius := 0.0
@export_range(0.0, 10.0, 0.1, "or_greater") var creature_spacing := 1.5
@export_range(0.05, 1.0, 0.01) var emergence_clearance := 0.15
@export_group("Part Assembly")
## Biological parts erupt near their creature's assembly point, without randomizing its pose.
@export_range(0.0, 10.0, 0.1, "or_greater") var part_spawn_radius := 2.0
@export_range(0.02, 1.0, 0.01) var part_interval := 0.1
## Minimum unassisted motion after full emergence; attraction also requires actual ground contact.
@export_range(0.0, 5.0, 0.1) var part_free_motion_duration := 1.0
@export_range(0.5, 3.0, 0.1) var attraction_frequency := 1.5
@export_range(10.0, 100.0, 1.0) var attraction_maximum_acceleration := 45.0
@export_range(10.0, 150.0, 1.0) var attraction_maximum_angular_acceleration := 60.0
@export_range(0.01, 0.2, 0.01) var arrival_distance := 0.05
@export_range(0.05, 1.0, 0.05) var arrival_speed := 0.3
@export_range(0.05, 0.5, 0.05) var arrival_confirmation_time := 0.1
@export_group("Wrong Parts")
@export_range(0.0, 2.0, 0.05) var wrong_part_ratio := 0.4
@export_range(1, 128) var maximum_wrong_parts := 48
@export_range(0.2, 5.0, 0.1) var decoration_size := 2.0
## Spawn cadence; the bounded decoration pool recycles after each complete fade.
@export_range(0.02, 2.0, 0.01) var decoration_interval := 0.12
@export_group("Timing")
@export_range(0.1, 10.0, 0.1) var creature_start_interval := 1.0
@export_range(0.1, 8.0, 0.1) var free_motion_duration := 2.4
@export_range(0.1, 5.0, 0.1) var decoration_fade_duration := 1.0
@export_range(0.1, 3.0, 0.1) var reveal_duration := 1.0
@export_group("Launch")
@export_range(1.0, 30.0, 0.1) var minimum_upward_speed := 10.0
@export_range(1.0, 30.0, 0.1) var maximum_upward_speed := 14.0
@export_range(0.0, 10.0, 0.1) var part_horizontal_speed := 1.5
@export_range(0.0, 10.0, 0.1) var horizontal_speed := 4.5
@export_range(0.0, 12.0, 0.1) var spin_speed := 5.0
