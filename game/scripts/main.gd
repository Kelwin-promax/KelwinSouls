# Orquestrador do KelwinSouls: mundo, ciclo de jogo, morte/renascimento, Graças, chefes e finais.
extends Node3D

const ENEMY_SPAWN_DIST := 150.0
const ENEMY_DESPAWN_DIST := 220.0
const BOSS_SPAWN_DIST := 320.0

var terrain: Terrain
var props: Props
var structures: Structures
var hud: HUD
var player: Player
var cam: CameraRig
var sun: DirectionalLight3D
var env: Environment
var title_cam: Camera3D

var _enemy_nodes: Dictionary = {}   # índice -> Enemy
var _enemy_dead: Dictionary = {}    # índice -> true (até descansar)
var _boss_nodes: Dictionary = {}    # id -> Boss
var _graces: Dictionary = {}        # id -> Grace
var _lost_marker: Node3D
var _region := ""
var _tick := 0.0
var _playing := false
var _title_t := 0.0
var _resting_grace: Grace


func _ready() -> void:
	Game.main = self
	_setup_environment()
	hud = HUD.new()
	add_child(hud)
	hud.loading_screen("Despertando as Terras de Kelwin...")
	await get_tree().process_frame
	await _build_world()
	_show_title()


# ------------------------------------------------------------ ambiente
func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.20, 0.25, 0.36)
	sm.sky_horizon_color = Color(0.78, 0.62, 0.45)
	sm.ground_horizon_color = Color(0.5, 0.42, 0.35)
	sm.ground_bottom_color = Color(0.12, 0.1, 0.09)
	sm.sun_angle_max = 20.0
	sm.sun_curve = 0.12
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.6, 0.54)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.00045
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.06
	if Game.quality >= 2:
		env.ssao_enabled = true
		env.ssao_radius = 1.5
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, 135, 0)
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if Game.quality < 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0 if Game.quality == 0 else 160.0
	sun.shadow_blur = 1.5
	add_child(sun)


# ------------------------------------------------------------ construção do mundo
func _build_world() -> void:
	var world := Game.world
	terrain = Terrain.new()
	add_child(terrain)
	Game.terrain = terrain
	hud.loading_text("Erguendo montanhas...")
	await get_tree().process_frame
	terrain.setup(world)
	hud.loading_text("Plantando a floresta...")
	await get_tree().process_frame
	props = Props.new()
	add_child(props)
	props.setup(terrain, world)
	hud.loading_text("Reconstruindo ruínas e a Cidadela de Marfim...")
	await get_tree().process_frame
	structures = Structures.new()
	add_child(structures)
	structures.setup(terrain, world)
	hud.loading_text("Acendendo as Graças...")
	await get_tree().process_frame
	for g in world.graces:
		var gr := Grace.new()
		gr.setup(g, terrain)
		add_child(gr)
		_graces[g.id] = gr
	_make_water(world)
	# câmera do título orbitando a Árvore de Brasa
	title_cam = Camera3D.new()
	title_cam.far = 8000.0
	title_cam.fov = 55.0
	add_child(title_cam)
	title_cam.current = true
	var et: Array = world.ember_tree
	terrain.update(Vector3(et[0], 0, et[2] + 900), true)
	props.update(Vector3(et[0], 0, et[2] + 900))
	hud.loading_text("Pronto.")
	await get_tree().process_frame


