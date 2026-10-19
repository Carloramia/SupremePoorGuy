class_name WorldTimeSettings
extends Resource
## Map distances use authored map units; travel_speed is units per game hour.

@export_range(0.0, 23.99, 0.25) var starting_hour := 8.0
@export_range(1.0, 100000.0, 1.0, "or_greater") var starting_travel_speed := 600.0
## Successful actions only. Opening menus, cancelling and rejected actions cost nothing.
@export var interaction_minutes: Dictionary[String, float] = {
	"visit": 5.0, "clear_obstacle": 15.0, "summon": 30.0,
	"study": 15.0, "collect": 10.0, "battle": 20.0,
}

func action_minutes(action: String) -> float:
	var cost := float(interaction_minutes.get(action, 0.0))
	return cost if is_finite(cost) and cost >= 0.0 else 0.0
