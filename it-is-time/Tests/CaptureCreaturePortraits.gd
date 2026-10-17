extends "res://Tests/ValidateCreaturePortraits.gd"
const OUTPUT := "D:/GameJamWorkspace/Reports/CreaturePortraits_2026-10-16"

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	root.size = Vector2i(1200,750)
	var background := ColorRect.new()
	background.color = Color.WHITE
	background.size = Vector2(1200,750)
	root.add_child(background)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(15,15)
	root.add_child(grid)
	var renderer := RENDERER.new()
	root.add_child(renderer)
	var portraits := {}
	for id: String in FACTORY.DEFINITIONS:
		var column := VBoxContainer.new()
		grid.add_child(column)
		var label := Label.new()
		label.text = id
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color",Color.BLACK)
		column.add_child(label)
		var portrait := PORTRAIT.instantiate()
		portrait.custom_minimum_size = Vector2(380,300)
		column.add_child(portrait)
		portraits[id] = portrait
		renderer.request(portrait,FACTORY.template(id))
	var duplicate_portrait := PORTRAIT.instantiate()
	root.add_child(duplicate_portrait)
	duplicate_portrait.hide()
	var duplicate_record := FACTORY.template("wolf")
	duplicate_record.name = "Another wolf"
	duplicate_record.hp *= 2.0
	renderer.request(duplicate_portrait,duplicate_record)
	for frame: int in 600:
		await process_frame
		if renderer._cache.size()==FACTORY.DEFINITIONS.size() and not renderer._busy: break
	check(renderer._cache.size()==FACTORY.DEFINITIONS.size(),"All six species render once with deduplicated pending jobs")
	for id: String in portraits:
		var texture: Texture2D = portraits[id].get_node("Artwork").texture
		check(texture != renderer._placeholder,"Rendered picture replaces the loading placeholder: "+id)
		var image := texture.get_image()
		check(image.get_size()==renderer.IMAGE_SIZE,"Portrait resolution is fixed")
		for corner: Vector2i in [Vector2i.ZERO,Vector2i(511,0),Vector2i(0,383),Vector2i(511,383)]:
			var color := image.get_pixelv(corner)
			check(color.r>0.99 and color.g>0.99 and color.b>0.99 and color.a>0.99,"Portrait has an opaque pure-white background: "+id)
		var visible_samples := 0
		for y: int in range(0,image.get_height(),4):
			for x: int in range(0,image.get_width(),4):
				var color := image.get_pixel(x,y)
				if minf(color.r,minf(color.g,color.b))<0.9: visible_samples += 1
		check(visible_samples>60,"Portrait contains the actual creature rather than a blank background: "+id)
		check(image.save_png(OUTPUT+"/"+id+".png")==OK,"Save species portrait")
		print("CREATURE_PORTRAIT_CAPTURE species=",id," visible_samples=",visible_samples)
	check(duplicate_portrait.get_node("Artwork").texture==portraits.wolf.get_node("Artwork").texture,"Different stats/names reuse the same visual texture")
	await process_frame
	check(renderer.get_child_count()==0,"One-shot viewports are released after rendering")
	var stale := PORTRAIT.instantiate()
	root.add_child(stale)
	var changed := FACTORY.template("wolf")
	changed.poses["GeneratedParts"][9] += 0.5
	renderer.request(stale,changed)
	stale.free()
	var swapped := PORTRAIT.instantiate()
	root.add_child(swapped)
	swapped.hide()
	var changed_human := FACTORY.template("human")
	changed_human.poses["GeneratedParts"][9] += 0.5
	renderer.request(swapped,changed_human)
	renderer.request(swapped,FACTORY.template("wolf"))
	for frame: int in 120:
		await process_frame
		if renderer._pending.is_empty(): break
	check(renderer._pending.is_empty() and not renderer._busy,"Closing an avatar while rendering safely releases its pending request")
	check(swapped.get_node("Artwork").texture==portraits.wolf.get_node("Artwork").texture,"An old pending request cannot overwrite a newly selected creature")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT+"/portraits.png")==OK,"Save contact sheet")
	if not failed: print("CREATURE_PORTRAIT_CAPTURE_VALIDATION_PASSED")
	quit(1 if failed else 0)
