# Masmorra (Etapa 4). A entrada é um portal de pedra no mundo aberto. Ao entrar, um labirinto
# é gerado num vale subterrâneo (y = DEPTH_Y, longe do mapa), com inimigos, um guardião e um
# baú de recompensa. Ao sair, o interior é descartado. Paredes são blocos de TILE metros:
# cada corredor tem um tile de largura, então a colisão e a navegação dos inimigos batem.
class_name Dungeon
extends Node3D

const DEPTH_Y := -400.0
const CELLS := 9                 # células do labirinto por lado
const N := 19                    # tiles por lado (2 * CELLS + 1)
const TILE := 4.5
const WALL_H := 4.2
const GATE_RANGE := 3.2
const EXTRA_OPENINGS := 0.10     # fração de paredes internas removidas (cria ciclos)

const DEFS := [
	{"id": "catacumbas_ghelm", "title": "Catacumbas de Ghelm", "grace": "graca_cemiterio",
	 "gate": [-16.0, 12.0], "mobs": ["vaelrith__the_veiled_horn", "gravestone_golem_-_cemetery_guardian"],
	 "mob_level": 3, "guardian": "gravestone_golem_-_cemetery_guardian", "guardian_level": 4, "reward": 600},
	{"id": "poco_pantano", "title": "Poço do Pântano", "grace": "graca_pantano",
	 "gate": [14.0, -12.0], "mobs": ["varkhen__the_obsidian_oathbreaker"],
	 "mob_level": 4, "guardian": "astravyne__the_ivory_bloodlancer", "guardian_level": 6, "reward": 900},
]

var def: Dictionary = {}
var index := 0
var gate_pos := Vector3.ZERO
var _origin := Vector3.ZERO          # canto de referência do labirinto (mundo)
var _inner: Node3D = null
var _inside := false
var _walls := PackedByteArray()       # N*N; 1 = parede
var _start_tile := Vector2i.ZERO
var _guard_tile := Vector2i.ZERO
var _guard: Enemy = null
var _guard_dead := false
var _chest_open := false
var _chest_node: Node3D = null
var _chest_lid: Node3D = null
var _near := ""
var _prompt := ""


func setup(d: Dictionary, idx: int, grace_pos: Vector3, terrain: Terrain) -> void:
	def = d
	index = idx
	var g: Array = d.gate
	var x: float = grace_pos.x + g[0]
	var z: float = grace_pos.z + g[1]
	gate_pos = Vector3(x, terrain.height_at(x, z), z)
	position = gate_pos
	# labirintos ficam longe do mapa, cada um numa coordenada própria
	_origin = Vector3(1000.0 + 400.0 * idx, DEPTH_Y, 1000.0)


func _ready() -> void:
	add_to_group("dungeons")
	_build_gate()


func title() -> String:
	return def.title


func is_inside() -> bool:
	return _inside


## Posição de entrada (dentro) e de saída (frente do portal, no mundo aberto).
func start_world() -> Vector3:
	return _tile_world(_start_tile) + Vector3(0, 0.3, 0)


func exit_world() -> Vector3:
	return gate_pos + Vector3(0, 0, 2.5)


## Usado pelos inimigos: a célula em (x, z) do mundo é transitável (não é parede)?
func is_walkable(p: Vector3) -> bool:
	var t := _world_tile(p)
	if t.x < 0 or t.y < 0 or t.x >= N or t.y >= N:
		return false
	return _walls[t.y * N + t.x] == 0


# ------------------------------------------------------------ portal (no mundo aberto)
func _build_gate() -> void:
	var stone := _stone_mat(Color(0.28, 0.26, 0.25))
	var glow := FX.additive_mat(Color(0.45, 1.0, 0.65), 1.6)
	_add_static_box(self, Vector3(-1.9, 2.1, 0), Vector3(1.0, 4.2, 1.2), stone)
	_add_static_box(self, Vector3(1.9, 2.1, 0), Vector3(1.0, 4.2, 1.2), stone)
	_add_static_box(self, Vector3(0, 4.3, 0), Vector3(4.8, 0.9, 1.3), stone)
	var recess := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(2.6, 3.4, 0.1)
	recess.mesh = rb
	recess.material_override = glow
	recess.position = Vector3(0, 1.9, 0)
	recess.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(recess)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.45, 1.0, 0.65)
	lamp.light_energy = 1.4
	lamp.omni_range = 9.0
	lamp.position = Vector3(0, 2.0, 1.0)
	lamp.shadow_enabled = false
	add_child(lamp)
	add_child(FX.flame(Color(0.5, 1.0, 0.7), 22, 0.22, 0.9))


