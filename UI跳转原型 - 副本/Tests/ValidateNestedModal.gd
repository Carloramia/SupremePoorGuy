extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("NESTED MODAL: "+label)
func settle() -> void:
	for i in 12:
		await process_frame
func capture(name: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://Tests/screenshots/"+name+".png")
func check_context(app, label: String) -> void:
	check(not app.status.visible,"no orphaned battle footer "+label)
	check(not app.main_content.visible,"inactive map stays hidden "+label)
	if DisplayServer.get_name() != "headless":
		check(app.modal_backdrop.visible and app.modal_backdrop.texture != null,"parent page remains behind explanation "+label)
		var img = app.modal_backdrop.texture.get_image()
		check(img.get_width()>100 and img.get_height()>100,"context backdrop covers modal area "+label)
func run() -> void:
	root.size = Vector2i(1280,720)
	var app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime")+"/nested_modal_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("battle")
	for c in Rules.definition("attack").cells:
		app.rules.extend(c)
	check(app.rules.commit() and app.state.summon(app.rules,"grassland","battle"),"battle result fixture")
	app._results()
	await settle()
	check(not app.status.visible and not app.main_content.visible,"results initially suppress footer and map")
	var unchanged: Dictionary = app.state.data.duplicate(true)
	app._trait("锐牙")
	await settle()
	check_context(app,"result trait")
	await capture("nested_trait_context")
	app._term("攻击","普通攻击的基础强度。")
	await settle()
	check_context(app,"second explanation")
	app._close_modal()
	await settle()
	check_context(app,"return to trait")
	check(app.modal_stack.size()==2,"nested return pops one layer")
	app._close_modal()
	await settle()
	check(not app.status.visible and not app.modal_backdrop.visible,"return to result restores page without duplicate backdrop")
	app._trait("锐牙")
	await settle()
	check_context(app,"reopen after battle refresh")
	check(app.state.data==unchanged,"explanations never reroll or change the saved batch")
	app._close_all()
	app.state.store_pending()
	app._warehouse("")
	await settle()
	app._trait("锐牙")
	await settle()
	check_context(app,"warehouse trait")
	await capture("nested_warehouse_context")
	app._close_modal()
	await settle()
	check(not app.status.visible and not app.modal_backdrop.visible,"warehouse return clears backdrop and hides footer")
	app._close_all()
	app._open_ritual()
	await settle()
	app._term("锐牙","攻击增加12%。")
	await settle()
	check_context(app,"rune reference")
	await capture("nested_rune_context")
	app._close_all()
	await settle()
	check(app.main_content.visible and app.status.visible and not app.modal_backdrop.visible,"closing all restores underlying battle and normal footer")
	check(app.status.global_position.y > root.size.y*0.8,"battle hint stays at bottom")
	app._term("普通说明","直接从地图打开。")
	await settle()
	check(app.main_content.visible,"standalone dialog retains map")
	check(not app.modal_backdrop.visible,"standalone dialog needs no stale book backdrop")
	app.queue_free()
	await process_frame
	print("NESTED_MODAL_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
