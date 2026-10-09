extends LocationInteractionPanel

func build_actions() -> void:
	if location.definition.scenario_scene:
		add_action("进入场景 / Enter town", func() -> void: scenario_start_requested.emit())
	add_action("Rest & resupply", func() -> void: complete("rest", false, {"rested": true}))
	add_action("Complete visit", func() -> void: complete("visit", false))
