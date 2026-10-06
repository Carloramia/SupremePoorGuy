@tool
extends "res://Scripts/Creatures/Generators/BaseCreatureGenerator.gd"

func _init() -> void:
	_apply_default_preset()

func _get_defaults_path() -> String:
	return "res://Resources/Generators/BeastGeneratorDefaults.tres"

@export_group("Beast Feet")
@export_range(0,10,1) var rear_leg_count: int = 4
@export_range(0,10,1) var foreleg_count: int = 2

func _validate_species_settings() -> bool:
	return rear_leg_count >= 0 and rear_leg_count <= 10 and foreleg_count >= 0 and foreleg_count <= 10

func _append_species_feet(layouts: Array[Dictionary], width: float) -> void:
	_append_foot_group(layouts,rear_leg_count,"Leg",-1.0,width)
	_append_foot_group(layouts,foreleg_count,"ForeLeg",1.0,width)

func _complete_species_plan(plan: Dictionary) -> Dictionary:
	plan["generator_type"] = "beast"
	plan["wings"] = []
	return plan
