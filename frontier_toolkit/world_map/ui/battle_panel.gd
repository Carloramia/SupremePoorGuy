extends LocationInteractionPanel

func build_actions() -> void:
	var button := add_action("Start battle", func() -> void: battle_start_requested.emit())
	button.pressed.connect(func() -> void:
		button.disabled = true
		button.text = "Waiting for external battle result…")
