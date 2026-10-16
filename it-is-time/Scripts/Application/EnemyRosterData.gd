class_name EnemyRosterData
extends Resource

@export var enabled := true
@export var definitions: Array[String] = []
@export_multiline var unavailable_reason := ""

func availability_error() -> String:
	if not enabled: return unavailable_reason if not unavailable_reason.is_empty() else "敌方编队尚未开放。"
	if definitions.is_empty(): return "敌方编队没有配置成员。"
	var factory = preload("res://Scripts/Application/CreatureFactory.gd")
	for id: String in definitions:
		if not factory.DEFINITIONS.has(id): return "敌方物种尚未注册："+id
	return ""
