extends SceneTree
const Hex=preload("res://HexMapData.gd")
func _initialize() -> void:
	var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://scene.json"))
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(spec.layout_path))
	var position:=Vector2.ZERO
	for site in document.sites:
		if site.id=="layout_summoning_hut":
			site.position=[site.position[0]+255,site.position[1]+80];position=Hex.v(site.position)
			for asset in document.assets:
				if asset.id==site.visual.asset_id:
					var entry:=Hex.v(document.spawn_site_anchor);var anchor:=Hex.v(site.visual.get("anchor",asset.get("anchor",[.5,1])))
					position+=(entry-anchor)*Vector2(float(site.visual.width),float(site.visual.width)*float(asset.height)/float(asset.width))
	var model=Hex.new();var error:String=model.set_document(document)
	var ok:=error.is_empty() and Hex.v(model.document.spawn).is_equal_approx(position) and float(model.document.vision_radius)==630
	print(("PASS " if ok else "FAIL ")+"native initial player and 630 sight follow the current hut position")
	quit(0 if ok else 1)
