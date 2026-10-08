class_name WorldMapGenerator
extends RefCounted

func generate(_definition: WorldMapDefinition, seed: int, overrides: Dictionary) -> WorldMapGenerationResult:
	# Contract: stable seed; fixed IDs/hexes win. No procedural algorithm in v1.
	# Location descriptors contain id, definition resource path, x/y and interaction x/y.
	# Controller registers descriptors through LocationManager, never SceneTree scans.
	var result := WorldMapGenerationResult.new()
	result.hex_overrides = overrides.get("hexes", {}).duplicate(true)
	for descriptor: Dictionary in overrides.get("locations", []):
		result.locations.append(descriptor.duplicate(true))
	result.metadata = {"seed": seed, "generator": "fixed_v1"}
	return result
