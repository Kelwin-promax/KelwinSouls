# Efeitos visuais reutilizáveis: rastro de golpe, faíscas, sangue, brasas, fogo.
class_name FX
extends RefCounted

static var _slash_mesh: ArrayMesh
static var _additive_cache: Dictionary = {}


static func additive_mat(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), energy]
	if _additive_cache.has(key):
		return _additive_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color * energy
	m.disable_receive_shadows = true
	_additive_cache[key] = m
	return m


static func _make_slash_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	var a0 := -PI * 0.55
	var a1 := PI * 0.55
	for i in seg:
		var t0 := float(i) / seg
		var t1 := float(i + 1) / seg
		var ang0 := lerpf(a0, a1, t0)
		var ang1 := lerpf(a0, a1, t1)
		var r_in := 0.55
		var r_out := 1.0
		var c0 := Color(1, 1, 1, pow(t0, 1.5))
		var c1 := Color(1, 1, 1, pow(t1, 1.5))
		var ci0 := Color(1, 1, 1, 0.0)
		var p_in0 := Vector3(sin(ang0) * r_in, 0, -cos(ang0) * r_in)
		var p_out0 := Vector3(sin(ang0) * r_out, 0, -cos(ang0) * r_out)
		var p_in1 := Vector3(sin(ang1) * r_in, 0, -cos(ang1) * r_in)
		var p_out1 := Vector3(sin(ang1) * r_out, 0, -cos(ang1) * r_out)
		st.set_color(ci0); st.add_vertex(p_in0)
		st.set_color(c0); st.add_vertex(p_out0)
		st.set_color(c1); st.add_vertex(p_out1)
		st.set_color(ci0); st.add_vertex(p_in0)
		st.set_color(c1); st.add_vertex(p_out1)
		st.set_color(ci0); st.add_vertex(p_in1)
	return st.commit()


## Arco de golpe. `roll` inclina o plano do arco (0 = horizontal, PI/2 = vertical).
static func slash(parent: Node, origin: Transform3D, radius: float, roll: float, color := Color(1.0, 0.75, 0.45), mirror := false) -> void:
	if _slash_mesh == null:
		_slash_mesh = _make_slash_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _slash_mesh
	mi.material_override = additive_mat(color, 1.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var b := origin.basis * Basis(Vector3.FORWARD, roll)
	if mirror:
		b = b * Basis.from_scale(Vector3(-1, 1, 1))
	mi.global_transform = Transform3D(b.scaled(Vector3.ONE * radius), origin.origin)
	var tw := mi.create_tween()
	tw.tween_property(mi, "transparency", 1.0, 0.22).from(0.0)
	tw.parallel().tween_property(mi, "scale", mi.scale * 1.12, 0.22)
	tw.tween_callback(mi.queue_free)


static func burst(parent: Node, pos: Vector3, color: Color, amount := 24, speed := 6.0, size := 0.08, life := 0.5, gravity := -9.0) -> void:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	var m := additive_mat(color, 3.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p.material_override = m
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func sparks(parent: Node, pos: Vector3) -> void:
	burst(parent, pos, Color(1.0, 0.7, 0.3), 30, 9.0, 0.06, 0.4, -14.0)


static func blood(parent: Node, pos: Vector3) -> void:
	burst(parent, pos, Color(0.55, 0.02, 0.02), 26, 5.0, 0.12, 0.6, -12.0)


static func embers(parent: Node, pos: Vector3, amount := 60, radius := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = amount
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 1.2, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	p.mesh = q
	var m := additive_mat(Color(1.0, 0.55, 0.15), 4.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p.material_override = m
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 0.3, 0.1, 0))
	p.color_ramp = grad
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## Chama contínua (Graça, tochas, sopro de dragão).
static func flame(color := Color(1.0, 0.65, 0.25), amount := 40, size := 0.35, height := 1.4) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.6
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = height * 0.6
	p.initial_velocity_max = height * 1.2
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	var m := additive_mat(color, 2.2)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p.material_override = m
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.add_point(0.4, Color(1, 0.6, 0.3, 0.6))
	grad.set_color(grad.get_point_count() - 1, Color(0.6, 0.1, 0.0, 0))
	p.color_ramp = grad
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.1))
	p.scale_amount_curve = curve
	return p
