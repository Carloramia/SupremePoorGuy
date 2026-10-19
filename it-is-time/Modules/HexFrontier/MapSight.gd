extends RefCounted
## Shared sight geometry. Only explicit opaque terrain participates, not every collider.
const RAY_COUNT:=256

static func wall_kinds(cells:Dictionary) -> Dictionary:
	var remaining:Dictionary={};var kinds:Dictionary={}
	for key in cells:
		if cells[key].get("feature","")=="wall":remaining[key]=true
	var directions:=[Vector2i(1,0),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,-1)]
	while not remaining.is_empty():
		var start:Vector2i=remaining.keys()[0];remaining.erase(start)
		var pending:Array=[start];var component:Array=[];var all_pit:=true
		while not pending.is_empty():
			var key:Vector2i=pending.pop_back();component.append(key)
			all_pit=all_pit and cells[key].get("region","")=="pit" and cells[key].get("wall_material","")!="source_mountain"
			for direction in directions:
				var neighbor:Vector2i=key+direction
				if remaining.has(neighbor):remaining.erase(neighbor);pending.append(neighbor)
		var kind:="pit" if all_pit and component.size()<=7 else "mountain"
		for key in component:kinds[key]=kind
	return kinds

static func occluder(polygon:PackedVector2Array) -> Dictionary:
	var bounds:=Rect2(polygon[0],Vector2.ZERO)
	for point in polygon:bounds=bounds.expand(point)
	return {"_polygon":polygon,"_bounds":bounds}

static func occluder_rings(rings:Array) -> Dictionary:
	var result:=occluder(rings[0]);var bounds:Rect2=result._bounds
	for ring in rings:
		for p in ring:bounds=bounds.expand(p)
	result["_rings"]=rings;result["_bounds"]=bounds
	return result

static func contains_surface(obstacle:Dictionary,point:Vector2) -> bool:
	var inside:=false
	for ring in obstacle.get("_rings",[obstacle._polygon]):
		if Geometry2D.is_point_in_polygon(point,ring):inside=not inside
	return inside

static func art_surfaces(document:Dictionary) -> Array:
	var assets:Dictionary={};var result:Array=[]
	for a in document.get("assets",[]):assets[a.id]=a
	for site in document.sites:
		var boundary:Dictionary=site.get("terrain",{}).get("boundary",{})
		var visual:Dictionary=site.get("visual",{});var asset:Dictionary=assets.get(visual.get("asset_id",""),{})
		if boundary.get("mode","")!="art_alpha" or asset.is_empty() or boundary.get("asset_id","")!=asset.id or boundary.get("asset_path","")!=asset.path:continue
		var w:=float(visual.width);var h:=w*float(asset.height)/float(asset.width)*float(visual.get("height_scale",1))
		var av:Array=visual.get("anchor",asset.get("anchor",[.5,1]));var anchor:=Vector2(av[0],av[1]);var ov:Array=visual.get("offset",[0,0]);var offset:=Vector2(ov[0],ov[1]);var pos:=Vector2(site.position[0],site.position[1])+offset
		var rings:Array=[]
		for source_ring in boundary.rings:
			var ring:=PackedVector2Array()
			for p in source_ring:ring.append((Vector2(p[0],p[1])-anchor)*Vector2(w,h))
			for i in ring.size():ring[i]=pos+ring[i].rotated(deg_to_rad(float(visual.get("rotation",0))))
			rings.append(ring)
		var surface:=occluder_rings(rings);surface["site_id"]=site.id;surface["blocks_movement"]=site.terrain.get("blocks_movement",true);surface["blocks_vision"]=site.terrain.get("blocks_vision",true);result.append(surface)
	return result

static func ray_distance(from:Vector2,to:Vector2,occluders:Array) -> float:
	var distance:=from.distance_to(to)
	var segment_bounds:=Rect2(from,Vector2.ZERO).expand(to)
	for obstacle in occluders:
		var bounds:Rect2=obstacle._bounds
		if not bounds.intersects(segment_bounds,true):continue
		var polygon:PackedVector2Array=obstacle._polygon
		if bounds.has_point(from) and contains_surface(obstacle,from):return 0.0
		for ring in obstacle.get("_rings",[polygon]):
			for i in ring.size():
				var hit=Geometry2D.segment_intersects_segment(from,to,ring[i],ring[(i+1)%ring.size()])
				if hit!=null:distance=minf(distance,from.distance_to(hit))
	return distance

