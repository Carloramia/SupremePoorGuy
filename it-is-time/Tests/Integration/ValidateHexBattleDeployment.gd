extends SceneTree
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const HOST = preload("res://Scripts/Application/BattleHost.gd")
const ADAPTER = preload("res://Scripts/Application/DeliveryBattleEnvironmentAdapter.gd")
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("HEX_DEPLOYMENT_TIMEOUT"); quit(1))
	call_deferred("run")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	CATALOG.select_version("20261019")
	var settings := load("res://Content/Maps/FrontierEditor_20261019/Runtime/BattleSettings.tres") as DeliveryBattleSettings
	var party: Array = []
	for id: String in ["wolf","snake","stump_beast","horned_beast"]: party.append(FACTORY.template(id))
	var count := 0
	for camp: Dictionary in CATALOG.objects_in_role("interactive"):
		if camp.type!="camp" or not settings.availability_error(camp.enemy_config_id).is_empty(): continue
		var host := HOST.new()
		host.delivery_settings=settings
		host.delivery_request={"battle_map_id":camp.battle_map_id,"enemy_config_id":camp.enemy_config_id,"deployment_id":""}
		root.add_child(host)
		var adapter := ADAPTER.new()
		var built: bool=adapter.build(host,party)
		if not built: failures.append(str(camp.id)+": "+str(host.last_error))
		elif host._deployment.size()!=4 or host._enemy_positions.size()!=host._enemy_initial.size() or host.capacity_status(1).used>host.capacity_settings.total_capacity: failures.append(str(camp.id)+": slot count mismatch")
		print("HEX_BATTLE_PLACEMENT ",camp.id," ",built," enemies=",host._enemy_positions.size()," reason=",host.last_error)
		if is_instance_valid(host._geometry): host._geometry.free(); host._geometry=null
		host.free()
		count+=1
		await process_frame
	for error: String in failures: push_error(error)
	print("HEX_BATTLE_DEPLOYMENT ","PASSED" if failures.is_empty() and count==31 else "FAILED"," maps=",count," failures=",failures.size())
	quit(0 if failures.is_empty() and count==31 else 1)
