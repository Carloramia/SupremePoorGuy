extends SceneTree

const BASE := "res://Content/Maps/FrontierEditor_20261019/"
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
var checked := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checked += 1
	if not ok: failures.append(message)

func read(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(value is Dictionary,path+" is a JSON object")
	return value if value is Dictionary else {}

func run() -> void:
	var manifest := read(BASE+"Migration/files.json")
	check(manifest.status=="staged_not_active","original migration provenance retained")
	for path: String in manifest.protected_runtime_files:
		if FileAccess.file_exists(BASE+"Runtime/integration.json") and path in ["Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd","Scripts/Application/CreatureFactory.gd"]: continue
		check(FileAccess.get_sha256("res://"+path)==manifest.protected_runtime_files[path],"active file unchanged: "+path)
	var paths := read(BASE+"Migration/asset_paths.json")
	for uri: String in paths.values():
		check(uri.begins_with(BASE+"Assets/") and FileAccess.file_exists(uri),"portable asset: "+uri)
	var world := read(BASE+"Data/hex_layout.json")
	var original := read(BASE+"Source/hex_layout.json")
	check(world.cells.size()==10877 and world.sites.size()==631,"full world layout retained")
	check(world.spawn==original.spawn and world.bounds==original.bounds and world.grid==original.grid,"coordinates retained")
	check(world.fog.enabled and world.fog.preserve_exploration,"fog contract retained")
	check(world.background.source_tiles.tiles.size()==48,"HD tiles retained")
	var clips := read(world.background.source_tiles.clip_asset)
	for tile: Dictionary in world.background.source_tiles.tiles:
		check(clips.tiles.has(tile.id),"clip geometry retained: "+tile.id)
	var battles := read(BASE+"Data/hex_battles.json")
	check(battles.maps.size()==41,"41 battle maps retained")
	var existing := 0
	for map: Dictionary in battles.maps:
		var data := read(BASE+"Data/BattleLevels/"+str(map.id)+".battlelevel.json")
		check(data.format=="frontier-battle-level" and data.map.id==map.id,"compiled map identity: "+str(map.id))
		check(data.map.radius==map.radius and data.map.orientation==map.orientation,"battle units retained: "+str(map.id))
		if CATALOG.index().maps.has(map.id): existing+=1
	check(existing==13,"13 old battle ID candidates; 28 additions")
	check(CATALOG.index().maps.size()==14 and CATALOG.world().objects.size()==293,"live game retains its original catalog")
	check(CATALOG.world().spawn!=world.spawn,"new world requires explicit save migration")
	print("HEX_MAP_HANDOFF_CHECKS ",checked," failures=",failures.size())
	for message: String in failures: push_error(message)
	if failures.is_empty(): print("HEX_MAP_HANDOFF_PASSED")
	quit(0 if failures.is_empty() else 1)
