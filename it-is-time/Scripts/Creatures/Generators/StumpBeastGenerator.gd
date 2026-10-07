@tool
extends "res://Scripts/Creatures/Generators/BeastGenerator.gd"

func _get_defaults_path() -> String:
	return "res://Resources/Generators/StumpBeastGeneratorDefaults.tres"

## Fixed models use arithmetic dimensions, not random anatomy samples.
func _sample_dimension(first: float, second: float) -> float:
	return (maxf(first,0.01) + maxf(second,0.01)) * 0.5

func _sample_limb_return_ratio() -> float:
	return 0.5

func _sample_limb_length() -> float:
	return base_limb_length

func _asymmetry() -> float:
	return 0.0

func _sample_foot_size() -> Vector3:
	return Vector3(maxf(base_foot_size.x,0.01),maxf(base_foot_size.y,0.01),part_width)

func _create_valid_plan() -> Dictionary:
	# The decorative network also stays identical across repeated generation.
	_random.seed = 42
	var plan := super._create_valid_plan()
	if not plan.is_empty(): plan["create_connection_markers"] = true
	return plan

@export_group("Stump Attachment")
## Fixed rear-to-front body height fraction for the head connection, avoiding random attachment drift.
@export_range(0.0, 1.0, 0.01) var head_attachment_height_ratio: float = 0.5

func _sample_neck_origin(torsos: Array[Dictionary]) -> Vector3:
	var torso: Dictionary = torsos[-1]
	var half: Vector3 = torso.size * 0.5
	return torso.position + Vector3(half.x, lerpf(-half.y, half.y, head_attachment_height_ratio), 0.0)
