extends "res://Scripts/Application/GameRoot.gd"
## Explicit F6-only sandbox. Never used by project.godot or by the normal game menu.
const CONTENT = preload("res://Scripts/Summoning/SummonContent.gd")

func _ready() -> void:
	# Tests may override with an isolated res://Tests/.runtime path before adding the scene.
	if save_path=="user://saves/slot_01.json": save_path="user://saves/summon_content_lab.json"
	if display_settings_path=="user://settings/display.cfg": display_settings_path="user://settings/summon_content_lab_display.cfg"
	super._ready()

func start_new_game() -> void:
	if phase!="main": return
	super.start_new_game()
	# The curtain may delay the route signal; phase can still be main after a successful save.
	if not session.last_error.is_empty(): return
	# Deliberate lab-only grants, not event completion and not production defaults.
	session.data.known_runes=CONTENT.RUNES.map(func(item):return item.id)
	session.data.known_relics=CONTENT.RELICS.map(func(item):return item.id)
	session.data.magic=10000
	session.data.array_stage=4
	session.data.layout={"version":4,"stage":4,"placed":[],"placedRelics":[]}
	if not session.save(): ui._notice(session.last_error)
	ui.rules.import_layout(session.data.layout)
