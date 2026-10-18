@tool
class_name QuestObjectiveData
extends Resource
## COUNT adds unique event receipts; MAXIMUM records the highest reported total.
enum CountMode { COUNT, MAXIMUM }

@export var id: StringName
@export var description_key: String
@export var event_key: StringName
## Empty matches every target. Otherwise the event must carry this target_id.
@export var target_id: StringName
@export_range(1, 1000000, 1) var required_count: int = 1
@export var count_mode: CountMode = CountMode.COUNT
## Historical facts must be explicitly replayed by the business system.
@export var count_history: bool = false
