extends SceneTree
const MAP = preload("res://Modules/HexFrontier/CurrentMapPreview.gd")
const ROOT_PATH := "res://Content/Maps/HexFrontier_20261019/"
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT_PATH+"ImportReceipt.json"))
	check(receipt.layout_sha256==FileAccess.get_sha256(ROOT_PATH+"hex_layout.json"),"World layout bytes preserved exactly")
	check(receipt.battle_sha256==FileAccess.get_sha256(ROOT_PATH+"hex_battles.json"),"Battle source bytes preserved exactly")
	check(receipt.map_count==41 and receipt.site_count==631,"All authored maps and sites imported")
	for item: Dictionary in receipt.art_files.values():
		check(FileAccess.get_sha256("res://"+item.target)==item.sha256,"Artwork bytes preserved: "+item.target)
	var view := MAP.new()
	view.size = Vector2(1280,720)
	root.add_child(view)
	await process_frame
	check(view.doc.get("sites",[]).size()==631,"Actual native visual component loads authoring layout")
	check(view.model.cells.size()==10877,"Actual hex navigation uses all authored cells")
	check(not view.spec.mountain_surfaces.is_empty() and not view.visual_surfaces.is_empty(),"Mountain and rear-edge constraints retained")
	check(not view.tile_nodes.is_empty(),"Original HD background tiles load around spawn")
	check(view.assets.size()==502,"All original asset registrations retained")
	check(view.player.is_equal_approx(view.Hex.v(view.doc.spawn)),"Spawn derives from summoning-hut anchor")
	check(is_equal_approx(float(view.doc.vision_radius),630.0),"Sight radius retains authored 630 units")
	view.queue_free()
	await process_frame
	print("HEX_MAP_IMPORT_", "PASSED" if failures==0 else "FAILED", " checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
