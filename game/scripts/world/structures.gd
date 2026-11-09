# Construções procedurais: ruínas, cemitérios, santuários, obeliscos, cidadela, pagode e a Árvore de Brasa.
class_name Structures
extends Node3D

var terrain: Terrain
var rng := RandomNumberGenerator.new()
var stone: StandardMaterial3D
var ivory: StandardMaterial3D
var obsidian: StandardMaterial3D
var wood: StandardMaterial3D
var roof: StandardMaterial3D
var ice: StandardMaterial3D
var rune_glow: StandardMaterial3D
var red_lacquer: StandardMaterial3D


func setup(p_terrain: Terrain, world: Dictionary) -> void:
	terrain = p_terrain
	stone = Props.tex_mat("stone_wall", 0.35, true)
	ivory = Props.tex_mat("ivory_stone", 0.3, true)
	obsidian = Props.tex_mat("obsidian", 0.25, true)
	obsidian.roughness = 0.25
	obsidian.metallic = 0.3
	wood = Props.tex_mat("wood", 0.5, true)
	roof = Props.tex_mat("roof", 0.5, true)
	ice = Props.tex_mat("ice", 0.3, true)
	ice.roughness = 0.1
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.albedo_color = Color(0.8, 0.9, 1.0, 0.85)
	red_lacquer = StandardMaterial3D.new()
	red_lacquer.albedo_color = Color(0.55, 0.06, 0.04)
	red_lacquer.roughness = 0.35
	rune_glow = StandardMaterial3D.new()
	rune_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_glow.albedo_color = Color(1.0, 0.45, 0.15)
	for r in world.ruins:
		var pos := Vector3(r.pos[0], 0, r.pos[2])
		pos.y = terrain.height_at(pos.x, pos.z)
		rng.seed = int(r.seed)
		var n := Node3D.new()
		add_child(n)
		n.position = pos
		n.rotation.y = r.rot
		match r.kind:
			"ruin": _ruin(n)
			"graveyard": _graveyard(n)
			"shrine": _shrine(n)
			"obelisks": _obelisks(n)
			"ice_spikes": _ice_spikes(n)
	_citadel()
	_pagoda(Vector3(2650, 0, 2950))
	_chapel(Vector3(350, 0, 2470))
	_ember_tree(Vector3(world.ember_tree[0], world.ember_tree[1], world.ember_tree[2]))
	_forge(Vector3(2100, 0, 650))


# ------------------------------------------------------------ peças básicas
func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		mi.add_child(body)
	mi.visibility_range_end = 1400.0
	return mi


func cyl(parent: Node3D, pos: Vector3, r_bottom: float, r_top: float, h: float, mat: Material, sides := 12, collide := true, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.bottom_radius = r_bottom
	c.top_radius = r_top
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos + Vector3(0, h * 0.5, 0)
	mi.rotation = rot
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = max(r_bottom, r_top)
		sh.height = h
		cs.shape = sh
		body.add_child(cs)
		mi.add_child(body)
	mi.visibility_range_end = 1600.0
	return mi


func prism_roof(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var p := PrismMesh.new()
	p.size = size
	mi.mesh = p
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _ground(n: Node3D, local: Vector3) -> float:
	var g := n.to_global(local)
	return terrain.height_at(g.x, g.z) - n.global_position.y


# ------------------------------------------------------------ tipos de ruína
func _ruin(n: Node3D) -> void:
	# paredes quebradas, colunas e um arco
	for i in rng.randi_range(2, 4):
		var x := rng.randf_range(-12, 12)
		var z := rng.randf_range(-12, 12)
		var h := rng.randf_range(2.5, 7.0)
		var w := rng.randf_range(5.0, 11.0)
		var g := _ground(n, Vector3(x, 0, z))
		box(n, Vector3(x, g + h * 0.5 - 0.5, z), Vector3(w, h, 1.2), stone, Vector3(0, rng.randf_range(-0.3, 0.3) + (PI * 0.5 if i % 2 else 0.0), rng.randf_range(-0.05, 0.05)))
	for i in rng.randi_range(3, 7):
		var a := TAU * i / 7.0
		var p := Vector3(cos(a) * 9.0, 0, sin(a) * 9.0)
		var h := rng.randf_range(2.0, 9.0)
		var g := _ground(n, p)
		cyl(n, p + Vector3(0, g - 0.3, 0), 0.8, 0.7, h, stone, 10)
		if rng.randf() < 0.3:
			cyl(n, p + Vector3(2.5, g, 0.5), 0.75, 0.75, 4.0, stone, 10, false, Vector3(0, 0, PI * 0.5))
	if rng.randf() < 0.5:
		var g := _ground(n, Vector3.ZERO)
		box(n, Vector3(-3, g + 3.5, 0), Vector3(1.4, 7, 1.4), stone)
		box(n, Vector3(3, g + 3.5, 0), Vector3(1.4, 7, 1.4), stone)
		box(n, Vector3(0, g + 7.5, 0), Vector3(8, 1.2, 1.6), stone)


func _graveyard(n: Node3D) -> void:
	for i in rng.randi_range(14, 30):
		var p := Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-16, 16))
		var g := _ground(n, p)
		if rng.randf() < 0.7:
			box(n, p + Vector3(0, g + 0.6, 0), Vector3(0.9, 1.6, 0.25), stone, Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.2)))
		else:
			box(n, p + Vector3(0, g + 1.2, 0), Vector3(0.25, 2.4, 0.25), stone, Vector3(0, 0, rng.randf_range(-0.2, 0.2)))
			box(n, p + Vector3(0, g + 1.8, 0), Vector3(1.2, 0.25, 0.25), stone, Vector3(0, 0, rng.randf_range(-0.2, 0.2)), false)
	if rng.randf() < 0.6:
		var g := _ground(n, Vector3(0, 0, -20))
		box(n, Vector3(0, g + 3, -20), Vector3(8, 6, 6), stone)
		prism_roof(n, Vector3(0, g + 7.2, -20), Vector3(9, 2.5, 7), stone)