static func visible(from:Vector2,to:Vector2,occluders:Array) -> bool:
	return from.distance_to(to)<=ray_distance(from,to,occluders)+.01

static func visible_from_segment(point:Vector2,from:Vector2,to:Vector2,radius:float,occluders:Array) -> bool:
	var nearest:=Geometry2D.get_closest_point_to_segment(point,from,to)
	if point.distance_to(nearest)>radius:return false
	if visible(nearest,point,occluders):return true
	# Another location on the travelled segment can see around the mountain's end.
	var steps:=maxi(1,ceili(from.distance_to(to)/maxf(8,radius/4)))
	for i in range(steps+1):
		var origin:=from.lerp(to,float(i)/steps)
		if origin.distance_to(point)<=radius and visible(origin,point,occluders):return true
	return false

# Logical sight stops on the near face. The second channel only exposes the
# first connected opaque surface, never a separate ridge or terrain behind it.
static func ray_distances(from:Vector2,to:Vector2,occluders:Array) -> Vector2:
	var length:=from.distance_to(to)
	var area:=Rect2(from,Vector2.ZERO).expand(to)
	var intervals:Array=[]
	for obstacle in occluders:
		if not obstacle._bounds.intersects(area,true):continue
		var polygon:PackedVector2Array=obstacle._polygon
		var hits:Array=[0.0,length]
		for ring in obstacle.get("_rings",[polygon]):
			for i in ring.size():
				var hit=Geometry2D.segment_intersects_segment(from,to,ring[i],ring[(i+1)%ring.size()])
				if hit!=null:hits.append(from.distance_to(hit))
		hits.sort()
		var unique:Array=[]
		for hit in hits:
			if unique.is_empty() or absf(hit-unique.back())>.001:unique.append(hit)
		for i in range(unique.size()-1):
			var midpoint:=from.lerp(to,(float(unique[i])+float(unique[i+1]))/(2.0*length))
			if contains_surface(obstacle,midpoint):intervals.append(Vector2(unique[i],unique[i+1]))
	if intervals.is_empty():return Vector2(length,length)
	intervals.sort_custom(func(a,b):return a.x<b.x)
	var front:float=intervals[0].x
	var surface:float=intervals[0].y
	for interval in intervals:
		if interval.x>surface+.5:break
		surface=maxf(surface,interval.y)
	return Vector2(front,surface)

static func update_rays(image:Image,from:Vector2,radius:float,occluders:Array) -> void:
	if occluders.is_empty():image.fill(Color.WHITE);return
	for i in image.get_width():
		var to:=from+Vector2.from_angle(TAU*(i+.5)/image.get_width())*radius
		var distances:=ray_distances(from,to,occluders)/radius
		image.set_pixel(i,0,Color(distances.x,distances.y,0,1))

static func surface_visible_in_rays(image:Image,from:Vector2,point:Vector2,radius:float) -> bool:
	var delta:=point-from
	if delta.length()>radius:return false
	var angle:=fposmod(delta.angle()/TAU,1.0)*image.get_width()-.5
	var lo:=posmod(floori(angle),image.get_width())
	var hi:=posmod(lo+1,image.get_width())
	var a:=image.get_pixel(lo,0);var b:=image.get_pixel(hi,0)
	# Conservative at angular discontinuities; no exploration leaks through thin ridges.
	return delta.length()<=minf(maxf(a.r,a.g),maxf(b.r,b.g))*radius+.5

static func surface_sweep(from:Vector2,to:Vector2,radius:float,occluders:Array) -> Array:
	var result:Array=[]
	var steps:=maxi(1,ceili(from.distance_to(to)/maxf(8,radius/4)))
	for i in range(steps+1):
		var origin:=from.lerp(to,float(i)/steps)
		var image:=Image.create(RAY_COUNT,1,false,Image.FORMAT_RG8)
		update_rays(image,origin,radius,occluders)
		result.append({"origin":origin,"rays":image})
	return result

