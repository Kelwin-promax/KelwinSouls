# Vegetação e rochas procedurais (MultiMesh por pedaço de 256 m) + colisões perto do jogador.
class_name Props
extends Node3D

const BUCKET := 256.0

var terrain: Terrain
var _meshes: Dictionary = {}       # tipo -> Array[Mesh] (variantes)
var _buckets: Dictionary = {}      # Vector2i -> {tipo: [instâncias]}
var _bucket_nodes: Dictionary = {} # Vector2i -> Node3D
var _colliders: Dictionary = {}    # Vector2i -> StaticBody3D
var _last_focus := Vector3(INF, 0, INF)
var view_dist := 1500.0
var collider_dist := 120.0
var rng := RandomNumberGenerator.new()

var bark_mat: StandardMaterial3D
var leaf_mat: StandardMaterial3D
var pine_mat: StandardMaterial3D
var rock_mat: StandardMaterial3D
var dead_mat: StandardMaterial3D


static func tex_mat(name: String, uv_scale := 1.0, triplanar := false, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s_albedo.png" % name)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/%s_normal.png" % name)
	m.albedo_color = tint
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * uv_scale
	else:
		m.uv1_scale = Vector3(uv_scale, uv_scale, 1)
	return m


func setup(p_terrain: Terrain, world: Dictionary) -> void:
	terrain = p_terrain
	rng.seed = 99
	if Game.quality == 0:
		view_dist = 900.0
	elif Game.quality == 2:
		view_dist = 2200.0
	bark_mat = tex_mat("bark", 1.0)
	dead_mat = tex_mat("bark", 1.0, false, Color(0.75, 0.7, 0.68))
	leaf_mat = tex_mat("leaves", 1.0, true)
	leaf_mat.uv1_scale = Vector3.ONE * 0.4
	pine_mat = tex_mat("leaves", 1.0, true, Color(0.55, 0.7, 0.6))
	pine_mat.uv1_scale = Vector3.ONE * 0.5
	rock_mat = tex_mat("rock", 0.18, true)
	_meshes["tree"] = [_tree_mesh(0), _tree_mesh(1), _tree_mesh(2)]
	_meshes["pine"] = [_pine_mesh(0), _pine_mesh(1)]
	_meshes["dead_tree"] = [_dead_tree_mesh(0, false), _dead_tree_mesh(1, false), _dead_tree_mesh(2, false)]
	_meshes["swamp_tree"] = [_dead_tree_mesh(3, true), _dead_tree_mesh(4, true)]
	_meshes["rock"] = [_rock_mesh(0), _rock_mesh(1), _rock_mesh(2), _rock_mesh(3)]
	for kind in world.props:
		for p in world.props[kind]:
			var b := Vector2i(int(floor(p[0] / BUCKET)), int(floor(p[2] / BUCKET)))
			if not _buckets.has(b):
				_buckets[b] = {}
			if not _buckets[b].has(kind):
				_buckets[b][kind] = []
			_buckets[b][kind].append(p)


# ------------------------------------------------------------ geometria procedural
func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides := 7, v0 := 0.0) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(dir).normalized()
	var L := a.distance_to(b)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var n0 := side * cos(a0) + up * sin(a0)
		var n1 := side * cos(a1) + up * sin(a1)
		var u0 := float(i) / sides
		var u1 := float(i + 1) / sides
		var p00 := a + n0 * ra
		var p01 := a + n1 * ra
		var p10 := b + n0 * rb
		var p11 := b + n1 * rb
		for v in [[p00, n0, Vector2(u0, v0)], [p10, n0, Vector2(u0, v0 + L * 0.3)], [p11, n1, Vector2(u1, v0 + L * 0.3)],
				[p00, n0, Vector2(u0, v0)], [p11, n1, Vector2(u1, v0 + L * 0.3)], [p01, n1, Vector2(u1, v0)]]:
			st.set_normal(v[1])
			st.set_uv(v[2])
			st.add_vertex(v[0])


