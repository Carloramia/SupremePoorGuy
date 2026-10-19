class_name SummonGameplaySettings
extends Resource
## First-pass tunable values, not final balance. No map logic is kept here.
@export_group("Magic Cost")
## Confirmed Demo stages only. Missing stages retain legacy laboratory pricing.
@export var base_magic_by_stage: Dictionary[int,int] = {1:5,2:10}
@export_range(0,100,1) var magic_per_rune_cell: int = 1
@export_range(0,100,1) var magic_per_relic: int = 2
@export_group("Structure")
@export_range(1,5,1) var swarm_count: int = 5
@export_range(0.1,1.0,0.01) var swarm_scale: float = 0.35
@export_range(1,3,1) var extra_limb_pairs: int = 1
@export_group("Magic Eye")
@export_range(1.0,100.0,0.5) var eye_range: float = 20.0
@export_range(0.2,10.0,0.1) var eye_cooldown: float = 2.0
@export_range(0.01,3.0,0.01) var eye_attack_ratio: float = 0.6
@export_group("Sustain")
@export var lifesteal_ratio: float = 0.20
@export var lifesteal_cap_per_second: float = 0.03
@export var regeneration_period: float = 4.0
@export var regeneration_ratio: float = 0.04
@export var shield_period: float = 8.0
@export var shield_duration: float = 4.0
@export var shield_ratio: float = 0.10
@export var revival_delay: float = 2.0
@export var revival_health_ratio: float = 0.30
@export_group("Team Effects")
@export var support_range: float = 3.0
@export var support_attack_bonus: float = 0.08
@export var taunt_period: float = 8.0
@export var taunt_duration: float = 2.0
@export var taunt_immunity: float = 4.0
