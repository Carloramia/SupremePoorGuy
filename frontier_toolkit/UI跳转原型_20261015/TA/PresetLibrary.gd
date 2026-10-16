extends RefCounted
const PRESETS = [
	preload("res://TA/Presets/light.tres"),
	preload("res://TA/Presets/medium.tres"),
	preload("res://TA/Presets/strong.tres")
]
## Modes: same raw assets, S1, S2, S3, combined.
static func variant(strength: int = 1, mode: int = 4) -> Resource:
	var preset: Resource = PRESETS[clampi(strength, 0, 2)].duplicate(true)
	var s1 := mode in [1, 4]
	var s2 := mode in [2, 4]
	var s3 := mode in [3, 4]
	if not s1:
		preset.outline_material.set_shader_parameter("line_width", 2.8)
		preset.outline_material.set_shader_parameter("width_variation", 0.0)
		preset.outline_material.set_shader_parameter("irregularity", 0.0)
		preset.outline_material.set_shader_parameter("repeat_strength", 1.0)
	if not s1 and not s3:
		preset.outline_material.set_shader_parameter("ink_loss", 0.0)
		preset.outline_material.set_shader_parameter("edge_coverage", 0.0)
	if not s3:
		for parameter in ["paper_grain", "pigment_grain", "edge_coverage", "edge_size", "ink_loss"]:
			preset.surface_material.set_shader_parameter(parameter, 0.0)
	preset.cutout_material.set_shader_parameter("backing_enabled", s2)
	preset.resource_name = "%s / mode %d" % [PRESETS[strength].resource_name, mode]
	return preset