func _process(_delta: float) -> void:
	var p := Game.player as Player
	if p == null:
		return
	var near := ""
	var prompt := ""
	if not _inside:
		if not Game.dungeon_active and p.global_position.distance_to(global_position) < GATE_RANGE:
			near = "gate"
			prompt = "[E] Entrar em %s" % def.title
	elif Game.dungeon == self:
		var d_pos := p.global_position
		if _guard_dead and not _chest_open and _chest_node and d_pos.distance_to(_chest_node.global_position) < 2.6:
			near = "chest"
			prompt = "[E] Abrir o baú"
		elif _exit_node() and d_pos.distance_to(_exit_node().global_position) < 2.2:
			near = "exit"
			prompt = "[E] Sair da masmorra"
	if near != _near or prompt != _prompt:
		_near = near
		_prompt = prompt
		if Game.hud:
			Game.hud.set_prompt(prompt)
	if _chest_lid and _chest_open:
		_chest_lid.rotation.x = lerpf(_chest_lid.rotation.x, -1.6, 0.05)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or _near == "":
		return
	var p := Game.player as Player
	if p == null or p.is_busy():
		return
	get_viewport().set_input_as_handled()
	match _near:
		"gate":
			Game.main.enter_dungeon(self)
		"exit":
			Game.main.leave_dungeon(self)
		"chest":
			_open_chest()


# ------------------------------------------------------------ interior
func build_interior() -> void:
	if _inside:
		return
	_inside = true
	_inner = Node3D.new()
	Game.main.add_child(_inner)
	_generate_maze()
	_build_geometry()
	_place_props()
	_spawn_mobs()


func clear_interior() -> void:
	if not _inside:
		return
	_inside = false
	for c in _inner.get_children():
		c.queue_free()
	_inner.queue_free()
	_inner = null
	_guard = null
	_guard_dead = false
	_chest_open = false
	_chest_node = null
	_chest_lid = null
	_near = ""
	_prompt = ""


func _tile_world(t: Vector2i) -> Vector3:
	var half := N * TILE * 0.5
	return _origin + Vector3((t.x + 0.5) * TILE - half, 0.0, (t.y + 0.5) * TILE - half)


func _world_tile(p: Vector3) -> Vector2i:
	var half := N * TILE * 0.5
	var lx := p.x - _origin.x + half
	var lz := p.z - _origin.z + half
	return Vector2i(int(floor(lx / TILE)), int(floor(lz / TILE)))


func _exit_node() -> Node3D:
	return _inner.get_node_or_null("Exit") as Node3D if _inner else null


func _generate_maze() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_walls = PackedByteArray()
	_walls.resize(N * N)
	_walls.fill(1)
	var seen := PackedByteArray()
	seen.resize(CELLS * CELLS)
	seen.fill(0)
	# backtracker recursivo (iterativo), a partir da célula (0, 0)
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	seen[0] = 1
	_carve(Vector2i(1, 1))
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var opts: Array[Vector2i] = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < CELLS and n.y < CELLS and seen[n.y * CELLS + n.x] == 0:
				opts.append(n)
		if opts.is_empty():
			stack.pop_back()
			continue
		var nxt: Vector2i = opts[rng.randi() % opts.size()]
		seen[nxt.y * CELLS + nxt.x] = 1
		# tile da célula = (2x+1, 2y+1); o tile entre duas células é a média
		_carve(Vector2i(2 * c.x + 1 + (nxt.x - c.x), 2 * c.y + 1 + (nxt.y - c.y)))
		_carve(Vector2i(2 * nxt.x + 1, 2 * nxt.y + 1))
		stack.append(nxt)
	# alguns atalhos para não ser uma árvore pura
	for y in range(1, N - 1):
		for x in range(1, N - 1):
			if (x % 2 == 0) != (y % 2 == 0) and _walls[y * N + x] == 1 and rng.randf() < EXTRA_OPENINGS:
				_walls[y * N + x] = 0
	_start_tile = Vector2i(1, 1)
	var far := _farthest_open(_start_tile)
	_guard_tile = far


