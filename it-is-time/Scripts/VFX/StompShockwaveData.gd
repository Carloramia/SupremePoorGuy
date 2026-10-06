class_name StompShockwaveData
extends Resource

@export var enabled: bool = true
@export_group("Expansion")
@export_range(0.1,100.0,0.1,"or_greater") var radius: float = 12.0
@export_range(0.05,5.0,0.01) var duration: float = 0.65
@export var require_line_of_sight: bool = true
@export_flags_3d_physics var obstacle_mask: int = 1
@export_group("Damage And Impact")
## Scales measured impulse before the global DamageService conversion.
@export_range(0.0,100.0,0.1,"or_greater") var impulse_scale: float = 1.0
@export_range(0.0,1.0,0.01) var edge_strength: float = 0.4
## Delta velocity; total character mass determines the impulse budget.
@export_range(0.0,50.0,0.1) var outward_speed: float = 5.0
@export_range(0.0,50.0,0.1) var upward_speed: float = 2.5
@export_range(0.0,3.0,0.01) var adhesion_release_time: float = 0.45
@export_group("Visual")
@export var color: Color = Color(1.0,0.55,0.12,1.0)
@export_range(0.0,20.0,0.1) var emission_energy: float = 4.0

func is_valid() -> bool:
	for value: float in [radius,duration,impulse_scale,edge_strength,outward_speed,upward_speed,adhesion_release_time,emission_energy]:
		if not is_finite(value) or value < 0.0: return false
	return radius > 0.0 and duration > 0.0 and edge_strength <= 1.0