func _blob(st: SurfaceTool, c: Vector3, r: Vector3, seed_v: int, detail := 2) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10 + detail * 2
	sm.rings = 6 + detail
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 1.3
	for i in idx.size():
		var k := idx[i]
		var v := verts[k]
		var d := 1.0 + noise.get_noise_3dv(v * 1.5) * 0.35
		st.set_normal(norms[k])
		st.set_uv(uvs[k])
		st.add_vertex(c + v * r * d)


func _tree_mesh(variant: int) -> ArrayMesh:
	rng.seed = 1000 + variant
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := rng.randf_range(7.0, 10.0)
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	_tube(bark, Vector3(0, -0.5, 0), Vector3(0, h * 0.5, 0) + lean * 0.5, 0.45, 0.32)
	_tube(bark, Vector3(0, h * 0.5, 0) + lean * 0.5, Vector3(0, h, 0) + lean, 0.32, 0.15)
	for i in 4:
		var a := rng.randf() * TAU
		var y := rng.randf_range(h * 0.45, h * 0.8)
		var s := Vector3(0, y, 0) + lean * (y / h)
		var e := s + Vector3(cos(a) * 2.5, rng.randf_range(1.0, 2.2), sin(a) * 2.5)
		_tube(bark, s, e, 0.16, 0.06, 5)
		_blob(leaves, e, Vector3(2.2, 1.6, 2.2) * rng.randf_range(0.8, 1.2), variant * 10 + i, 1)
	_blob(leaves, Vector3(0, h, 0) + lean, Vector3(3.2, 2.4, 3.2), variant * 10 + 9, 2)
	var m := bark.commit()
	m.surface_set_material(0, bark_mat)
	leaves.generate_normals()
	var m2 := leaves.commit(m)
	m2.surface_set_material(1, leaf_mat)
	return m2


func _pine_mesh(variant: int) -> ArrayMesh:
	rng.seed = 2000 + variant
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := rng.randf_range(11.0, 15.0)
	_tube(bark, Vector3(0, -0.5, 0), Vector3(0, h, 0), 0.4, 0.08)
	var m := bark.commit()
	m.surface_set_material(0, bark_mat)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers := 5
	for t in tiers:
		var y0 := h * (0.25 + 0.15 * t)
		var r := 3.4 * (1.0 - float(t) / tiers) + 0.6
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = r
		cone.height = h * 0.3
		cone.radial_segments = 9
		cone.rings = 1
		var arr := cone.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		for k: int in arr[Mesh.ARRAY_INDEX]:
			var v: Vector3 = verts[k]
			v.x += sin(v.y * 3.0 + t) * 0.15
			leaves.set_normal(norms[k])
			leaves.set_uv(uvs[k])
			leaves.add_vertex(v + Vector3(0, y0 + h * 0.15, 0))
	var m2 := leaves.commit(m)
	m2.surface_set_material(1, pine_mat)
	return m2


func _dead_tree_mesh(variant: int, swamp: bool) -> ArrayMesh:
	rng.seed = 3000 + variant
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := rng.randf_range(5.0, 9.0) * (1.3 if swamp else 1.0)
	var segs: Array = [[Vector3(0, -0.5, 0), Vector3(rng.randf_range(-0.6, 0.6), h * 0.55, rng.randf_range(-0.6, 0.6)), 0.5, 0.3, 0]]
	var i := 0
	while i < segs.size() and segs.size() < 26:
		var s: Array = segs[i]
		_tube(st, s[0], s[1], s[2], s[3], 6)
		if s[4] < 3:
			var dir: Vector3 = (s[1] - s[0]).normalized()
			var n := 2 if s[4] > 0 else 3
			for k in n:
				var nd := (dir + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.1, 0.5), rng.randf_range(-0.9, 0.9))).normalized()
				if swamp and s[4] >= 1:
					nd.y -= 0.6
					nd = nd.normalized()
				var L: float = s[0].distance_to(s[1]) * rng.randf_range(0.5, 0.8)
				segs.append([s[1], s[1] + nd * L, s[3], s[3] * 0.55, s[4] + 1])
		i += 1
	var m := st.commit()
	m.surface_set_material(0, dead_mat)
	return m