func _shrine(n: Node3D) -> void:
	var g := _ground(n, Vector3.ZERO)
	# torii
	cyl(n, Vector3(-3, g - 0.2, 0), 0.35, 0.3, 7.0, red_lacquer, 10)
	cyl(n, Vector3(3, g - 0.2, 0), 0.35, 0.3, 7.0, red_lacquer, 10)
	box(n, Vector3(0, g + 6.4, 0), Vector3(9, 0.6, 0.8), red_lacquer, Vector3.ZERO, false)
	box(n, Vector3(0, g + 5.2, 0), Vector3(7, 0.4, 0.5), red_lacquer, Vector3.ZERO, false)
	# pequeno santuário
	var g2 := _ground(n, Vector3(0, 0, -10))
	box(n, Vector3(0, g2 + 0.5, -10), Vector3(6, 1, 5), stone)
	box(n, Vector3(0, g2 + 2.5, -10), Vector3(4.5, 3, 3.5), wood)
	prism_roof(n, Vector3(0, g2 + 4.8, -10), Vector3(7, 1.8, 5.5), roof)
	for i in 4:
		var p := Vector3(-2 + i * 1.3, 0, -6)
		cyl(n, p + Vector3(0, _ground(n, p), 0), 0.25, 0.2, 1.2, stone, 8)


func _obelisks(n: Node3D) -> void:
	for i in rng.randi_range(3, 6):
		var a := TAU * i / 6.0 + rng.randf() * 0.4
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(5, 12)
		var h := rng.randf_range(6, 16)
		var g := _ground(n, p)
		var o := box(n, p + Vector3(0, g + h * 0.5 - 1.0, 0), Vector3(1.6, h, 1.6), obsidian, Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * PI, rng.randf_range(-0.12, 0.12)))
		var rune := box(o, Vector3(0, 0, 0.81), Vector3(0.3, h * 0.6, 0.02), rune_glow, Vector3.ZERO, false)
		rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if rng.randf() < 0.5:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.4, 0.1)
		l.light_energy = 2.0
		l.omni_range = 18.0
		l.position = Vector3(0, _ground(n, Vector3.ZERO) + 2.0, 0)
		l.visibility_range_end = 250.0
		n.add_child(l)


func _ice_spikes(n: Node3D) -> void:
	for i in rng.randi_range(6, 14):
		var p := Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
		var h := rng.randf_range(3, 11)
		var mi := cyl(n, p + Vector3(0, _ground(n, p) - 0.5, 0), rng.randf_range(0.6, 1.4), 0.02, h, ice, 6)
		mi.rotation = Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))


