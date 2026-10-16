extends Node
## Isolated prototype: host owns game time, pause, inventory, saves and rewards.
signal screen_changed(route: StringName, context: Dictionary)
signal overlay_changed(route: StringName, context: Dictionary)
signal action_requested(action: StringName, context: Dictionary)
signal input_block_changed(blocked: bool)

const ROUTES = [&"main", &"world", &"local", &"summon", &"summon_result", &"deployment", &"battle", &"settlement"]
const OVERLAYS = [&"warehouse", &"monster", &"book", &"event", &"trade", &"settings", &"help"]
const NEXT = {
	&"main": [&"world"], &"world": [&"local"],
	&"local": [&"summon", &"deployment"], &"summon": [&"summon_result"],
	&"summon_result": [], &"deployment": [&"battle"],
	&"battle": [&"settlement"], &"settlement": []
}
var history: Array[Dictionary] = []
var overlays: Array[Dictionary] = []

func current_route() -> StringName:
	return history.back().route if not history.is_empty() else &"main"

func current_context() -> Dictionary:
	return history.back().context.duplicate(true) if not history.is_empty() else {}

func start(context: Dictionary = {}) -> void:
	history = [{"route": &"main", "context": context.duplicate(true)}]
	_close_all_overlays()
	screen_changed.emit(current_route(), current_context())

func navigate(route: StringName, context: Dictionary = {}) -> bool:
	if not overlays.is_empty() or route not in ROUTES:
		return false
	if route not in NEXT.get(current_route(), []):
		return false
	var merged := current_context()
	merged.merge(context.duplicate(true), true)
	history.append({"route": route, "context": merged})
	screen_changed.emit(route, current_context())
	return true

func can_go_back() -> bool:
	return not overlays.is_empty() or (history.size() > 1 and current_route() not in [&"battle", &"settlement"])

func go_back() -> bool:
	if not overlays.is_empty():
		overlays.pop_back()
		_emit_overlay()
		return true
	if not can_go_back():
		return false
	history.pop_back()
	screen_changed.emit(current_route(), current_context())
	return true

func open_overlay(route: StringName, context: Dictionary = {}) -> bool:
	if route not in OVERLAYS:
		return false
	if not overlays.is_empty() and overlays.back().route == route:
		return false
	var merged := current_context()
	if not overlays.is_empty():
		merged.merge(overlays.back().context, true)
	merged.merge(context.duplicate(true), true)
	overlays.append({"route": route, "context": merged})
	_emit_overlay()
	return true

func request_action(action: StringName, payload: Dictionary = {}) -> void:
	var context := current_context()
	if not overlays.is_empty():
		context.merge(overlays.back().context, true)
	context.merge(payload.duplicate(true), true)
	context["ui_route"] = current_route()
	context["ui_overlay"] = overlays.back().route if not overlays.is_empty() else &""
	action_requested.emit(action, context.duplicate(true))

## Called by the host AFTER real settlement is committed, not by the reward button.
func return_to_exploration() -> bool:
	if not overlays.is_empty() or current_route() != &"settlement":
		return false
	while history.size() > 1 and current_route() != &"local":
		history.pop_back()
	screen_changed.emit(current_route(), current_context())
	return true

func finish_summon_preview() -> bool:
	if not overlays.is_empty() or current_route() != &"summon_result":
		return false
	history.pop_back()
	screen_changed.emit(current_route(), current_context())
	return true

func _close_all_overlays() -> void:
	overlays.clear()
	_emit_overlay()

func _emit_overlay() -> void:
	input_block_changed.emit(not overlays.is_empty())
	if overlays.is_empty():
		overlay_changed.emit(&"", {})
	else:
		overlay_changed.emit(overlays.back().route, overlays.back().context.duplicate(true))
