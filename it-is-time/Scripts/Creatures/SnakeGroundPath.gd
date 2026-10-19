extends RefCounted

# World-space horizontal route. Only the unvisited preview can be replanned.
var points: Array[Dictionary] = []
var corners: Array[Dictionary] = []
var turn_markers: Array[Dictionary] = []
var wavelength := 1.0
var amplitude := 0.0
var step := 0.1
var keep_length := 1.0
var requested_heading := Vector3.RIGHT
var _visited_high := 0.0

func reset(origin: Vector3, forward: Vector3, length: float, wave_length: float, wave_amplitude: float, spacing: float) -> void:
	points.clear()
	corners.clear()
	wavelength = wave_length
	amplitude = wave_amplitude
	step = maxf(spacing,length/1024.0)
	keep_length = length
	requested_heading = forward.slide(Vector3.UP).normalized()
	origin.y = 0.0
	var count := ceili(length / step)
	_visited_high = 0.0
	var previous := origin
	var distance := 0.0
	for i: int in range(0, -count-1, -1):
		var u := i * step
		var center := origin + requested_heading * u
		var position := _position(center,requested_heading,u)
		distance -= position.distance_to(previous)
		points.append({"s": distance, "u": u, "position": position, "center": center, "forward": requested_heading})
		previous = position
	points.reverse()
	turn_markers.assign([{"s": float(points[0].s), "facing": requested_heading}])

func mark_turn(distance: float, facing: Vector3) -> void:
	facing = facing.slide(Vector3.UP).normalized()
	if facing.is_zero_approx(): return
	if not turn_markers.is_empty() and Vector3(turn_markers[-1].facing).dot(facing) > 0.999: return
	# An unvisited marker at the same place can be replaced without changing history.
	while turn_markers.size() > 1 and float(turn_markers[-1].s) >= distance-0.000001: turn_markers.pop_back()
	if not turn_markers.is_empty() and Vector3(turn_markers[-1].facing).dot(facing)>0.999: return
	turn_markers.append({"s": distance, "facing": facing})

func facing_at(distance: float) -> Vector3:
	if turn_markers.is_empty(): return requested_heading
	var low := 0
	var high := turn_markers.size()-1
	while low < high:
		var middle := (low+high+1)/2
		if float(turn_markers[middle].s) <= distance: low = middle
		else: high = middle-1
	return turn_markers[low].facing

func _index(distance: float) -> int:
	var low := 0
	var high := points.size()-1
	while low < high:
		var middle := (low+high+1)/2
		if float(points[middle].s) <= distance: low = middle
		else: high = middle-1
	return low

func _position(center: Vector3, forward: Vector3, u: float) -> Vector3:
	return center+forward.cross(Vector3.UP)*(amplitude*sin(TAU*u/wavelength))

func sample(distance: float) -> Dictionary:
	var index := _index(distance)
	var a: Dictionary = points[index]
	var b: Dictionary = points[mini(index+1, points.size()-1)]
	var tangent: Vector3 = (b.position-a.position).normalized() if index+1 < points.size() else a.forward
	if distance < float(a.s) or index == points.size()-1:
		return {"position": Vector3(a.position)+tangent*(distance-float(a.s)), "tangent": tangent, "forward": a.forward, "u": float(a.u)+distance-float(a.s)}
	var t := (distance-float(a.s))/maxf(float(b.s)-float(a.s),0.000001)
	return {"position": Vector3(a.position).lerp(b.position,t), "tangent": tangent,
		"forward": a.forward, "u": lerpf(a.u,b.u,t)}

