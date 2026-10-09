class_name WorldMapGenerationResult
extends RefCounted

var hex_overrides: Dictionary = {}
var locations: Array[Dictionary] = []
var metadata: Dictionary = {}

func to_dict() -> Dictionary:
	return {"hex_overrides": hex_overrides, "locations": locations, "metadata": metadata}
