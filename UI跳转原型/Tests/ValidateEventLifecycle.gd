extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("EVENT LIFECYCLE: "+label)
func settle() -> void:
	for i in 10:
		await process_frame
func make_app(path: String):
	var app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = path
	root.add_child(app)
	app._show("world")
	return app
func run() -> void:
	var path := ProjectSettings.globalize_path("res://Tests/.runtime")+"/event_life_%d.json" % Time.get_ticks_usec()
	var app = make_app(path)
	await settle()
	check(app.view.get_node("Traveler").visible, "unfinished marker exists")
	var money: int = app.state.data.magic
	app._open_event("traveler")
	check(app.close_button.text.contains("离开"), "event has explicit leave exit")
	app.close_button.pressed.emit()
	check(app.modal_stack.is_empty() and app.view.get_node("Traveler").visible, "leaving preserves unfinished event")
	check(app.state.data.magic == money and app.state.data.completed.is_empty(), "leave changes neither reward nor completion")
	app._open_event("traveler")
	await settle()
	app.modal_box.get_child(0).get_node("%Commands").get_child(0).pressed.emit()
	check(app.modal_stack.is_empty() and not app.view.get_node("Traveler").visible, "finished terminal event disappears")
	check(app.state.data.magic == money+20, "reward retained")
	app._open_event("traveler")
	check(app.modal_stack.is_empty() and app.state.data.magic==money+20, "finished event cannot be replayed")
	for name in ["Grassland","Forest","Desert"]:
		check(app.view.get_node(name).visible, "battle marker preserved "+name)
	app._show("battle")
	app._show("world")
	check(not app.view.get_node("Traveler").visible, "map navigation does not revive event")
	app.queue_free()
	await process_frame
	app = make_app(path)
	await settle()
	check(not app.view.get_node("Traveler").visible and app.state.data.magic == money+20, "completed event stays hidden after save reload")
	app.state.reset()
	app._show("world")
	check(app.view.get_node("Traveler").visible, "new game restores event")
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime")+"/missing_event_parent/save.json"
	app._open_event("traveler")
	await settle()
	app.modal_box.get_child(0).get_node("%Commands").get_child(0).pressed.emit()
	check(not app.modal_stack.is_empty() and app.view.get_node("Traveler").visible, "save failure does not hide event")
	check(app.state.data.completed.is_empty() and app.state.data.magic==money, "failed completion rolls back")
	app.queue_free()
	await process_frame
	print("EVENT_LIFECYCLE_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
