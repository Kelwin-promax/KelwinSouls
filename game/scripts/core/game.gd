# Autoload "Game": estado global, atributos do personagem, save/load e controles.
extends Node

signal brasas_changed(value: int)
signal stats_changed
signal show_message(text: String, kind: String)
signal flasks_changed(value: int)

const SAVE_PATH := "user://kelwinsouls_save.json"

# ---- dados do mundo (carregados uma vez)
var world: Dictionary = {}
var manifest: Dictionary = {}

# ---- progresso
var brasas := 0
var level := 1
var vigor := 10
var endurance := 10
var strength := 10
var flasks_max := 4
var flasks := 4
var great_embers: Array = []          # ids de chefes cujas Grandes Brasas foram tomadas
var defeated_bosses: Array = []
var discovered_graces: Array = ["graca_despertar"]
var last_grace := "graca_despertar"
var lost_brasas := 0
var lost_pos := Vector3.ZERO
var play_time := 0.0
var ending_seen := ""
var world_time := 9.0                 # horas desde o início do mundo (dia = floor(t/24)+1)
var mounted := false                  # montado no cavalo?
var dungeon_active := false           # dentro de uma masmorra (chão plano em outra altura)
var dungeon_floor_y := 0.0
var dungeon: Node = null              # masmorra atual (tem is_walkable)
var horse: Node = null                # cavalo da montaria (Horse)
var dungeons_cleared: Array = []      # ids de masmorras concluídas
var npc_flags: Dictionary = {}        # progresso de diálogos (ex.: "vesper_ajudou": true)

# ---- configurações
var mouse_sens := 0.22
var invert_y := false
var quality := 1   # 0 baixo, 1 médio, 2 alto

# ---- referências de cena (preenchidas pelo main)
var player: Node = null
var terrain: Node = null
var hud: Node = null
var main: Node = null

var _scene_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_load_data()
	_load_settings()


func _process(delta: float) -> void:
	if player != null and not get_tree().paused:
		play_time += delta


# ------------------------------------------------------------ dados
func _load_data() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/world.json"))
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/manifest.json"))


## Altura do chão no ponto (x, z): o terreno lá fora, o piso da masmorra lá dentro.
func ground_height(x: float, z: float) -> float:
	if dungeon_active:
		return dungeon_floor_y
	if terrain == null:
		return 0.0
	return terrain.height_at(x, z)


func ground_y(x: float, z: float) -> float:
	if dungeon_active:
		return dungeon_floor_y
	if terrain == null:
		return 0.0
	return terrain.ground_y(x, z)


## Modelos licenciados que não vão para a build distribuída: se o arquivo não existir,
## usa o substituto. O .exe exportado não contém o asset de Game of Thrones (ver export_presets.cfg).
const MODEL_FALLBACK := {"drogon_-_dragon_game_of_thrones": "red_dragon"}


## Versão com esqueleto e animações (gerada por tools/rig/rig_humanoid.py), se existir.
func rig_path(model_name: String) -> String:
	return "res://assets/models/%s__rig.glb" % model_name


func has_rig(model_name: String) -> bool:
	return ResourceLoader.exists(rig_path(model_name))


func model_scene(model_name: String) -> PackedScene:
	if not _scene_cache.has(model_name):
		var path := "res://assets/models/%s.glb" % model_name
		if has_rig(model_name):
			path = rig_path(model_name)
		elif not ResourceLoader.exists(path) and MODEL_FALLBACK.has(model_name):
			path = "res://assets/models/%s.glb" % MODEL_FALLBACK[model_name]
		_scene_cache[model_name] = load(path)
	return _scene_cache[model_name]


func model_info(model_name: String) -> Dictionary:
	return manifest.get(model_name, {})


func grace_by_id(id: String) -> Dictionary:
	for g in world.graces:
		if g.id == id:
			return g
	return world.graces[0]


func boss_by_id(id: String) -> Dictionary:
	for b in world.bosses:
		if b.id == id:
			return b
	return {}


# ------------------------------------------------------------ atributos
func max_hp() -> float:
	return 420.0 + (vigor - 10) * 32.0


func max_stamina() -> float:
	return 90.0 + (endurance - 10) * 4.5


func damage_mult() -> float:
	return 1.0 + (strength - 10) * 0.045


func level_cost() -> int:
	return int(120 + pow(level, 1.55) * 40)


func add_brasas(v: int) -> void:
	brasas = max(0, brasas + v)
	brasas_changed.emit(brasas)


func level_up(stat: String) -> bool:
	var c := level_cost()
	if brasas < c:
		return false
	brasas -= c
	level += 1
	match stat:
		"vigor": vigor += 1
		"endurance": endurance += 1
		"strength": strength += 1
	brasas_changed.emit(brasas)
	stats_changed.emit()
	return true