func ensure(progress: float, preview: float, heading: Vector3, occupied_high: float = -1e30) -> void:
	heading = heading.slide(Vector3.UP).normalized()
	if heading.is_zero_approx(): heading = requested_heading
	if requested_heading.dot(heading) < cos(deg_to_rad(2.0)):
		# Preserve the route beneath every body part before redirecting the preview.
		points.resize(mini(_index(maxf(maxf(progress,_visited_high),occupied_high))+2,points.size()))
		var cosine := clampf(requested_heading.dot(heading),-1.0,1.0)
		requested_heading = heading
		var corner: Dictionary = points[-1]
		while not corners.is_empty() and float(corners[-1].s) >= float(corner.s): corners.pop_back()
		corners.append({"s":corner.s,"cos_half":sqrt((1.0+cosine)*0.5)})
		# Re-anchor the sine at the corner so its rotated lateral offset cannot move the join.
		corner.forward = heading
		corner.center = Vector3(corner.position)-heading.cross(Vector3.UP)*(amplitude*sin(TAU*float(corner.u)/wavelength))
	_visited_high = maxf(_visited_high,progress)
	while float(points[-1].s) < progress+preview:
		var last: Dictionary = points[-1]
		var forward := requested_heading
		var center: Vector3 = last.center + forward*step
		var u := float(last.u)+step
		var position := _position(center,forward,u)
		points.append({"s":float(last.s)+position.distance_to(last.position),"u":u,"position":position,"center":center,"forward":forward})
	var prefix: Array[Dictionary] = []
	var first: Dictionary = points[0]
	while float(first.s) > progress-keep_length*0.5:
		var forward: Vector3 = first.forward
		var center: Vector3 = first.center-forward*step
		var u := float(first.u)-step
		var position := _position(center,forward,u)
		first = {"s":float(first.s)-position.distance_to(first.position),"u":u,"position":position,"center":center,"forward":forward}
		prefix.append(first)
	if not prefix.is_empty():
		prefix.reverse()
		prefix.append_array(points)
		points = prefix
	# Retain enough history for the tail and a full reverse manoeuvre; memory does not grow with play time.
	var remove := maxi(_index(progress-keep_length)-1,0)
	if remove > 32: points = points.slice(remove)
	var end := mini(_index(progress+maxf(preview,keep_length))+2,points.size())
	if points.size()-end > 32: points.resize(end)
	_visited_high = minf(_visited_high,float(points[-1].s))
	while not corners.is_empty() and float(corners[0].s) < float(points[0].s): corners.pop_front()
	while not corners.is_empty() and float(corners[-1].s) > float(points[-1].s): corners.pop_back()
	while turn_markers.size() > 1 and float(turn_markers[1].s) < float(points[0].s): turn_markers.pop_front()

func corner_speed_limit(distance: float, speed: float, acceleration: float, jerk: float, rounding: float) -> float:
	if speed <= 0.0 or acceleration <= 0.0: return 0.0
	var result := speed
	# Reserve the distance spent ramping the braking acceleration, on both sides of a corner.
	var ramp_distance := speed*acceleration/jerk
	for corner: Dictionary in corners:
		var cosine: float = corner.cos_half
		var radius := rounding*maxf(cosine,0.05)/maxf(1.0-cosine,0.001)
		var corner_speed_squared := acceleration*radius
		var remaining := maxf(absf(distance-float(corner.s))-ramp_distance,0.0)
		result = minf(result,sqrt(corner_speed_squared+2.0*acceleration*remaining))
	return result

func anticipate_velocity(distance: float, velocity: Vector3, acceleration: float, jerk: float) -> Vector3:
	var speed := velocity.length()
	if speed <= 0.0 or acceleration <= 0.0: return Vector3.ZERO
	var preview := speed*speed/(2.0*acceleration)+speed*acceleration/jerk
	for corner: Dictionary in corners:
		var gap := float(corner.s)-distance
		if gap < 0.0 or gap > preview: continue
		var weight := smoothstep(0.0,1.0,1.0-gap/preview)*0.5
		return velocity.lerp(Vector3(sample(float(corner.s)+0.0001).tangent)*speed,weight)
	return velocity

func project(position: Vector3, near: float, radius: float, forward_only: bool = false) -> float:
	position.y = 0.0
	var best := near
	var error := INF
	var first := _index(near) if forward_only else maxi(_index(near-radius)-1,0)
	var last := mini(_index(near+radius)+1,points.size()-2)
	for i: int in range(first,last+1):
		var a: Dictionary = points[i]
		var b: Dictionary = points[i+1]
		var edge: Vector3 = b.position-a.position
		var t := clampf((position-Vector3(a.position)).dot(edge)/maxf(edge.length_squared(),0.000001),0.0,1.0)
		if forward_only:
			t = maxf(t,clampf((near-float(a.s))/maxf(float(b.s)-float(a.s),0.000001),0.0,1.0))
		var closest: Vector3 = a.position+edge*t
		var candidate := position.distance_squared_to(closest)
		if candidate < error:
			error = candidate
			best = lerpf(a.s,b.s,t)
	return clampf(best,near-radius,near+radius)
