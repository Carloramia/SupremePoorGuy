@tool
class_name QuestDefinition
extends Resource
const OBJECTIVE = preload("res://Scripts/Quests/QuestObjectiveData.gd")

@export var id: StringName
@export var title_key: String
@export_multiline var description_key: String
@export var prerequisite_ids: Array[StringName] = []
@export var auto_accept: bool = true
@export var objectives: Array[OBJECTIVE] = []
@export_group("Rewards")
@export_range(0, 1000000, 1) var reward_magic: int = 0
@export var reward_rune_ids: Array[StringName] = []
@export var reward_relic_ids: Array[StringName] = []
