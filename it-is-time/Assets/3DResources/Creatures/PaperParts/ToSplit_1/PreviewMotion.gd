extends Node3D
## Rest-pose assembly demo. Disable animate to inspect the original placement.
@export var animate: bool = true
var elapsed: float = 0.0
@onready var hip: Node3D = $RightLeg/Pivot1
@onready var knee: Node3D = $RightLeg/Pivot1/Pivot2
@onready var ankle: Node3D = $RightLeg/Pivot1/Pivot2/Pivot3

func _process(delta: float) -> void:
    elapsed += delta
    if not animate:
        hip.rotation.z = 0.0
        knee.rotation.z = 0.0
        ankle.rotation.z = 0.0
        return
    hip.rotation.z = sin(elapsed * 1.5) * 0.12
    knee.rotation.z = sin(elapsed * 1.5 + 0.8) * 0.2
    ankle.rotation.z = -hip.rotation.z - knee.rotation.z
