@tool
extends Resource

## Density per generated block type. Zero inherits the character's Mass Density.
@export_range(0.0, 100.0, 0.01, "or_greater") var torso: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var sub_torso: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var leg: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var fore_leg: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var leg_limb: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var neck: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var head: float = 1.0
## Zero preserves the fallback density of existing generated arm layouts.
@export_range(0.0, 100.0, 0.01, "or_greater") var arm: float = 0.0
@export_range(0.0, 100.0, 0.01, "or_greater") var arm_limb: float = 0.0
@export_group("Wings")
@export_range(0.0, 100.0, 0.01, "or_greater") var wing_root: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var wing_middle: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var wing_tip: float = 1.0
@export_range(0.0, 100.0, 0.001, "or_greater") var feather: float = 0.01

@export_group("Tail and Horns")
@export_range(0.0, 100.0, 0.01, "or_greater") var tail: float = 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var horn: float = 1.0

const TYPE_PROPERTIES = {
	"Torso": &"torso", "SubTorso": &"sub_torso", "Leg": &"leg",
	"ForeLeg": &"fore_leg", "LegLimb": &"leg_limb", "Neck": &"neck", "Head": &"head",
	"WingRoot": &"wing_root", "WingMiddle": &"wing_middle", "WingTip": &"wing_tip",
	"Feather": &"feather",
	"Tail": &"tail", "Horn": &"horn",
	"Arm": &"arm", "ArmLimb": &"arm_limb",
}

func get_density(part_type: String, fallback: float) -> float:
	if not TYPE_PROPERTIES.has(part_type): return fallback
	var value: Variant = _density_value(TYPE_PROPERTIES[part_type])
	if not (value is float or value is int): return fallback
	return value if value > 0.0 and is_finite(value) else fallback

func is_valid() -> bool:
	for property: StringName in TYPE_PROPERTIES.values():
		var value: Variant = _density_value(property)
		if not (value is float or value is int):
			push_warning("[creature_density] Property '%s' is %s in '%s'; no numeric density could be restored." % [property, type_string(typeof(value)), resource_path])
			return false
		if not is_finite(value) or value < 0.0: return false
	return true

func _density_value(property: StringName) -> Variant:
	var value: Variant = get(property)
	if value != null or not Engine.is_editor_hint(): return value
	# Hot reload leaves new fields Nil; restore only those fields, preserving unsaved edits.
	var source: Resource
	if resource_path.is_empty():
		source = get_script().new()
	else:
		source = ResourceLoader.load(resource_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if source == null: return null
	value = source.get(property)
	if value is float or value is int:
		set(property, value)
		if get(property) != null:
			print("[creature_density] Restored '%s'=%s after editor hot reload (%s)." % [property, value, resource_path])
	return get(property)
