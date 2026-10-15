@tool
class_name BodyPartVisualState3D
extends Resource

## Render resources only. Collision shapes and connection markers are owned by the Part.
@export var state_name: StringName = &""
@export var mesh: Mesh
@export var material_override: Material
## Applied relative to the original visual transform, including generated scale and offsets.
@export var visual_transform: Transform3D = Transform3D.IDENTITY
## Optional existing marker under this Part; switching never moves the marker itself.
@export_node_path("Node3D") var anchor_path: NodePath
@export var mesh_anchor: Vector3 = Vector3.ZERO
