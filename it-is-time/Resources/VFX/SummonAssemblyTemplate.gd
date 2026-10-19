extends Resource
## Reusable presentation settings, independent of gameplay summon results.
@export var template_name := "混合召唤 · 12只 · 触地停顿与加速吸附"
@export_range(1, 30) var count: int = 12
@export var height: float = 3.2
@export var random_seed: int = 5169
@export var burst_height: float = 9.0
@export var total_duration: float = 4.0
@export var anticipation_duration: float = 0.12
@export var flight_duration: float = 0.82
@export var launch_window: float = 0.34
@export var absorption_arc_height: float = 0.24
@export var scatter_radius: float = 9.75
@export var scatter_center_bias: float = 0.65
## Budget includes the ground pause; adding a pause never extends this budget.
@export var landing_to_assembly_duration: float = 0.64
@export var landing_pause: float = 0.16
@export var acceleration_power: float = 2.0
@export var playback_speed: float = 1.0
@export var layout_width: float = 22.0
@export var layout_depth: float = 8.0
@export var max_row_spacing: float = 3.2
@export var assembly_height: float = 2.4
@export var assembly_height_variation: float = 1.2
@export var drop_duration: float = 0.32
@export var landing_stagger: float = 0.075
@export var landing_sequence_window: float = 0.6
@export var first_bounce_height: float = 0.08
@export var second_bounce_height: float = 0.025
@export var first_bounce_duration: float = 0.12
@export var second_bounce_duration: float = 0.08
