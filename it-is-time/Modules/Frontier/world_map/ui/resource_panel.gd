extends LocationInteractionPanel

func build_actions() -> void:
	add_action("Collect herbs", func() -> void: complete("collect", true, {"collected": 3}))
