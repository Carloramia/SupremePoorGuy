extends Node3D
const Catalog = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
@export var map_id := ""
@export_file("*.json") var data_path := ""
var deployed_ids: Array = []

func deploy(units: Array, deployment_id := "", factory: Callable = Callable()) -> void:
	for child in $Party.get_children():
		$Party.remove_child(child)
		child.queue_free()
	deployed_ids.clear()
	var definition:=Catalog.map_data(map_id)
	var deployment: Dictionary={}
	for object in definition.objects:
		if object.type=="deployment" and (deployment_id.is_empty() or object.id==deployment_id):
			deployment=object
			break
	if deployment.is_empty():return
	# Preserve every inventory instance; additional slots are placed inside the deployment region.
	for i in units.size():
		var unit: Dictionary=units[i]
		var local:=Catalog.v(deployment.slots[i%deployment.slots.size()])
		if i>=deployment.slots.size():local+=Vector2(0,-0.65*(i/deployment.slots.size()))
		var point:=Catalog.world_point(deployment,local)
		var actor: Node3D=factory.call(unit.duplicate(true)) if factory.is_valid() else _marker(unit)
		actor.name="Unit_"+str(unit.id)
		actor.set_meta("monster_id",unit.id)
		actor.set_meta("inventory_snapshot",unit.duplicate(true))
		$Party.add_child(actor)
		actor.position=Vector3(point.x,0.7,point.y)
		deployed_ids.append(unit.id)

func _marker(unit: Dictionary) -> Node3D:
	var actor:=Node3D.new()
	var visual:=MeshInstance3D.new()
	var sphere:=SphereMesh.new()
	sphere.radius=.55
	sphere.height=1.1
	visual.mesh=sphere
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(unit.get("color","#358d81"))
	visual.material_override=material
	actor.add_child(visual)
	return actor