func _rock_mesh(variant: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blob(st, Vector3(0, 0.6, 0), Vector3(2.2, 1.5, 1.8) * (1.0 + variant * 0.25), 500 + variant, 3)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, rock_mat)
	return m


# ------------------------------------------------------------ streaming
func update(focus: Vector3) -> void:
	if Vector2(focus.x - _last_focus.x, focus.z - _last_focus.z).length() < 30.0:
		return
	_last_focus = focus
	var r := int(ceil(view_dist / BUCKET)) + 1
	var fb := Vector2i(int(floor(focus.x / BUCKET)), int(floor(focus.z / BUCKET)))
	var want := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var b := fb + Vector2i(dx, dz)
			if not _buckets.has(b):
				continue
			var c := Vector2((b.x + 0.5) * BUCKET, (b.y + 0.5) * BUCKET)
			var d := c.distance_to(Vector2(focus.x, focus.z)) - BUCKET * 0.7
			if d < view_dist:
				want[b] = true
				if d < collider_dist and not _colliders.has(b):
					_make_colliders(b)
	for b in _bucket_nodes.keys():
		if not want.has(b):
			_bucket_nodes[b].queue_free()
			_bucket_nodes.erase(b)
	for b in want:
		if not _bucket_nodes.has(b):
			_build_bucket(b)
	for b in _colliders.keys():
		var c := Vector2((b.x + 0.5) * BUCKET, (b.y + 0.5) * BUCKET)
		if c.distance_to(Vector2(focus.x, focus.z)) > collider_dist * 2.5 + BUCKET:
			_colliders[b].queue_free()
			_colliders.erase(b)


func _build_bucket(b: Vector2i) -> void:
	var node := Node3D.new()
	add_child(node)
	_bucket_nodes[b] = node
	for kind in _buckets[b]:
		var list: Array = _buckets[b][kind]
		var variants: Array = _meshes[kind]
		for vi in variants.size():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = variants[vi]
			var sel := []
			for k in list.size():
				if k % variants.size() == vi:
					sel.append(list[k])
			if sel.is_empty():
				continue
			mm.instance_count = sel.size()
			for k in sel.size():
				var p: Array = sel[k]
				var y: float = terrain.height_at(p[0], p[2])
				var s: float = p[4] * (1.6 if kind == "rock" else 1.0)
				var basis := Basis(Vector3.UP, p[3]).scaled(Vector3.ONE * s)
				if kind == "rock":
					var nrm := terrain.normal_at(p[0], p[2])
					basis = Basis(Quaternion(Vector3.UP, nrm)) * basis
					y -= 0.6 * s
				mm.set_instance_transform(k, Transform3D(basis, Vector3(p[0], y, p[2])))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = view_dist * (0.6 if kind == "rock" else 1.0)
			mmi.visibility_range_end_margin = 50.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Game.quality > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mmi)


func _make_colliders(b: Vector2i) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	_colliders[b] = body
	for kind in _buckets[b]:
		for p in _buckets[b][kind]:
			var cs := CollisionShape3D.new()
			var y: float = terrain.height_at(p[0], p[2])
			if kind == "rock":
				var sh := SphereShape3D.new()
				sh.radius = 1.6 * p[4] * 1.6
				cs.shape = sh
				cs.position = Vector3(p[0], y + 0.2, p[2])
			else:
				var sh := CylinderShape3D.new()
				sh.radius = 0.45 * p[4]
				sh.height = 6.0
				cs.shape = sh
				cs.position = Vector3(p[0], y + 3.0, p[2])
			body.add_child(cs)
