@tool
extends Resource
## Shared style preset. Duplicate this resource for component-specific overrides.

@export_range(0.5, 12.0, 0.1) var line_width: float = 2.4:
	set(value):
		line_width = value
		emit_changed()

@export_range(0.0, 0.6, 0.01) var width_variation: float = 0.22:
	set(value):
		width_variation = value
		emit_changed()

@export_range(0.0, 3.0, 0.05) var irregularity: float = 0.65:
	set(value):
		irregularity = value
		emit_changed()

@export_range(0.0, 0.6, 0.01) var repeat_strength: float = 0.22:
	set(value):
		repeat_strength = value
		emit_changed()

@export_range(0.0, 0.6, 0.01) var ink_loss: float = 0.12:
	set(value):
		ink_loss = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var edge_coverage: float = 0.35:
	set(value):
		edge_coverage = value
		emit_changed()

@export_range(0.0, 8.0, 0.1) var edge_size: float = 1.4:
	set(value):
		edge_size = value
		emit_changed()

@export_range(0.0, 0.3, 0.005) var paper_grain: float = 0.08:
	set(value):
		paper_grain = value
		emit_changed()

@export_range(0.0, 0.3, 0.005) var pigment_grain: float = 0.06:
	set(value):
		pigment_grain = value
		emit_changed()

@export_range(0.5, 8.0, 0.1) var grain_size: float = 1.3:
	set(value):
		grain_size = value
		emit_changed()

@export_range(0.0, 32.0, 0.5) var backing_width: float = 6.0:
	set(value):
		backing_width = value
		emit_changed()

@export var backing_color: Color = Color.WHITE:
	set(value):
		backing_color = value
		emit_changed()

@export var ink_color: Color = Color("#302f2b"):
	set(value):
		ink_color = value
		emit_changed()

@export var seed: float = 17.0:
	set(value):
		seed = value
		emit_changed()

@export var s1_enabled: bool = true:
	set(value):
		s1_enabled = value
		emit_changed()

@export var s2_enabled: bool = true:
	set(value):
		s2_enabled = value
		emit_changed()

@export var s3_enabled: bool = true:
	set(value):
		s3_enabled = value
		emit_changed()

