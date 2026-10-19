extends Resource
const L10N = preload("res://Scripts/Localization/GameText.gd")
## Each faction has its own budget; reserves do not consume deployed capacity.
@export_range(1,10000,1) var total_capacity: int = 30
@export_range(0.1,60.0,0.1) var enemy_reinforcement_interval: float = 3.0
@export var creature_costs: Dictionary[String,int] = {
	"human":4, "stump_beast":6, "wolf":6, "snake":12, "horned_beast":10, "spider":8
}

func creature_cost(record: Dictionary) -> int:
	return int(creature_costs.get(str(record.get("definition_id","")),0))

func evaluate(allies: Array) -> Dictionary:
	var result := {"allies":0,"used":0,"limit":total_capacity,"remaining":total_capacity,"error":""}
	if total_capacity < 1:
		result.error = L10N.text("ui.capacity.invalid_limit")
		return result
	for entry: Variant in allies:
		var record: Dictionary = entry if entry is Dictionary else {"definition_id":str(entry)}
		var cost := creature_cost(record)
		if cost < 1:
			result.error = L10N.text("ui.capacity.invalid_cost",{"id":record.get("definition_id","")})
			return result
		result.allies += cost
	result.used = result.allies
	result.remaining = maxi(total_capacity - int(result.used),0)
	if result.used > total_capacity: result.error = L10N.text("ui.capacity.exceeded",result)
	return result

func summary(status: Dictionary) -> String:
	return L10N.text("ui.capacity.summary",status)

func initial_roster(records: Array) -> Dictionary:
	var selected: Array = []
	var status := evaluate([])
	if not status.error.is_empty(): return {"records":selected,"error":status.error}
	for record: Dictionary in records:
		var cost := creature_cost(record)
		if cost <= 0: return {"records":[],"error":L10N.text("ui.capacity.invalid_cost",{"id":record.get("definition_id","")})}
		if status.used+cost <= total_capacity:
			selected.append(record)
			status.used += cost
	return {"records":selected,"error":""}