static func surface_visible_in_sweep(point:Vector2,sweep:Array,radius:float) -> bool:
	for sample in sweep:
		if surface_visible_in_rays(sample.rays,sample.origin,point,radius):return true
	return false

# Close the fog opening inside the first solid interval's rear foot.
# Lifted art uses its own silhouette below, keeping concave rock faces intact.
static func _rear_overlap_shader() -> String:
	return """
uniform float rear_overlap=32.0;
float rear_visibility(vec2 delta,vec2 ray,float footprint){
 float thickness=(ray.g-ray.r)*radius;
 // White rays are open ground; a radius-clipped rock has no visible rear edge.
 if(ray.g>=.998 || thickness<=.5)return 1.0;
 float inset=min(rear_overlap,thickness*.35);
 float pad=min(footprint,thickness*.10);
 return 1.0-smoothstep(ray.g*radius-inset,ray.g*radius,length(delta)+pad);
}
"""

static func fog_shader() -> String:
	return """shader_type canvas_item;
uniform sampler2D explored_mask : filter_linear, repeat_disable;
uniform sampler2D sight_rays : filter_linear, repeat_enable;
uniform vec2 map_origin; uniform vec2 map_size;
uniform vec2 player; uniform vec2 sight_origin; uniform vec2 camera; uniform vec2 view_size;
uniform float zoom=1.0; uniform float radius=210.0; uniform float feather=64.0;
uniform float cloud_scale=280.0; uniform float cloud_speed=.12;
uniform float pixel_size=12.0; uniform float pixel_steps=8.0;
uniform vec4 unknown_color : source_color=vec4(.208,.282,.251,1.0);
uniform vec4 explored_color : source_color=vec4(.094,.169,.149,.76);
"""+_rear_overlap_shader()+"""
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
float clouds(vec2 p){return .53*noise(p)+.27*noise(p*2.07+13.1)+.13*noise(p*4.03+7.7)+.07*noise(p*8.11);}
float memory(vec2 uv){
 vec2 d=min(vec2(feather*.7)/map_size,vec2(2.0)/vec2(textureSize(explored_mask,0)));
 float v=texture(explored_mask,uv).r*4.0;
 v+=(texture(explored_mask,uv+vec2(d.x,0)).r+texture(explored_mask,uv-vec2(d.x,0)).r+texture(explored_mask,uv+vec2(0,d.y)).r+texture(explored_mask,uv-vec2(0,d.y)).r)*2.0;
 v+=texture(explored_mask,uv+d).r+texture(explored_mask,uv-d).r+texture(explored_mask,uv+vec2(d.x,-d.y)).r+texture(explored_mask,uv+vec2(-d.x,d.y)).r;
 return v/16.0;
}
float raw_visibility(vec2 point){
 vec2 delta=point-sight_origin;
 float angle=atan(delta.y,delta.x)/6.28318530718;
 vec2 ray=texture(sight_rays,vec2(fract(angle),.5)).rg;
 float limit=max(ray.r,ray.g)*radius;
 float shadow=1.0-smoothstep(limit,limit+min(feather*.25,18.0),length(delta));
 return min(shadow,rear_visibility(delta,ray,0.0))*(1.0-smoothstep(radius-feather*.4,radius,distance(point,player)));
}
void fragment(){
 vec2 world=(UV*view_size-view_size*.5)/zoom+camera;
 vec2 uv=(world-map_origin)/map_size;
 float explored=memory(clamp(uv,vec2(0),vec2(1)));
 if(any(lessThan(uv,vec2(0)))||any(greaterThan(uv,vec2(1))))explored=0.0;
 vec2 drift=vec2(TIME*cloud_speed*.12,-TIME*cloud_speed*.07);
 float mist=clouds(world/max(cloud_scale,40.0)+drift);
 float fine=clouds(world/max(cloud_scale*.43,24.0)-drift*.65);
 // World-locked square samples affect the fog only; art textures retain full detail.
 vec2 block=floor((world-map_origin)/max(pixel_size,1.0));
 vec2 pixel_world=map_origin+(block+.5)*max(pixel_size,1.0);
 float visible=0.0;
 float total_weight=0.0;
 // A Cartesian filter rounds occlusion corners without the fan bands of angular taps.
 for(int y=-3;y<=3;y++){
  for(int x=-3;x<=3;x++){
   vec2 offset=vec2(float(x),float(y));
   float weight=exp(-dot(offset,offset)/5.5);
   visible+=raw_visibility(pixel_world+offset*feather*.20)*weight;
   total_weight+=weight;
  }
 }
 visible/=total_weight;
 // Feathering may round corners, but must never reopen a strip behind a rock.
 vec2 rear_delta=pixel_world-sight_origin;
 vec2 rear_ray=texture(sight_rays,vec2(fract(atan(rear_delta.y,rear_delta.x)/6.28318530718),.5)).rg;
 visible=min(visible,rear_visibility(rear_delta,rear_ray,pixel_size*.707107));
 visible=clamp(floor(visible*pixel_steps+.35+(hash(block)-.5)*.32)/pixel_steps,0.0,1.0);
 // The farthest corner of an exposed block must stay inside the true sight radius.
 visible*=1.0-smoothstep(radius-pixel_size*1.5,radius,distance(pixel_world,player)+pixel_size*.707107);
 vec3 haze=mix(unknown_color.rgb,vec3(.53,.59,.56),.60);
 vec3 cloud_color=haze*(.83+.30*mist)+vec3(.028)*fine;
 vec4 unknown=vec4(cloud_color,1.0);
 vec4 remembered=vec4(mix(explored_color.rgb,vec3(.49,.55,.51),.48)*( .91+.16*mist),clamp(explored_color.a,.35,.64));
 COLOR=mix(unknown,remembered,smoothstep(.0,1.0,explored));
 COLOR.a*=1.0-visible;
}"""

