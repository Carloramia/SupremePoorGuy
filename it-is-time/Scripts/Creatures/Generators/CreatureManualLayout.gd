@tool
extends Resource

## Base-unit physical blueprint captured from an authored generated character.
## Scene rules remain on the generator and are resolved again during assembly.
@export var blueprint: Dictionary = {}

func scaled_blueprint(multiplier: float) -> Dictionary:
	var result := blueprint.duplicate(true)
	for part: Dictionary in result.get("parts", []):
		part.size *= multiplier
		if part.has("connector_span"): part.connector_span *= multiplier
		var pose: Transform3D = part.transform
		pose.origin *= multiplier
		part.transform = pose
	for connection: Dictionary in result.get("connections", []):
		connection.anchor *= multiplier
	result["manual_layout"] = true
	result["overall_scale"] = multiplier
	result["create_connection_markers"] = true
	return result
