extends SceneTree
## Reproducible native runtime preview, isolated from the player's normal save.
const Scene = preload("res://Scenes/GameDemo.tscn")
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
var app
var caption

func _initialize() -> void:
	call_deferred("_run")

func hold(seconds: float) -> void:
	for i in int(seconds*30):
		await process_frame

func say(line: String) -> void:
	caption.get_node("Text").text = "纸雕 UI 0.5　｜　"+line

func _run() -> void:
	root.size = Vector2i(1280,720)
	app = Scene.instantiate()
	app.state.save_path = "user://native_art_capture_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	caption = preload("res://Scenes/UI/ArtTestCaption.tscn").instantiate()
	root.add_child(caption)
	app._show("world")
	say("原生界面自动演示 · 书本打开召唤")
	await hold(1.4)
	app.view.summon_book.pressed.emit()
	say("画板滑入 · 底纸 / 叠层框 / 夹子为独立素材")
	await hold(1.1)
	say("绘制与刻入仍为独立交互，不烘焙进贴图")
	for cell in Rules.RUNES[0].cells:
		app.rules.extend(cell)
		app._refresh_ritual()
		await hold(0.25)
	app.modal_box.get_child(0).get_node("%Commit").pressed.emit()
	await hold(1.0)
	app.summon_button.pressed.emit()
	# Visual demonstration only; business generation rules are unchanged.
	for i in 3:
		app.state.data.monsters[i].form = ["兽形", "人形", "蛇形"][i]
		app.state.data.monsters[i].name = "纸雕示意·"+app.state.data.monsters[i].form+" %02d" % (i+1)
	say("沿用当地喷涌 · 本次只替换 UI 美术")
	await hold(3.5)
	say("结果纸卡 · 用户概念图示意 · 不是实时生成外观")
	await hold(1.4)
	app.modal_box.get_child(0).get_node("%Cards").get_child(0).get_node("%Move").pressed.emit()
	await hold(0.7)
	app.close_button.pressed.emit()
	say("画板移开 · 剩余妖兽自动入库")
	await hold(1.0)
	app.base.get_node("%Warehouse").pressed.emit()
	say("仓库复用同一套分件与主题")
	await hold(1.8)
	app.modal_box.get_child(0).get_node("%Cards").get_child(0).get_node("%Detail").pressed.emit()
	say("详情独立纸页 · 文本与数值可编辑")
	await hold(1.4)
	app.close_button.pressed.emit()
	await hold(0.5)
	app.close_button.pressed.emit()
	say("返回地图 · 进出动效不参与存档或扣费")
	await hold(1.1)
	print("ART_UI_MOVIE_COMPLETED")
	quit()