static func surface_shader() -> String:
	return """shader_type canvas_item;
uniform vec2 player; uniform vec2 camera; uniform vec2 view_size; uniform vec2 map_origin;
uniform float zoom=1.0; uniform float radius=630.0; uniform float pixel_size=12.0;
uniform bool rear_mask_enabled=false;
uniform sampler2D rear_mask : filter_linear, repeat_disable;
uniform vec4 rear_bounds;
uniform float rear_distance_scale=64.0; uniform float rear_overlap=32.0;
uniform sampler2D fog_texture : filter_nearest, repeat_disable;
uniform bool fog_texture_available=false;
uniform float rear_mist_strength=.22;
float rear_visibility(vec2 world){
 if(!rear_mask_enabled)return 1.0;
 vec2 uv=(world-rear_bounds.xy)/rear_bounds.zw;
 vec2 texel=1.0/vec2(textureSize(rear_mask,0));
 float d=(texture(rear_mask,uv).r*2.0-1.0)*rear_distance_scale;
 vec2 gradient=vec2(texture(rear_mask,uv+vec2(texel.x,0)).r-texture(rear_mask,uv-vec2(texel.x,0)).r,texture(rear_mask,uv+vec2(0,texel.y)).r-texture(rear_mask,uv-vec2(0,texel.y)).r)/(texel*rear_bounds.zw);
 vec2 outward=-gradient/max(length(gradient),.00001);
 vec2 away=(world-player)/max(distance(world,player),.001);
 float back=smoothstep(.05,.60,dot(outward,away));
 return 1.0-back*(1.0-smoothstep(0.0,rear_overlap,max(d,0.0)));
}
void fragment(){
 vec2 world=(SCREEN_UV*view_size-view_size*.5)/zoom+camera;
 float edge=1.0-smoothstep(radius-pixel_size*1.8,radius,distance(world,player));
 // Keep the opaque silhouette intact. Only a thin colour veil belongs on the art;
 // Pixel opacity steps belong to the fog buffer, never the rock artwork.
 float rim=1.0-rear_visibility(world);
 vec3 mist_color=vec3(.40,.46,.43);
 if(fog_texture_available){
  vec4 mist=texture(fog_texture,SCREEN_UV);
  if(mist.a>.02)mist_color=clamp(mist.rgb/mist.a,vec3(0.0),vec3(1.0));
 }
 COLOR.rgb=mix(COLOR.rgb,mist_color,rim*rear_mist_strength);
 COLOR.a*=edge;
}"""