func refill_flasks() -> void:
	flasks = flasks_max
	flasks_changed.emit(flasks)


func message(text: String, kind := "info") -> void:
	show_message.emit(text, kind)


# ------------------------------------------------------------ save/load
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func new_game() -> void:
	brasas = 0; level = 1; vigor = 10; endurance = 10; strength = 10
	flasks_max = 4; flasks = 4
	great_embers = []; defeated_bosses = []
	discovered_graces = ["graca_despertar"]; last_grace = "graca_despertar"
	lost_brasas = 0; play_time = 0.0; ending_seen = ""
	world_time = 9.0; dungeons_cleared = []; npc_flags = {}


func save_game() -> void:
	var d := {
		"brasas": brasas, "level": level, "vigor": vigor, "endurance": endurance, "strength": strength,
		"flasks_max": flasks_max, "great_embers": great_embers, "defeated_bosses": defeated_bosses,
		"discovered_graces": discovered_graces, "last_grace": last_grace,
		"lost_brasas": lost_brasas, "lost_pos": [lost_pos.x, lost_pos.y, lost_pos.z],
		"play_time": play_time, "ending_seen": ending_seen,
		"world_time": world_time, "dungeons_cleared": dungeons_cleared, "npc_flags": npc_flags,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))


func load_game() -> bool:
	if not has_save():
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	brasas = int(d.get("brasas", 0)); level = int(d.get("level", 1))
	vigor = int(d.get("vigor", 10)); endurance = int(d.get("endurance", 10)); strength = int(d.get("strength", 10))
	flasks_max = int(d.get("flasks_max", 4)); flasks = flasks_max
	great_embers = d.get("great_embers", []); defeated_bosses = d.get("defeated_bosses", [])
	discovered_graces = d.get("discovered_graces", ["graca_despertar"]); last_grace = d.get("last_grace", "graca_despertar")
	lost_brasas = int(d.get("lost_brasas", 0))
	var lp: Array = d.get("lost_pos", [0, 0, 0])
	lost_pos = Vector3(lp[0], lp[1], lp[2])
	play_time = float(d.get("play_time", 0.0)); ending_seen = d.get("ending_seen", "")
	world_time = float(d.get("world_time", 9.0))
	dungeons_cleared = d.get("dungeons_cleared", [])
	npc_flags = d.get("npc_flags", {})
	return true


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		mouse_sens = cfg.get_value("input", "mouse_sens", mouse_sens)
		invert_y = cfg.get_value("input", "invert_y", invert_y)
		quality = cfg.get_value("video", "quality", quality)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sens", mouse_sens)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("video", "quality", quality)
	cfg.save("user://settings.cfg")


# ------------------------------------------------------------ controles
func _add_key(action: String, keys: Array, mouse: Array = [], joy_buttons: Array = [], joy_axes: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for m in mouse:
		var e := InputEventMouseButton.new()
		e.button_index = m
		InputMap.action_add_event(action, e)
	for b in joy_buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in joy_axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)


func _setup_input() -> void:
	_add_key("move_forward", [KEY_W, KEY_UP], [], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add_key("move_back", [KEY_S, KEY_DOWN], [], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add_key("move_left", [KEY_A, KEY_LEFT], [], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_key("move_right", [KEY_D, KEY_RIGHT], [], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_add_key("cam_left", [], [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_add_key("cam_right", [], [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_add_key("cam_up", [], [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_add_key("cam_down", [], [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_add_key("attack", [], [MOUSE_BUTTON_LEFT], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_key("heavy_attack", [KEY_CTRL], [], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_add_key("guard", [], [MOUSE_BUTTON_RIGHT], [JOY_BUTTON_LEFT_SHOULDER])
	_add_key("dodge", [KEY_SPACE], [], [JOY_BUTTON_B])
	_add_key("sprint", [KEY_SHIFT], [], [JOY_BUTTON_LEFT_STICK])
	_add_key("jump", [KEY_F], [], [JOY_BUTTON_Y])
	_add_key("lock_on", [KEY_Q], [MOUSE_BUTTON_MIDDLE], [JOY_BUTTON_RIGHT_STICK])
	_add_key("use_flask", [KEY_R], [], [JOY_BUTTON_X])
	_add_key("interact", [KEY_E], [], [JOY_BUTTON_A])
	_add_key("map", [KEY_M, KEY_TAB], [], [JOY_BUTTON_BACK])
	_add_key("inventory", [KEY_I], [], [JOY_BUTTON_DPAD_DOWN])
	_add_key("mount", [KEY_G], [], [JOY_BUTTON_DPAD_LEFT])
	_add_key("pause", [KEY_ESCAPE], [], [JOY_BUTTON_START])
	_add_key("ui_up_alt", [KEY_W], [], [])
	_add_key("ui_down_alt", [KEY_S], [], [])
