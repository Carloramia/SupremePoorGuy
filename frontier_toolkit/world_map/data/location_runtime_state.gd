class_name LocationRuntimeState
extends RefCounted

enum Lifecycle { AVAILABLE, COMPLETED, HIDDEN_SESSION, REMOVED_PERMANENTLY, RESPAWNABLE }
var discovered: bool = false
var lifecycle: Lifecycle = Lifecycle.AVAILABLE
var custom_data: Dictionary = {}
var visits: int = 0

func to_dict() -> Dictionary:
	return {"discovered": discovered, "lifecycle": lifecycle, "custom_data": custom_data, "visits": visits}

static func from_dict(data: Dictionary) -> LocationRuntimeState:
	var state := LocationRuntimeState.new()
	state.discovered = bool(data.get("discovered", false))
	state.lifecycle = clampi(int(data.get("lifecycle", 0)), 0, 4) as Lifecycle
	state.custom_data = data.get("custom_data", {}).duplicate(true) if data.get("custom_data") is Dictionary else {}
	state.visits = maxi(0, int(data.get("visits", 0)))
	return state
