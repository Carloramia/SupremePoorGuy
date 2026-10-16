extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var catalog = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
	var factory = preload("res://Scripts/Application/CreatureFactory.gd")
	assert(catalog.index().maps.size()==14 and catalog.world().objects.size()==293)
	for id: String in factory.DEFINITIONS:
		var record: Dictionary = factory.template(id)
		assert(factory.valid_record(record))
		print("DELIVERY_BODY_BOUNDS ",id," ",factory.local_bounds(record))
	var settings = preload("res://Resources/Application/FrontierDeliveryBattle.tres")
	for id: String in settings.enemy_rosters:
		assert(not settings.availability_error(id).is_empty() if "rat_" in id else settings.availability_error(id).is_empty())
	print("DELIVERY_ASSETS_PASSED")
	quit()
