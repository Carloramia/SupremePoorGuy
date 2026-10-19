extends SceneTree
const View=preload("res://BattlePreview3D.gd")
const Pose=preload("res://battle_visual_pose.gd")
var view
var failed:int=0
func check(ok:bool,label:String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok:failed+=1
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1440,900);view=View.new();root.add_child(view)
	var errors:int=0;var tilted:int=0;var grounded:int=0
	for map:Dictionary in view.spec.maps:
		for object:Dictionary in map.objects:
			if object.type in ["deployment","enemy"] or not object.visual.get("visible",true) or str(object.visual.asset).is_empty():continue
			var host:=Node3D.new();host.position=Vector3(object.position[0],object.height,object.position[1]);host.rotation.y=-deg_to_rad(float(object.rotation));host.scale=Vector3(object.scale[0],1,object.scale[1]);view.add_child(host)
			var sprite:=Sprite3D.new();sprite.pixel_size=1;sprite.texture=view.texture(view.spec.assets[object.visual.asset].native_path);host.add_child(sprite);Pose.apply(sprite,host,object)
			var size:Vector2=sprite.texture.get_size();var mode:=Pose.surface_mode(object)
			if mode=="tilted":
				tilted+=1
				var bottom:Vector3=sprite.global_transform*Vector3(0,-size.y*.5,0)
				if Vector2(bottom.x,bottom.z).distance_to(Vector2(host.position.x,host.position.z))>.001 or absf(bottom.y-float(object.height))>.3:errors+=1
				if sprite.global_basis.y.normalized().dot(Vector3.UP)<.8:errors+=1
			elif mode=="ground":
				grounded+=1
				if absf(sprite.global_basis.z.normalized().dot(Vector3.UP))<.999:errors+=1
			host.free()
	check(view.spec.maps.size()==41,"all 41 current battle maps are available")
	check(errors==0,"all visible scenery keeps its ground contact and correct tilt/decal orientation")
	check(tilted>0 and grounded>0,"raised scenery and grounded mud/patches coexist: %d / %d"%[tilted,grounded])
	print("BATTLE_PRESENTATION_TESTS failures=",failed)
	quit(1 if failed else 0)
