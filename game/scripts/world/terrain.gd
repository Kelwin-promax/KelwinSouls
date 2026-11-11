# Terreno com streaming: pedaços de 256 m, 4 níveis de detalhe, colisão só perto do jogador.
class_name Terrain
extends Node3D

const CHUNK_CELLS := 64
const LAYERS := ["grass", "dirt", "rock", "snow", "ash", "mud", "bone", "crimson"]

var n := 2049
var cell := 4.0
var size := 8192.0
var half := 4096.0
var water := 22.0
var heights := PackedFloat32Array()
var chunk_m := 256.0
var per_side := 32
var lod_res := [64, 32, 16, 8]
var lod_dist := [420.0, 1000.0, 1900.0]
var view_dist := 3400.0
var collider_dist := 200.0

var mat: ShaderMaterial
var _lod_meshes: Array[ArrayMesh] = []
var _chunks: Dictionary = {}      # Vector2i -> MeshInstance3D
var _chunk_lod: Dictionary = {}
var _colliders: Dictionary = {}   # Vector2i -> StaticBody3D
var _minmax: Dictionary = {}
var _last_focus := Vector3(INF, 0, INF)
var height_texture: ImageTexture


func setup(world: Dictionary) -> void:
	n = int(world.n)
	cell = float(world.cell)
	size = float(world.size)
	half = size * 0.5
	water = float(world.water)
	per_side = int(size / chunk_m)
	var bytes := FileAccess.get_file_as_bytes("res://assets/world/height.bin")
	heights = bytes.to_float32_array()
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, bytes)
	height_texture = ImageTexture.create_from_image(img)
	_compute_minmax()
	for r in lod_res:
		_lod_meshes.append(_make_grid(r))
	_make_material()
	if Game.quality == 0:
		view_dist = 2200.0
		lod_dist = [300.0, 700.0, 1400.0]
	elif Game.quality == 2:
		view_dist = 4600.0
		lod_dist = [600.0, 1400.0, 2600.0]


func _make_material() -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("heightmap", height_texture)
	mat.set_shader_parameter("splat0", load("res://assets/world/splat0.png"))
	mat.set_shader_parameter("splat1", load("res://assets/world/splat1.png"))
	mat.set_shader_parameter("cell", cell)
	mat.set_shader_parameter("half_size", half)
	mat.set_shader_parameter("n", n)
	mat.set_shader_parameter("albedo_arr", _texture_array("albedo"))
	mat.set_shader_parameter("normal_arr", _texture_array("normal"))


static func load_image(path: String) -> Image:
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _texture_array(kind: String) -> Texture2DArray:
	var imgs: Array[Image] = []
	for l in LAYERS:
		var img := load_image("res://assets/textures/%s_%s.png" % [l, kind])
		if img.get_width() != 1024:
			img.resize(1024, 1024)
		img.generate_mipmaps()
		imgs.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


func _compute_minmax() -> void:
	for cz in per_side:
		for cx in per_side:
			var lo := INF
			var hi := -INF
			for i in range(0, CHUNK_CELLS + 1, 4):
				var row := (cz * CHUNK_CELLS + i) * n + cx * CHUNK_CELLS
				for j in range(0, CHUNK_CELLS + 1, 4):
					var h := heights[row + j]
					lo = min(lo, h)
					hi = max(hi, h)
			_minmax[Vector2i(cx, cz)] = Vector2(lo, hi)


