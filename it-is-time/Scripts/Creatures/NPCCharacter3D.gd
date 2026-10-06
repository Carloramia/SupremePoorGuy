extends "res://Scripts/Creatures/PhysicalCharacterController.gd"

@export_group("Initial Equipment")
## Assign a weapon scene exported from Weapon Workshop, or another SampleWeapon3D scene.
@export var initial_weapon_scene: PackedScene

func _ready() -> void:
	super._ready()
	call_deferred("_equip_initial_weapon")

func _equip_initial_weapon() -> void:
	if initial_weapon_scene == null: return
	var inventory := get_node_or_null("InventoryController3D")
	if inventory == null or not inventory.equip_initial_weapon(initial_weapon_scene):
		push_warning("[npc_equipment] Initial weapon could not be equipped: "+str(get_path()))
