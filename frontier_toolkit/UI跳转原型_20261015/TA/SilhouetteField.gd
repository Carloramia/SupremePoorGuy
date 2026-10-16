extends RefCounted
## Exact Euclidean distance to a whole filled silhouette. No per-frame processing.
static var cache: Dictionary = {}

static func build(texture: Texture2D, padding: int, max_dimension: int = 256) -> Dictionary:
	var key := "%s:%d:%d" % [texture.get_instance_id(), padding, max_dimension]
	if cache.has(key):
		return cache[key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {}
	if image.is_compressed():
		image.decompress()
	# Bounded mask work; original art remains at its imported resolution.
	if maxi(image.get_width(), image.get_height()) > max_dimension:
		var ratio := float(max_dimension) / maxi(image.get_width(), image.get_height())
		image.resize(maxi(1, roundi(image.get_width() * ratio)), maxi(1, roundi(image.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	var source_size := Vector2i(image.get_width(), image.get_height())
	var w := source_size.x + 2 * padding
	var h := source_size.y + 2 * padding
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in source_size.y:
		for x in source_size.x:
			solid[(y + padding) * w + x + padding] = int(image.get_pixel(x, y).a >= 0.1)
	# Flood fill exterior transparency; enclosed holes belong to the backing.
	var exterior := PackedByteArray()
	exterior.resize(w * h)
	var queue := PackedInt32Array([0])
	exterior[0] = 1
	var cursor := 0
	while cursor < queue.size():
		var i := queue[cursor]
		cursor += 1
		for offset in [-1, 1, -w, w]:
			var j: int = i + offset
			if j < 0 or j >= w * h or (offset == -1 and i % w == 0) or (offset == 1 and i % w == w - 1):
				continue
			if exterior[j] == 0 and solid[j] == 0:
				exterior[j] = 1
				queue.append(j)
	var data := PackedFloat32Array()
	data.resize(w * h)
	var line := PackedFloat32Array()
	line.resize(w)
	for y in h:
		for x in w:
			line[x] = 1.0e12 if exterior[y * w + x] else 0.0
		var row := _edt(line)
		for x in w:
			data[y * w + x] = row[x]
	line.resize(h)
	for x in w:
		for y in h:
			line[y] = data[y * w + x]
		var column := _edt(line)
		for y in h:
			data[y * w + x] = maxf(0.0, sqrt(column[y]) - 0.5)
	var field := Image.create_from_data(w, h, false, Image.FORMAT_RF, data.to_byte_array())
	var result := {"texture": ImageTexture.create_from_image(field), "size": Vector2(w, h), "subject_size": Vector2(source_size), "padding": padding}
	# Limit editor cache retention when trying many assets/sizes.
	if cache.size() >= 32:
		cache.clear()
	cache[key] = result
	return result

static func _edt(f: PackedFloat32Array) -> PackedFloat32Array:
	var n := f.size()
	var v := PackedInt32Array()
	var z := PackedFloat32Array()
	var d := PackedFloat32Array()
	v.resize(n)
	z.resize(n + 1)
	d.resize(n)
	var k := 0
	z[0] = -1.0e20
	z[1] = 1.0e20
	for q in range(1, n):
		var s := ((f[q] + float(q * q)) - (f[v[k]] + float(v[k] * v[k]))) / (2.0 * (q - v[k]))
		while s <= z[k] and k > 0:
			k -= 1
			s = ((f[q] + float(q * q)) - (f[v[k]] + float(v[k] * v[k]))) / (2.0 * (q - v[k]))
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = 1.0e20
	k = 0
	for q in n:
		while z[k + 1] < q:
			k += 1
		d[q] = float((q - v[k]) * (q - v[k])) + f[v[k]]
	return d
