@tool
extends RefCounted

# Timings are inclusive: a parent phase contains its child phases and must not be added to them.
var enabled: bool = false
var timings: Dictionary = {}
var counters: Dictionary = {}

func register(component: Node) -> void:
	if Engine.is_editor_hint(): return
	component.add_to_group(&"control_performance_components")
	var console := component.get_tree().root.get_node_or_null("RuntimeConsole")
	set_enabled(console != null and console.is_control_performance_tracking_enabled())

func set_enabled(value: bool) -> void:
	if enabled == value: return
	enabled = value
	timings.clear()
	counters.clear()

func start() -> int:
	return Time.get_ticks_usec() if enabled else 0

func finish(phase: StringName, started: int) -> void:
	if not enabled or started == 0: return
	var elapsed := Time.get_ticks_usec() - started
	var entry: Dictionary = timings.get(phase, {"calls": 0, "total_usec": 0, "max_usec": 0})
	entry.calls += 1
	entry.total_usec += elapsed
	entry.max_usec = maxi(entry.max_usec, elapsed)
	timings[phase] = entry

func count(key: StringName, amount: int = 1) -> void:
	if enabled: counters[key] = int(counters.get(key, 0)) + amount

func consume() -> Dictionary:
	var result := {"timings": timings.duplicate(true), "counters": counters.duplicate()}
	timings.clear()
	counters.clear()
	return result