func _make_grid(res: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var step := chunk_m / res
	for z in res + 1:
		for x in res + 1:
			verts.append(Vector3(x * step, 0, z * step))
			cols.append(Color(0, 0, 0))
	var w := res + 1
	for z in res:
		for x in res:
			var a := z * w + x
			idx.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
	# saias nas 4 bordas para esconder fendas entre níveis de detalhe
	var edges := [
		[func(i): return i, func(i): return i + 1, true],                          # norte (z=0)
		[func(i): return res * w + i, func(i): return res * w + i + 1, false],     # sul
		[func(i): return i * w, func(i): return (i + 1) * w, false],                # oeste
		[func(i): return i * w + res, func(i): return (i + 1) * w + res, true],    # leste
	]
	for e in edges:
		for i in res:
			var a: int = e[0].call(i)
			var b: int = e[1].call(i)
			var sa := verts.size()
			verts.append(verts[a]); cols.append(Color(1, 0, 0))
			verts.append(verts[b]); cols.append(Color(1, 0, 0))
			if e[2]:
				idx.append_array([a, sa, b, b, sa, sa + 1])
			else:
				idx.append_array([a, b, sa, b, sa + 1, sa])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# ------------------------------------------------------------ consultas
func height_at(x: float, z: float) -> float:
	var gx: float = clamp((x + half) / cell, 0.0, n - 1.001)
	var gz: float = clamp((z + half) / cell, 0.0, n - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i0 := iz * n + ix
	var a := heights[i0]
	var b := heights[i0 + 1]
	var c := heights[i0 + n]
	var d := heights[i0 + n + 1]
	return lerp(lerp(a, b, fx), lerp(c, d, fx), fz)


func normal_at(x: float, z: float) -> Vector3:
	var hl := height_at(x - cell, z)
	var hr := height_at(x + cell, z)
	var hd := height_at(x, z - cell)
	var hu := height_at(x, z + cell)
	return Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()


func ground_y(x: float, z: float) -> float:
	return max(height_at(x, z), water - 1.2)


func region_at(pos: Vector3) -> String:
	var best := ""
	var best_d := INF
	for k in Game.world.regions:
		var r: Dictionary = Game.world.regions[k]
		var d := Vector2(pos.x - r.center[0], pos.z - r.center[1]).length() / float(r.radius)
		if d < best_d:
			best_d = d
			best = k
	return best if best_d < 1.15 else ""


# ------------------------------------------------------------ streaming
func update(focus: Vector3, force := false) -> void:
	if not force and Vector2(focus.x - _last_focus.x, focus.z - _last_focus.z).length() < 24.0:
		return
	_last_focus = focus
	var want := {}
	var r := int(ceil(view_dist / chunk_m)) + 1
	var fc := Vector2i(int(floor((focus.x + half) / chunk_m)), int(floor((focus.z + half) / chunk_m)))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := fc + Vector2i(dx, dz)
			if c.x < 0 or c.y < 0 or c.x >= per_side or c.y >= per_side:
				continue
			var cx: float = c.x * chunk_m - half + chunk_m * 0.5
			var cz: float = c.y * chunk_m - half + chunk_m * 0.5
			var d := Vector2(focus.x - cx, focus.z - cz).length() - chunk_m * 0.5
			if d > view_dist:
				continue
			var lod := 3
			for i in lod_dist.size():
				if d < lod_dist[i]:
					lod = i
					break
			want[c] = lod
			if d < collider_dist and not _colliders.has(c):
				_make_collider(c)
	for c in _chunks.keys():
		if not want.has(c):
			_chunks[c].queue_free()
			_chunks.erase(c)
			_chunk_lod.erase(c)
	for c in want:
		var lod: int = want[c]
		if not _chunks.has(c):
			var mi := MeshInstance3D.new()
			mi.material_override = mat
			mi.position = Vector3(c.x * chunk_m - half, 0, c.y * chunk_m - half)
			var mm: Vector2 = _minmax[c]
			mi.custom_aabb = AABB(Vector3(0, mm.x - 40, 0), Vector3(chunk_m, mm.y - mm.x + 80, chunk_m))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_chunks[c] = mi
			_chunk_lod[c] = -1
		if _chunk_lod[c] != lod:
			_chunks[c].mesh = _lod_meshes[lod]
			_chunks[c].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_chunk_lod[c] = lod
	for c in _colliders.keys():
		var cx: float = c.x * chunk_m - half + chunk_m * 0.5
		var cz: float = c.y * chunk_m - half + chunk_m * 0.5
		if Vector2(focus.x - cx, focus.z - cz).length() - chunk_m * 0.7 > collider_dist * 1.6:
			_colliders[c].queue_free()
			_colliders.erase(c)


func _make_collider(c: Vector2i) -> void:
	var faces := PackedVector3Array()
	faces.resize(CHUNK_CELLS * CHUNK_CELLS * 6)
	var k := 0
	var x0 := c.x * chunk_m - half
	var z0 := c.y * chunk_m - half
	for i in CHUNK_CELLS:
		var gi := c.y * CHUNK_CELLS + i
		for j in CHUNK_CELLS:
			var gj := c.x * CHUNK_CELLS + j
			var p := gi * n + gj
			var xa := x0 + j * cell
			var za := z0 + i * cell
			var v00 := Vector3(xa, heights[p], za)
			var v10 := Vector3(xa + cell, heights[p + 1], za)
			var v01 := Vector3(xa, heights[p + n], za + cell)
			var v11 := Vector3(xa + cell, heights[p + n + 1], za + cell)
			faces[k] = v00; faces[k + 1] = v10; faces[k + 2] = v01
			faces[k + 3] = v10; faces[k + 4] = v11; faces[k + 5] = v01
			k += 6
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	_colliders[c] = body


func has_collision_at(pos: Vector3) -> bool:
	var c := Vector2i(int(floor((pos.x + half) / chunk_m)), int(floor((pos.z + half) / chunk_m)))
	return _colliders.has(c)
