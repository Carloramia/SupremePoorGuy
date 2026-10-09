@tool
class_name GeneratedPartSceneRule
extends Resource

enum SizeMode { KEEP_SIZE, FIT_UNIFORM, FIT_BOX }

func _init() -> void:
	resource_local_to_scene = true

## Empty means all parts of Part Type. Exact names (e.g. Leg_1_Limb_2)
## override type rules, and do not depend on random positions.
@export var part_name: String = ""
## Optional stable identity; e.g. SubTorso_Leg_1 stays attached to Leg_1 even if foreleg counts change.
## Highest priority. Other parts use their generated name as their key.
@export var part_key: String = ""
@export_enum("Torso", "SubTorso", "Leg", "ForeLeg", "LegLimb", "Neck", "Head", "WingRoot", "WingMiddle", "WingTip", "Feather", "Tail", "Horn") var part_type: String = "Torso"
@export var part_scene: PackedScene
## Custom models keep their proportions by default. Standard box parts always fit the frame.
## Custom paper-volume models fit XY only; final depth is generator Part Width * Overall Scale.
@export var size_mode: SizeMode = SizeMode.FIT_UNIFORM
## Applied after fitting; affects visuals, collision, markers and calculated mass together.
@export_range(0.01, 10.0, 0.01, "or_greater") var size_multiplier: float = 1.0
## Use the closest authored JointIn/JointOut marker to the planned connection.
## Disabled by default because imported markers may only be estimates.
@export var use_joint_markers: bool = false
## Custom limbs fit JointOut -> JointIn to the frame segment; feet/head align their attachment.
## Requires calibrated markers. Preserves limb XY proportions and fits depth separately.
## Paper models use Part Width * Overall Scale; ordinary custom meshes fit the frame depth.
@export var align_connectors_to_frame: bool = false

func matches(type: String, node_name: String) -> bool:
	return part_name == node_name if not part_name.is_empty() else part_type == type
