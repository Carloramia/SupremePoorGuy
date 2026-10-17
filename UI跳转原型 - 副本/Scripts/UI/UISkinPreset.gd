@tool
extends Resource
## Asset contract only. S1/S2/S3 algorithms and final defaults are supplied by TA.
@export_group("S3 Surface")
@export var surface_texture: Texture2D:
	set(value):
		surface_texture = value
		emit_changed()
@export var surface_region := Rect2():
	set(value):
		surface_region = value
		emit_changed()
@export var surface_material: Material:
	set(value):
		surface_material = value
		emit_changed()
@export_group("S1 Outline")
@export var outline_texture: Texture2D:
	set(value):
		outline_texture = value
		emit_changed()
@export var outline_material: Material:
	set(value):
		outline_material = value
		emit_changed()
@export_range(0,128,1) var patch_margin := 16:
	set(value):
		patch_margin = value
		emit_changed()
@export_group("S2 Illustration and icons")
@export var cutout_material: Material:
	set(value):
		cutout_material = value
		emit_changed()
@export_group("Decoration")
@export var decoration_material: Material:
	set(value):
		decoration_material = value
		emit_changed()
@export_group("Stable instance parameters")
@export var stable_seed := 42:
	set(value):
		stable_seed = value
		emit_changed()
@export var remove_legacy_shadows := true:
	set(value):
		remove_legacy_shadows = value
		emit_changed()
