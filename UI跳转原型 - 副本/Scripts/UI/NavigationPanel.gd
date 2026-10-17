extends VBoxContainer
signal action_requested(action: String)
func _ready() -> void:
	for pair in [["Tasks","tasks"],["Summon","summon"],["Warehouse","warehouse"],["Party","party"],["ReturnMap","world"],["Dictionary","dictionary"],["Help","help"]]:
		get_node("%"+pair[0]).pressed.connect(func(): action_requested.emit(pair[1]))
func present_context(in_battle: bool, animate := true) -> void:
	get_node("%PartySlot").set_present(in_battle,animate,0.0 if in_battle else 0.05)
	get_node("%ReturnMapSlot").set_present(in_battle,animate,0.05 if in_battle else 0.0)
