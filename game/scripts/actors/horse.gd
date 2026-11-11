# Cavalo da montaria (Etapa 4). Construído com primitivas e animado proceduralmente.
# Anda sobre o terreno (sem colisão de corpo). O jogador monta com G perto dele.
class_name Horse
extends Node3D

const SADDLE_H := 1.25      # altura da sela: o modelo do cavaleiro é erguido até aqui
const WALK := 6.5
const GALLOP := 13.0
const TURN_RATE := 3.2
const ACCEL := 3.0

var rider: Node = null
var _speed := 0.0
var _phase := 0.0
var _legs: Array[Node3D] = []
var _body: Node3D
var _tail: Node3D
var _head: Node3D
var _near_rider := false


func setup(pos: Vector3, yaw := 0.0) -> void:
	position = Vector3(pos.x, Game.ground_y(pos.x, pos.z), pos.z)
	rotation.y = yaw


func _ready() -> void:
	add_to_group("horses")
	_build()


# ------------------------------------------------------------ modelo
func _build() -> void:
	var coat := _mat(Color(0.34, 0.21, 0.12), 0.9)
	var dark := _mat(Color(0.09, 0.06, 0.05), 0.95)
	var leather := _mat(Color(0.36, 0.22, 0.12), 0.6)
	var metal := _mat(Color(0.55, 0.52, 0.48), 0.35, 0.8)

	_body = Node3D.new()
	add_child(_body)
	_add_mesh(_body, _capsule(0.42, 1.8), coat, Vector3(0, 1.22, 0), Vector3(PI / 2.0, 0, 0))
	# pescoço e cabeça
	var neck := _add_mesh(_body, _cyl(0.17, 0.24, 0.95), coat, Vector3(0, 1.82, -0.95), Vector3(-0.75, 0, 0))
	_add_mesh(neck, _cyl(0.07, 0.07, 0.1), dark, Vector3.ZERO)
	_head = Node3D.new()
	_head.position = Vector3(0, 2.2, -1.42)
	_head.rotation.x = 0.35
	_body.add_child(_head)
	_add_mesh(_head, _box(Vector3(0.24, 0.3, 0.62)), coat, Vector3.ZERO)
	_add_mesh(_head, _box(Vector3(0.18, 0.22, 0.2)), coat, Vector3(0, -0.12, -0.36))   # focinho
	_add_mesh(_head, _box(Vector3(0.06, 0.2, 0.06)), dark, Vector3(-0.1, 0.22, 0.1))   # orelhas
	_add_mesh(_head, _box(Vector3(0.06, 0.2, 0.06)), dark, Vector3(0.1, 0.22, 0.1))
	# crina
	_add_mesh(_body, _box(Vector3(0.09, 0.3, 1.0)), dark, Vector3(0, 2.0, -0.85), Vector3(-0.75, 0, 0))
	# sela, cilhas e estribos
	_add_mesh(_body, _box(Vector3(0.52, 0.1, 0.85)), leather, Vector3(0, 1.66, 0.05))
	_add_mesh(_body, _box(Vector3(0.6, 0.06, 0.06)), leather, Vector3(0, 1.45, 0.05))
	for s in [-1.0, 1.0]:
		_add_mesh(_body, _box(Vector3(0.04, 0.3, 0.04)), metal, Vector3(s * 0.34, 1.4, 0.05))
		_add_mesh(_body, _box(Vector3(0.1, 0.03, 0.12)), metal, Vector3(s * 0.34, 1.22, 0.05))
	# cauda
	_tail = Node3D.new()
	_tail.position = Vector3(0, 1.38, 0.9)
	_tail.rotation.x = 0.5
	_body.add_child(_tail)
	_add_mesh(_tail, _cyl(0.04, 0.12, 0.7), dark, Vector3(0, -0.35, 0))
	# pernas: pivôs nos ombros/quadris, com a perna para baixo
	for leg in [Vector3(-0.22, 1.0, -0.62), Vector3(0.22, 1.0, -0.62), Vector3(-0.22, 1.0, 0.62), Vector3(0.22, 1.0, 0.62)]:
		var pivot := Node3D.new()
		pivot.position = leg
		add_child(pivot)
		_add_mesh(pivot, _cyl(0.07, 0.06, 1.0), coat, Vector3(0, -0.5, 0))
		_add_mesh(pivot, _box(Vector3(0.12, 0.1, 0.16)), dark, Vector3(0, -1.05, -0.02))   # casco
		_legs.append(pivot)


func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	return c


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------ montaria
func mount_by(p: Node) -> void:
	rider = p
	_speed = 0.0
	_near_rider = false
	if Game.hud:
		Game.hud.set_prompt("")


func dismount() -> void:
	rider = null
	_speed = 0.0


func saddle_height() -> float:
	return SADDLE_H


func speed01() -> float:
	return clampf(_speed / GALLOP, 0.0, 1.0)


## Chamado pelo jogador enquanto montado. input = eixos do analógico/WASD; cam_basis = base da câmera.
func drive(delta: float, input: Vector2, cam_basis: Basis) -> void:
	var dir := cam_basis * Vector3(input.x, 0, input.y)
	dir.y = 0.0
	var target := 0.0
	if dir.length() > 0.05:
		var want := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-delta * TURN_RATE))
		var top := GALLOP if Input.is_action_pressed("sprint") else WALK
		target = top * clampf(input.length(), 0.0, 1.0)
	_speed = lerpf(_speed, target, 1.0 - exp(-delta * ACCEL))
	var fwd := -global_transform.basis.z
	var np := global_position + fwd * _speed * delta
	np.y = Game.ground_y(np.x, np.z)
	global_position = np
	_animate(delta)


func _animate(delta: float) -> void:
	var s := clampf(_speed / WALK, 0.0, 1.6)
	_phase += delta * _speed * 1.9
	# passo a passo: diagonais juntas (dianteira esquerda + traseira direita, etc.)
	var offsets := [0.0, PI, PI, 0.0]
	for i in _legs.size():
		var swing := sin(_phase + offsets[i]) * 0.5 * minf(s, 1.0)
		_legs[i].rotation.x = swing
	_body.position.y = absf(sin(_phase * 2.0)) * 0.05 * minf(s, 1.0)
	_tail.rotation.x = 0.5 + sin(_phase * 0.5) * 0.08
	_head.rotation.x = 0.35 - 0.1 * minf(s, 1.0)


# ------------------------------------------------------------ dica de interação
func _process(_delta: float) -> void:
	if rider != null:
		return
	var p := Game.player as Player
	if p == null:
		return
	var near := p.global_position.distance_to(global_position) < 3.5 and not p.is_busy()
	if near != _near_rider:
		_near_rider = near
		if Game.hud and near:
			Game.hud.set_prompt("[G] Montar no cavalo")
		elif Game.hud and not near:
			Game.hud.set_prompt("")