func _carve(t: Vector2i) -> void:
	_walls[t.y * N + t.x] = 0


## Maior distância em passos a partir de `from`, entre as células do labirinto (BFS nos tiles).
func _farthest_open(from: Vector2i) -> Vector2i:
	var dist := PackedInt32Array()
	dist.resize(N * N)
	dist.fill(-1)
	dist[from.y * N + from.x] = 0
	var q: Array[Vector2i] = [from]
	var best := from
	var best_d := 0
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		var dcur: int = dist[cur.y * N + cur.x]
		if (cur.x % 2 == 1) and (cur.y % 2 == 1) and dcur > best_d:
			best_d = dcur
			best = cur
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if n.x < 0 or n.y < 0 or n.x >= N or n.y >= N:
				continue
			if _walls[n.y * N + n.x] == 1 or dist[n.y * N + n.x] != -1:
				continue
			dist[n.y * N + n.x] = dcur + 1
			q.append(n)
	return best


func _build_geometry() -> void:
	var W := N * TILE
	var stone := _stone_mat(Color(0.3, 0.28, 0.26))
	var dark := _stone_mat(Color(0.12, 0.11, 0.1))
	# piso e teto (com colisão, para o jogador não sair do labirinto)
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(_origin.x, DEPTH_Y, _origin.z)
	_inner.add_child(floor_body)
	_add_shape(floor_body, Vector3(0, -0.5, 0), Vector3(W + TILE, 1.0, W + TILE))
	_add_visual(floor_body, Vector3(0, -0.5, 0), Vector3(W + TILE, 1.0, W + TILE), dark)
	var ceil_body := StaticBody3D.new()
	ceil_body.position = Vector3(_origin.x, DEPTH_Y, _origin.z)
	_inner.add_child(ceil_body)
	_add_shape(ceil_body, Vector3(0, WALL_H + 0.5, 0), Vector3(W + TILE, 1.0, W + TILE))
	_add_visual(ceil_body, Vector3(0, WALL_H + 0.5, 0), Vector3(W + TILE, 1.0, W + TILE), dark)
	# paredes: um MultiMesh para desenhar e um corpo estático com um bloco por parede
	var walls_body := StaticBody3D.new()
	walls_body.position = Vector3(_origin.x, DEPTH_Y, _origin.z)
	_inner.add_child(walls_body)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(TILE, WALL_H, TILE)
	mm.mesh = box
	var count := 0
	for y in N:
		for x in N:
			if _walls[y * N + x] == 1:
				count += 1
	mm.instance_count = count
	var k := 0
	for y in N:
		for x in N:
			if _walls[y * N + x] == 1:
				var local := Vector3((x + 0.5) * TILE - W * 0.5, WALL_H * 0.5, (y + 0.5) * TILE - W * 0.5)
				mm.set_instance_transform(k, Transform3D(Basis(), local))
				_add_shape(walls_body, local, Vector3(TILE, WALL_H, TILE))
				k += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = stone
	walls_body.add_child(mmi)
	# tochas nas células abertas (uma em cada ~4 células)
	var lit := 0
	for y in range(1, N - 1, 2):
		for x in range(1, N - 1, 2):
			if (x + y) % 4 != 0 or Vector2i(x, y) == _start_tile:
				continue
			var p := _tile_world(Vector2i(x, y))
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.68, 0.36)
			lamp.light_energy = 1.7
			lamp.omni_range = 11.0
			lamp.shadow_enabled = false
			lamp.position = p + Vector3(0, 2.7, 0)
			_inner.add_child(lamp)
			var f := FX.flame(Color(1.0, 0.7, 0.35), 18, 0.2, 0.7)
			f.position = p + Vector3(0, 0.2, 0)
			_inner.add_child(f)
			lit += 1
	# o piso ganha luz suave para a visão não cair no escuro total
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.4, 0.45, 0.6)
	fill.light_energy = 0.4
	fill.omni_range = 40.0
	fill.position = _tile_world(_start_tile) + Vector3(0, 3.0, 0)
	_inner.add_child(fill)


