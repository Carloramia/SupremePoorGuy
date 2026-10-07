@tool
extends Resource

## Species-specific snapshots, including shared generator parameters and curves.
@export var parameters: Dictionary = {}:
	set(value):
		parameters = value
		emit_changed()