# ------------------------------------------------------------ marcos
func _citadel() -> void:
	# muralha em anel na borda do platô + portão sul + torre de menagem
	var c := Vector3(0, 0, -1100)
	var root := Node3D.new()
	add_child(root)
	root.position = c
	var R := 560.0
	var segments := 56
	for i in segments:
		var a := TAU * i / segments
		var p := Vector3(sin(a) * R, 0, cos(a) * R)
		if absf(wrapf(a, -PI, PI)) < 0.06:
			continue  # vão do portão (sul, +Z)
		var g := terrain.height_at(c.x + p.x, c.z + p.z)
		var seg_len := TAU * R / segments + 1.0
		var wall := box(root, p + Vector3(0, g + 9.0, 0), Vector3(seg_len, 22.0, 6.0), ivory, Vector3(0, a + PI * 0.5, 0))
		wall.visibility_range_end = 5000.0
		if i % 4 == 0:
			var t := cyl(root, p + Vector3(0, g - 2.0, 0), 7.0, 6.0, 36.0, ivory, 16)
			t.visibility_range_end = 5000.0
			var cone := cyl(root, p + Vector3(0, g + 34.0, 0), 7.5, 0.3, 14.0, roof, 16, false)
			cone.visibility_range_end = 5000.0
	# portão
	var gp := Vector3(0, 0, R)
	var gg := terrain.height_at(c.x, c.z + R)
	for s in [-1, 1]:
		var tw := cyl(root, gp + Vector3(s * 14, gg - 2, 0), 8, 7, 44, ivory, 16)
		tw.visibility_range_end = 5000.0
	box(root, gp + Vector3(0, gg + 30, 0), Vector3(30, 8, 8), ivory)
	# torre de menagem perto da Árvore
	var kp := Vector3(0, 0, -150)
	var kg := terrain.height_at(c.x + kp.x, c.z + kp.z)
	var keep := box(root, kp + Vector3(0, kg + 30, 0), Vector3(60, 60, 50), ivory)
	keep.visibility_range_end = 6000.0
	for s in [Vector3(-30, 0, -25), Vector3(30, 0, -25), Vector3(-30, 0, 25), Vector3(30, 0, 25)]:
		var t := cyl(root, kp + s + Vector3(0, kg, 0), 9, 8, 90, ivory, 16)
		t.visibility_range_end = 6000.0
		var cone := cyl(root, kp + s + Vector3(0, kg + 88, 0), 9.5, 0.4, 24, roof, 16, false)
		cone.visibility_range_end = 6000.0
	# rua principal com colunas
	for i in 16:
		var z := R - 40 - i * 30.0
		for s in [-1, 1]:
			var p := Vector3(s * 16, 0, z)
			cyl(root, p + Vector3(0, terrain.height_at(c.x + p.x, c.z + p.z) - 0.5, 0), 1.3, 1.1, 14.0, ivory, 12)


