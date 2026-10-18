class_name CombatAudioSettings
extends Resource

@export var enabled: bool = true
@export_range(-60.0, 6.0, 0.5) var volume_db: float = -3.0
@export_range(1, 64, 1) var maximum_voices: int = 24
@export_range(1.0, 500.0, 1.0) var unit_size: float = 32.0
@export_range(1.0, 2000.0, 1.0) var maximum_distance: float = 320.0
@export var cues: Array[CombatSoundCue] = []
