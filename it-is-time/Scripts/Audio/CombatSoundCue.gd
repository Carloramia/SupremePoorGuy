class_name CombatSoundCue
extends Resource

@export var event: StringName
@export var streams: Array[AudioStream] = []
@export_range(-60.0, 6.0, 0.5) var volume_db: float = -6.0
@export_range(0.5, 2.0, 0.01) var minimum_pitch: float = 0.94
@export_range(0.5, 2.0, 0.01) var maximum_pitch: float = 1.06
## Per character, so a compound hit or a death cascade does not play once per Part.
@export_range(0.0, 2.0, 0.01) var cooldown: float = 0.12
