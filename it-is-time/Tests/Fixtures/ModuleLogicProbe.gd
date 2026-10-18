extends Node
var character: Node
var host: Node
var active := false
func on_module_mounted(actor: Node, part: Node) -> void:
	character = actor
	host = part
func on_module_enabled_changed(value: bool) -> void:
	active = value
