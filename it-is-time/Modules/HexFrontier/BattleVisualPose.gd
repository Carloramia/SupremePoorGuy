extends RefCounted
## Angles are measured UP from the ground: 0 = decal, 90 = vertical paper.
## Visual transforms never change gameplay regions, collisions or spawn positions.
static func surface_mode(object: Dictionary) -> String:
	var explicit := str(object.get("visual",{}).get("surface_mode","auto"))
	if explicit != "auto": return explicit
	if object.type in ["mud","pit","post_battle","broken_barricade"]: return "ground"
	var asset := str(object.get("visual",{}).get("asset",""))
	if asset in ["battle_leaf_litter","battle_dry_patch","battle_shale_patch","demo_wood_fragment"]: return "ground"
	if object.type in ["tree","decoration","edge_decoration","web","thorns","indestructible","destructible","traversable","collision_damage"]: return "tilted"
	return "actor"

static func apply(sprite: Sprite3D, host: Node3D, object: Dictionary, default_tilt: float = 60.0) -> void:
	var visual: Dictionary = object.visual
	var object_scale: Array = object.get("scale",[1,1])
	var width := float(visual.size[0])*float(object_scale[0])
	var height := float(visual.size[1])*float(object_scale[1])
	var mode := surface_mode(object)
	var tilt := clampf(float(visual.get("tilt_degrees",default_tilt)),0,90)
	var lift := .035 + float(visual.get("z_index",0))*.0002
	var basis := Basis.IDENTITY
	var offset := Vector3.ZERO
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	if mode == "ground":
		basis = Basis(Vector3.UP,-deg_to_rad(float(object.rotation)))*Basis(Vector3.RIGHT,-PI*.5)
		offset.y = maxf(.015,lift)
	elif mode == "tilted":
		var angle := deg_to_rad(tilt)
		basis = Basis(Vector3.RIGHT,angle-PI*.5)
		# Bottom pivot stays on the same X/Z ground contact while the top leans away.
		offset = Vector3(0,height*.5*sin(angle)+maxf(.015,lift),-height*.5*cos(angle))
	else:
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		offset.y = height*.5
	var texture_size := sprite.texture.get_size()
	var scaled_basis := Basis(basis.x*(width/texture_size.x),basis.y*(height/texture_size.y),basis.z)
	var desired := Transform3D(scaled_basis,host.global_position+offset)
	# Compensate authored map rotation/scale for camera-facing paper, keeping the
	# transform local so moving or hiding the host still moves/hides its visual.
	sprite.transform = host.global_transform.affine_inverse()*desired
	sprite.set_meta("surface_mode",mode)
	sprite.set_meta("tilt_from_ground",tilt if mode=="tilted" else 0.0)