func _make_water(world: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(world.size, world.size)
	pm.subdivide_depth = 0
	pm.subdivide_width = 0
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mi.material_override = mat
	mi.position = Vector3(0, world.water, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------ título e início
func _show_title() -> void:
	_playing = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	title_cam.current = true
	hud.set_hud_visible(false)
	Sfx.play_music("music_explore", 3.0)
	Sfx.play_ambience("wind_loop", -16)
	hud.title_screen(_on_new_game, _on_continue, func(): get_tree().quit())


func _on_new_game() -> void:
	Game.new_game()
	hud.lore_intro(func(): _start_play())


func _on_continue() -> void:
	Game.load_game()
	_start_play()


func _start_play() -> void:
	hud.loading_screen("Seguindo a Graça...")
	await get_tree().process_frame
	if player == null:
		player = Player.new()
		add_child(player)
		cam = CameraRig.new()
		add_child(cam)
		cam.target = player
		player.cam = cam
		hud.bind_player(player)
		player.died.connect(_on_player_died)
	for gid in _graces:
		_graces[gid].discovered = Game.discovered_graces.has(gid)
		_graces[gid]._refresh()
	var g := Game.grace_by_id(Game.last_grace)
	var pos := _grace_spawn_pos(g)
	if Game.last_grace == "graca_despertar" and Game.play_time < 1.0:
		pos = Vector3(Game.world.start[0], 0, Game.world.start[2])
	await _teleport(pos)
	player.respawn_at(player.global_position)
	cam.yaw = PI  # olhando para o norte (Cidadela/Árvore)
	cam.camera.current = true
	_reset_enemies()
	_refresh_lost_marker()
	Game.refill_flasks()
	hud.close_menu()
	hud.set_hud_visible(true)
	hud._resize_bars()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_playing = true
	_region = ""
	Sfx.play_music("music_explore", 3.0)


func _grace_spawn_pos(g: Dictionary) -> Vector3:
	return Vector3(g.pos[0] + 2.5, 0, g.pos[2] + 2.5)


func _teleport(pos: Vector3) -> void:
	terrain.update(pos, true)
	props.update(pos)
	await get_tree().physics_frame
	await get_tree().physics_frame
	pos.y = terrain.height_at(pos.x, pos.z) + 0.3
	player.global_position = pos
	player.velocity = Vector3.ZERO
	cam.global_position = pos + Vector3(0, 1.6, 0)


# ------------------------------------------------------------ laço principal
func _process(delta: float) -> void:
	if not _playing:
		_title_t += delta * 0.04
		if title_cam and title_cam.current:
			var et: Array = Game.world.ember_tree
			var c := Vector3(et[0], et[1], et[2])
			var p := c + Vector3(sin(_title_t) * 900.0, 0, cos(_title_t) * 900.0)
			p.y = max(terrain.height_at(p.x, p.z) + 40.0, c.y + 60.0)
			title_cam.global_position = p
			title_cam.look_at(c + Vector3(0, 160, 0))
		return
	if player == null:
		return
	terrain.update(player.global_position)
	props.update(player.global_position)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_stream_enemies()
		_stream_bosses()
		_check_region()
		_check_lost_brasas()


func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event.is_action_pressed("pause"):
		if hud.is_menu_open():
			if _resting_grace == null:
				_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and not hud.is_menu_open() and not player.is_dead():
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.map_menu()
		hud.menu_closed.connect(_resume, CONNECT_ONE_SHOT)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not hud.is_menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pause() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.pause_menu(_resume, func():
		get_tree().paused = false
		Game.save_game()
		_playing = false
		hud.close_menu()
		_despawn_all()
		player.queue_free()
		cam.queue_free()
		player = null
		cam = null
		Game.player = null
		title_cam.current = true
		_show_title())


func _resume() -> void:
	if hud.is_menu_open():
		hud.close_menu()
	get_tree().paused = false
	if _playing:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------ inimigos
func _stream_enemies() -> void:
	var pp := player.global_position
	var list: Array = Game.world.enemies
	for i in list.size():
		var e: Dictionary = list[i]
		var p := Vector3(e.pos[0], 0, e.pos[2])
		var d := Vector2(p.x - pp.x, p.z - pp.z).length()
		if _enemy_nodes.has(i):
			var node: Enemy = _enemy_nodes[i]
			if not is_instance_valid(node):
				_enemy_nodes.erase(i)
			elif d > ENEMY_DESPAWN_DIST and node.state != Enemy.S.CHASE and node.state != Enemy.S.ATTACK:
				node.queue_free()
				_enemy_nodes.erase(i)
		elif d < ENEMY_SPAWN_DIST and not _enemy_dead.has(i):
			var en := Enemy.new()
			en.setup(e.model, int(e.level), "enemy", Vector3(p.x, terrain.ground_y(p.x, p.z), p.z))
			var idx := i
			en.killed.connect(func(_x): _enemy_dead[idx] = true)
			add_child(en)
			_enemy_nodes[i] = en


func _stream_bosses() -> void:
	var pp := player.global_position
	var all := []
	for b in Game.world.bosses:
		all.append([b, "boss"])
	for d in Game.world.dragons:
		all.append([d, "dragon"])
	for item in all:
		var b: Dictionary = item[0]
		if Game.defeated_bosses.has(b.id):
			continue
		var p := Vector3(b.pos[0], 0, b.pos[2])
		var d := Vector2(p.x - pp.x, p.z - pp.z).length()
		var spawn_d := BOSS_SPAWN_DIST if item[1] == "boss" else 600.0
		if _boss_nodes.has(b.id):
			var node: Boss = _boss_nodes[b.id]
			if not is_instance_valid(node):
				_boss_nodes.erase(b.id)
			elif d > spawn_d * 1.3 and not node.fight_active:
				node.queue_free()
				_boss_nodes.erase(b.id)
		elif d < spawn_d:
			var node: Boss
			if item[1] == "dragon":
				var dr := Dragon.new()
				dr.setup_dragon(b, "sky" if b.model == "red_dragon" else "ground")
				node = dr
			else:
				node = Boss.new()
				node.setup_boss(b)
				if b.id == "ivorae":
					node.required_embers = 2
			node.position.y = terrain.ground_y(p.x, p.z)
			node.spawn_pos.y = node.position.y
			if item[1] == "dragon" and b.model == "red_dragon":
				node.position.y += 60.0
			node.defeated.connect(_on_boss_defeated)
			add_child(node)
			_boss_nodes[b.id] = node


func _on_boss_defeated(b: Boss) -> void:
	_boss_nodes.erase(b.boss_id)
	if b.boss_id == "ivorae":
		get_tree().create_timer(6.0).timeout.connect(_start_ending)


func _reset_enemies() -> void:
	_enemy_dead.clear()
	for i in _enemy_nodes:
		if is_instance_valid(_enemy_nodes[i]):
			_enemy_nodes[i].queue_free()
	_enemy_nodes.clear()
	for id in _boss_nodes:
		var b: Boss = _boss_nodes[id]
		if is_instance_valid(b) and not b.is_dead():
			b.reset_fight()
	if hud:
		hud.hide_boss()


func _despawn_all() -> void:
	for i in _enemy_nodes:
		if is_instance_valid(_enemy_nodes[i]):
			_enemy_nodes[i].queue_free()
	_enemy_nodes.clear()
	for id in _boss_nodes:
		if is_instance_valid(_boss_nodes[id]):
			_boss_nodes[id].queue_free()
	_boss_nodes.clear()


# ------------------------------------------------------------ morte e brasas perdidas
func _on_player_died() -> void:
	hud.death_screen()
	hud.hide_boss()
	Sfx.play_music("", 1.0)
	Game.lost_brasas = Game.brasas
	Game.lost_pos = player.global_position
	Game.add_brasas(-Game.brasas)
	cam.release_lock()
	cam.set_extra_distance(0.0)
	Game.save_game()
	await get_tree().create_timer(5.5).timeout
	hud.close_menu()
	var g := Game.grace_by_id(Game.last_grace)
	await _teleport(_grace_spawn_pos(g))
	player.respawn_at(player.global_position)
	Game.refill_flasks()
	_reset_enemies()
	_refresh_lost_marker()
	Sfx.play_music("music_explore", 3.0)


func _refresh_lost_marker() -> void:
	if _lost_marker:
		_lost_marker.queue_free()
		_lost_marker = null
	if Game.lost_brasas <= 0:
		return
	_lost_marker = Node3D.new()
	add_child(_lost_marker)
	_lost_marker.global_position = Game.lost_pos
	var f := FX.flame(Color(0.4, 1.0, 0.6), 30, 0.25, 1.0)
	_lost_marker.add_child(f)
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 1.0, 0.6)
	l.light_energy = 1.5
	l.omni_range = 6.0
	l.position.y = 0.8
	_lost_marker.add_child(l)


func _check_lost_brasas() -> void:
	if _lost_marker == null or player.is_dead():
		return
	if player.global_position.distance_to(_lost_marker.global_position) < 2.5:
		Game.add_brasas(Game.lost_brasas)
		Game.message("Brasas recuperadas: %d" % Game.lost_brasas, "item")
		Game.lost_brasas = 0
		FX.embers(self, _lost_marker.global_position, 60, 0.8)
		_lost_marker.queue_free()
		_lost_marker = null


# ------------------------------------------------------------ regiões
func _check_region() -> void:
	var r := terrain.region_at(player.global_position)
	if r != _region:
		_region = r
		if r != "":
			hud.region_banner(Game.world.regions[r].name)


# ------------------------------------------------------------ Graças
func rest_at_grace(g: Grace) -> void:
	_resting_grace = g
	player.set_resting(true)
	Sfx.play("grace_rest", -4, 0.0)
	Game.refill_flasks()
	_reset_enemies()
	Game.save_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.grace_menu(g.grace_name, _leave_grace)


func _leave_grace() -> void:
	_resting_grace = null
	player.set_resting(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func fast_travel(gid: String) -> void:
	_resting_grace = null
	get_tree().paused = false
	hud.loading_screen("Viajando...")
	Game.last_grace = gid
	await get_tree().process_frame
	await _teleport(_grace_spawn_pos(Game.grace_by_id(gid)))
	player.set_resting(false)
	_reset_enemies()
	_despawn_all()
	Game.save_game()
	hud.close_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------ final
func _start_ending() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_resting(true)
	hud.ending_choice(func(kind: String):
		Game.ending_seen = kind
		Game.save_game()
		hud.ending_text(kind, func():
			player.set_resting(false)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Game.message("O mundo continua... explore e enfrente os chefes restantes.", "small")))