func _place_props() -> void:
	# entrada (início) com um círculo luminoso de saída
	var start := _tile_world(_start_tile)
	var exit := Node3D.new()
	exit.name = "Exit"
	exit.position = start + Vector3(0, 0.02, 0)
	_inner.add_child(exit)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 1.4
	cm.height = 0.04
	disc.mesh = cm
	disc.material_override = FX.additive_mat(Color(0.45, 1.0, 0.65), 1.2)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	exit.add_child(disc)
	# baú + guardião no ponto mais distante
	var g := _tile_world(_guard_tile)
	var chest := Node3D.new()
	chest.position = g + Vector3(1.1, 0, 1.1)   # canto do tile do guardião
	_inner.add_child(chest)
	_chest_node = chest
	var wood := _stone_mat(Color(0.32, 0.2, 0.1))
	var metal := _stone_mat(Color(0.6, 0.5, 0.25))
	metal.metallic = 0.8
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.7, 0.85)
	base.mesh = bm
	base.material_override = wood
	base.position = Vector3(0, 0.35, 0)
	chest.add_child(base)
	_chest_lid = Node3D.new()
	_chest_lid.position = Vector3(0, 0.7, -0.42)
	chest.add_child(_chest_lid)
	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.3, 0.22, 0.85)
	lid.mesh = lm
	lid.material_override = wood
	lid.position = Vector3(0, 0.11, 0.42)
	_chest_lid.add_child(lid)
	var lock := MeshInstance3D.new()
	var lkm := BoxMesh.new()
	lkm.size = Vector3(0.22, 0.24, 0.06)
	lock.mesh = lkm
	lock.material_override = metal
	lock.position = Vector3(0, 0.0, 0.46)
	chest.add_child(lock)
	chest.visible = true


func _spawn_mobs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var placed := 0
	for y in range(1, N - 1, 2):
		for x in range(1, N - 1, 2):
			var t := Vector2i(x, y)
			if t == _start_tile or t == _guard_tile:
				continue
			if rng.randf() > 0.42 or placed >= 16:
				continue
			var model: String = def.mobs[rng.randi() % def.mobs.size()]
			var lvl: int = int(def.mob_level) + (1 if rng.randf() < 0.3 else 0)
			var en := Enemy.new()
			en.setup(model, lvl, "enemy", _tile_world(t) + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)))
			_inner.add_child(en)
			placed += 1
	# guardião com recompensa: elite, na ponta do labirinto
	var gm: String = def.guardian
	_guard = Enemy.new()
	_guard.setup(gm, int(def.guardian_level), "elite", _tile_world(_guard_tile))
	_guard.killed.connect(func(_e):
		_guard_dead = true
		if Game.hud:
			Game.hud.big_banner("%s caiu" % _guard.display_name, Color(1.0, 0.85, 0.5), 2.0)
			Game.hud.set_prompt(""))
	_inner.add_child(_guard)


func _open_chest() -> void:
	if _chest_open:
		return
	_chest_open = true
	var first := not Game.dungeons_cleared.has(def.id)
	if first:
		Game.dungeons_cleared.append(def.id)
		Game.add_brasas(int(def.reward))
		Game.flasks_max += 1
		Game.flasks = Game.flasks_max
		Game.flasks_changed.emit(Game.flasks)
		Game.message("Masmorra concluída: +%d Brasas e +1 Lágrima Ígnea" % int(def.reward), "item")
		Game.save_game()
	else:
		Game.message("O baú já foi saqueado", "small")
	Sfx.play_at("grace_discover", _chest_node.global_position, -4)
	FX.embers(_inner, _chest_node.global_position + Vector3(0, 1, 0), 60, 0.8)


# ------------------------------------------------------------ materiais e formas
func _stone_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m


func _add_shape(body: StaticBody3D, local: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = local
	body.add_child(cs)


func _add_visual(parent: Node3D, local: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = local
	parent.add_child(mi)


func _add_static_box(parent: Node3D, local: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = local
	parent.add_child(body)
	_add_shape(body, Vector3.ZERO, size)
	_add_visual(body, Vector3.ZERO, size, mat)
