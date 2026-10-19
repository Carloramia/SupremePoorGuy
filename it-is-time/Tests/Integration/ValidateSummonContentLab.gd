extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)

func run() -> void:
	var app := preload("res://Scenes/Application/SummonContentLab.tscn").instantiate()
	app.save_path="res://Tests/.runtime/integration/content_lab_%d.json" % Time.get_ticks_usec()
	app.display_settings_path="res://Tests/.runtime/integration/content_lab_display.cfg"
	app.use_delivery_map=false # UI/summon check; does not exercise or alter another team's map.
	root.add_child(app)
	check(app.session.save_path.begins_with("res://Tests/"),"Lab test never reads or writes the player save")
	app.ui.animate_panels=false
	app.ui.board_motion.enabled=false
	app.start_new_game()
	for frame: int in 600:
		if app.phase=="world": break
		await physics_frame
	check(app.phase=="world","Lab enters the map")
	check(app.session.data.known_runes.size()==9 and app.session.data.known_relics.size()==8 and app.session.data.array_stage==4,"Lab-only unlocks and stage four")
	app.ui._close_all()
	app.ui._open_ritual()
	check(is_instance_valid(app.ui.ritual_page) and app.ui.rules.layout_version==4,"Native summon panel uses the current catalogue")
	check(app.ui.ritual_page.get_node("%Examples").item_count==8,"Native examples do not offer retired tiny or bone recipe")
	app.ui.rules.draft=app.ui.Rules.current_definition("multiply").cells.duplicate(true)
	check(app.ui.rules.commit(),"Lab can draw the current swarm rune")
	app.ui._refresh_ritual()
	check(not app.ui.summon_button.disabled,"Owned current swarm is callable through the actual native UI")
	check(app.session.summon(app.ui.rules,"frontier","world"),"Native session generates real swarm bodies")
	check(app.session.data.pending.size()==5,"Swarm has five stable IDs")
	if app.session.data.pending.is_empty():
		app.queue_free()
		await process_frame
		quit(1)
		return
	var id: String = app.session.data.pending[0]
	check(app.session.move_monster(id,"team") and app.session.monsters("team").size()==5 and app.session.occupied_slots()==1,"Moving one swarm member moves the entire one-slot group")
	check(not app.session.recycle_monster(id),"First-pass swarm remains unrecoverable")
	app.ui._close_all()
	app.ui._warehouse("team")
	await process_frame
	check(not app.ui.modal_stack.is_empty(),"Native warehouse can display swarm members")
	app.ui._detail(id)
	await process_frame
	check(app.ui.modal_stack.size()>=2,"Native detail opens without placeholder part_hp fields")
	app.ui._close_all()
	app.queue_free()
	await process_frame
	await process_frame
	print("SUMMON_LAB_CHECKS=",checks," FAILURES=",failures)
	quit(0 if failures==0 else 1)
