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
}

func get_density(part_type: String, fallback: float) -> float:
	if not TYPE_PROPERTIES.has(part_type): return fallback
	var value: float = get(TYPE_PROPERTIES[part_type])
	return value if value > 0.0 and is_finite(value) else fallback

func is_valid() -> bool:
	for property: StringName in TYPE_PROPERTIES.values():
		var value: float = get(property)
		if not is_finite(value) or value < 0.0: return false
	return true
