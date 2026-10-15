extends SceneTree

const SOURCE_BASE := "res://Assets/3DResources/Creatures/Human/"
const DESTINATION := "res://Scenes/Items/Weapons/Human/"
const SETTINGS := {
	"Human1Spear": {"label":"Human1 长矛", "grip":Vector2(1660.500000,1795.500000), "rotation":135.0, "tag":0},
	"Human2ClawGauntlet": {"label":"Human2 爪形护手", "grip":Vector2(272,720), "rotation":45.0, "tag":2},
	"Human3CurvedSword": {"label":"Human3 弯刀", "grip":Vector2(64,64), "rotation":180.0, "tag":1},
	"Human4Flail": {"label":"Human4 绳锤", "grip":Vector2(90,65), "rotation":180.0, "tag":3},
	"Human5Spear": {"label":"Human5 长矛", "grip":Vector2(75,650), "rotation":0.0, "tag":0},
	"Human5Shield": {"label":"Human5 木盾", "grip":Vector2(287,518), "rotation":0.0, "tag":4},
}

func _initialize() -> void: call_deferred("run")

func vector3_text(value: Vector3) -> String:
	return "Vector3(%.9f, %.9f, %.9f)" % [value.x,value.y,value.z]

func write_scene(record: Dictionary) -> Dictionary:
	var settings: Dictionary = SETTINGS[record.name]
	var unit: float = record.units_per_texture_pixel
	var pivot := Vector2(record.pivot_pixel[0],record.pivot_pixel[1])
	var size := Vector2(record.texture_size[0],record.texture_size[1])
	var grip: Vector2 = settings.grip
	var attachment := Vector3((grip.x-pivot.x)*unit,(pivot.y-grip.y)*unit,0)
	var forward := (Vector3(record.joint_out_local[0],record.joint_out_local[1],record.joint_out_local[2])-attachment).normalized()
	var sprite_center := Vector3((size.x*0.5-pivot.x)*unit,(pivot.y-size.y*0.5)*unit,0)
	var thickness: float = record.thickness
	var points := PackedStringArray()
	for point: Array in record.collision_points:
		points.append("%.9f, %.9f, %.9f" % [point[0],point[1],thickness*0.5*signf(float(point[2]))])
	var path := DESTINATION + str(record.name) + ".tscn"
	if not FileAccess.file_exists(path):
		var source := """[gd_scene load_steps=5 format=3]

[ext_resource type="PackedScene" path="res://Scenes/Items/_SampleWeapon.tscn" id="1_base"]
[ext_resource type="Texture2D" path="%s" id="2_texture"]
[ext_resource type="PackedScene" path="%s" id="3_model"]

[sub_resource type="ConvexPolygonShape3D" id="Shape"]
resource_local_to_scene = true
points = PackedVector3Array(%s)

[node name="%s" instance=ExtResource("1_base")]
mass = %.9f
can_be_picked_up = true
display_name = "%s"
weapon_tags = Array[int]([%d])
primary_attack_tag = %d
attack_forward_local = %s
item_image = ExtResource("2_texture")
sprite_visible = false
mesh_visible = true
attachment_local_position = %s
item_rotation = %.9f
preferred_holder_name = &""
has_attachment_point = true
metadata/source_png = "%s"
metadata/source_model_scene = "%s"
metadata/source_physical_scene = "%s"

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("Shape")

[node name="Sprite3D" type="Sprite3D" parent="."]
visible = false
position = %s
pixel_size = %.9f
texture = ExtResource("2_texture")

[node name="Model" parent="." instance=ExtResource("3_model")]
""" % [record.source,SOURCE_BASE+str(record.scene),", ".join(points),record.name,
			record.mass,settings.label,settings.tag,settings.tag,vector3_text(forward),vector3_text(attachment),deg_to_rad(settings.rotation),
			record.source,SOURCE_BASE+str(record.scene),record.physical_scene,vector3_text(sprite_center),unit]
		var file := FileAccess.open(path,FileAccess.WRITE)
		assert(file != null,"Could not create Human weapon scene")
		file.store_string(source)
		print("HUMAN_WEAPON_CREATED ",path)
	else:
		print("HUMAN_WEAPON_RETAINED ",path)
	return {"name":record.name,"display_name":settings.label,"set":record.set,
		"weapon_tags":[settings.tag],"primary_attack_tag":settings.tag,"attack_forward_local":[forward.x,forward.y,forward.z],
		"source_texture":record.source,"source_sha256":record.source_sha256,
		"source_original":"res://Assets/2DResources/AIGenerated/Unprocessed/Human/Humanoid_%d.png" % int(record.set),
		"model_glb":SOURCE_BASE+str(record.glb),"model_scene":SOURCE_BASE+str(record.scene),
		"volume_mesh":record.volume_mesh,"legacy_body_part":record.physical_scene,"weapon_scene":path,
		"grip_pixel":[grip.x,grip.y],"attachment_local_position":[attachment.x,attachment.y,attachment.z],
		"item_rotation_degrees":settings.rotation,"mass":record.mass,"thickness":thickness,
		"collision":"one simplified convex hull; visual holes and concavities do not cut the collider"}

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_BASE+"Metadata/model_manifest.json"))
	assert(DirAccess.make_dir_recursive_absolute(DESTINATION) == OK)
	var weapons: Array[Dictionary] = []
	for record: Dictionary in manifest.models:
		if SETTINGS.has(record.name): weapons.append(write_scene(record))
	assert(weapons.size() == SETTINGS.size())
	var file := FileAccess.open(SOURCE_BASE+"Metadata/weapon_manifest.json",FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"weapon_count":weapons.size(),"base_scene":"res://Scenes/Items/_SampleWeapon.tscn",
		"assets":"Reuse the existing AI-separated, completed Human textures and baked paper volumes without edits.",
		"weapons":weapons},"\t"))
	print("PASS: Six Human weapons inherit _SampleWeapon; source textures, meshes and BodyParts retained.")
	quit()