func _pagoda(p: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	p.y = terrain.height_at(p.x, p.z)
	root.position = p
	var w := 26.0
	var y := 0.0
	box(root, Vector3(0, -1, 0), Vector3(w + 10, 4, w + 10), stone)
	for tier in 5:
		var h := 8.0 - tier * 0.6
		box(root, Vector3(0, y + 1 + h * 0.5, 0), Vector3(w, h, w), wood)
		for cx in [-1, 1]:
			for cz in [-1, 1]:
				cyl(root, Vector3(cx * w * 0.5, y + 1, cz * w * 0.5), 0.6, 0.6, h, red_lacquer, 8, false)
		var r := box(root, Vector3(0, y + 1 + h + 0.6, 0), Vector3(w + 8, 1.2, w + 8), roof, Vector3.ZERO, false)
		r.visibility_range_end = 4000.0
		y += h + 1.2
		w *= 0.8
	cyl(root, Vector3(0, y + 1, 0), 0.5, 0.05, 14, red_lacquer, 8, false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.5, 0.3)
	lamp.light_energy = 3.0
	lamp.omni_range = 40.0
	lamp.position = Vector3(0, 6, 22)
	root.add_child(lamp)


func _chapel(p: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	p.y = terrain.height_at(p.x, p.z)
	root.position = p
	box(root, Vector3(0, 4, -12), Vector3(14, 9, 1.2), stone)
	box(root, Vector3(-7, 3, -4), Vector3(1.2, 7, 16), stone)
	box(root, Vector3(7, 2, -6), Vector3(1.2, 5, 12), stone)
	for i in 3:
		cyl(root, Vector3(-4 + i * 4, -0.3, 4), 0.7, 0.6, 5.0 + i * 1.5, stone, 10)
	prism_roof(root, Vector3(-2, 9.5, -9), Vector3(10, 3, 6), stone)


func _forge(p: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	p.y = terrain.height_at(p.x, p.z)
	root.position = p + Vector3(30, 0, 30)
	box(root, Vector3(0, 1.5, 0), Vector3(5, 3, 2.5), obsidian)
	box(root, Vector3(0, 3.4, 0), Vector3(7, 0.8, 3), obsidian)
	var f := FX.flame(Color(1.0, 0.5, 0.15), 50, 0.8, 3.0)
	f.position = Vector3(0, 4, 0)
	root.add_child(f)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.45, 0.15)
	l.light_energy = 4.0
	l.omni_range = 30.0
	l.position = Vector3(0, 6, 0)
	root.add_child(l)


func _ember_tree(p: Vector3) -> void:
	# A Árvore de Brasa: tronco colossal + copa dourada brilhante (visível de todo o mapa)
	var root := Node3D.new()
	add_child(root)
	root.position = p
	var bark := Props.tex_mat("bark", 0.08, true, Color(0.9, 0.75, 0.55))
	bark.emission_enabled = true
	bark.emission = Color(0.6, 0.3, 0.05)
	bark.emission_energy_multiplier = 0.25
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var props := Props.new()
	rng.seed = 777
	# tronco em espiral (várias raízes entrelaçadas)
	for k in 5:
		var a0 := TAU * k / 5.0
		var prev := Vector3(cos(a0) * 26.0, -5, sin(a0) * 26.0)
		for s in 12:
			var t := float(s + 1) / 12.0
			var a := a0 + t * 2.2
			var r := lerpf(26.0, 6.0, pow(t, 0.7))
			var nxt := Vector3(cos(a) * r, t * 230.0, sin(a) * r)
			props._tube(st, prev, nxt, lerpf(11.0, 4.0, t - 1.0 / 12.0), lerpf(11.0, 4.0, t), 9)
			prev = nxt
	# galhos
	var tips: Array[Vector3] = []
	for i in 18:
		var a := rng.randf() * TAU
		var y := rng.randf_range(150.0, 230.0)
		var s := Vector3(cos(a) * 6.0, y, sin(a) * 6.0)
		var e := s + Vector3(cos(a) * rng.randf_range(60, 120), rng.randf_range(20, 70), sin(a) * rng.randf_range(60, 120))
		props._tube(st, s, e, 4.0, 1.2, 7)
		tips.append(e)
	props.free()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = bark
	mi.extra_cull_margin = 400.0
	root.add_child(mi)
	# copa: folhas douradas (MultiMesh de quadrados) sem neblina para brilhar ao longe
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	leaf_mat.albedo_color = Color(1.0, 0.72, 0.28)
	leaf_mat.disable_fog = true
	leaf_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	leaf_mat.albedo_texture = _soft_dot()
	var q := QuadMesh.new()
	q.size = Vector2(14, 14)
	q.material = leaf_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	var count := 2600
	mm.instance_count = count
	for i in count:
		var tip := tips[i % tips.size()]
		var off := Vector3(rng.randfn(0, 1), rng.randfn(0, 0.6), rng.randfn(0, 1)) * 38.0
		if i % 5 == 0:
			off = Vector3(rng.randfn(0, 1) * 70.0, rng.randf_range(200, 300) - tip.y, rng.randfn(0, 1) * 70.0)
		var sc := rng.randf_range(0.6, 1.8)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * sc), tip + off))
		mm.set_instance_color(i, Color(1, 1, 1, rng.randf_range(0.25, 0.7)))
	leaf_mat.vertex_color_use_as_albedo = true
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 400.0
	root.add_child(mmi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.7, 0.3)
	glow.light_energy = 6.0
	glow.omni_range = 400.0
	glow.position = Vector3(0, 230, 0)
	glow.shadow_enabled = false
	root.add_child(glow)
	var embers := FX.flame(Color(1.0, 0.7, 0.3), 200, 1.6, 2.0)
	embers.emission_sphere_radius = 120.0
	embers.lifetime = 8.0
	embers.gravity = Vector3(0, -0.4, 0)
	embers.position = Vector3(0, 220, 0)
	root.add_child(embers)


func _soft_dot() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
