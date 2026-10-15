extends LocationInteractionPanel

func build_actions() -> void:
	add_action("Study the inscription", func() -> void: complete("study", true, {"choice": "knowledge"}))
	add_action("Leave an offering", func() -> void: complete("offering", true, {"choice": "blessing"}))
