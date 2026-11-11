# Ciclo de dia/noite e clima: move o sol, troca céu/neblina e controla chuva e relâmpagos.
# Um dia completo dura DAY_SECONDS segundos reais. O tempo do mundo fica em Game.world_time (horas).
class_name SkyCycle
extends Node

signal weather_changed(kind: int)

const DAY_SECONDS := 1440.0          # 24 min reais = 1 dia no jogo (1 hora a cada minuto)
const WEATHER_MIN := 240.0           # o clima muda a cada 4 a 12 minutos reais
const WEATHER_MAX := 720.0
const TRANSITION := 18.0             # segundos para o clima mudar gradualmente

enum Weather { CLEAR, OVERCAST, RAIN, STORM }
const WEATHER_NAMES := ["Céu limpo", "Nublado", "Chuva", "Tempestade"]
const WEATHER_CLOUD := [0.0, 0.5, 0.8, 1.0]

# Paleta por hora: [hora, topo do céu, horizonte, neblina, cor do sol, energia do sol, luz ambiente]
const KEYS := [
	[0.0, Color(0.02, 0.03, 0.08), Color(0.07, 0.08, 0.13), Color(0.08, 0.09, 0.14), Color(0.45, 0.55, 0.9), 0.10, 0.25],
	[5.0, Color(0.08, 0.10, 0.20), Color(0.35, 0.30, 0.38), Color(0.25, 0.24, 0.30), Color(0.80, 0.60, 0.70), 0.35, 0.40],
	[6.5, Color(0.25, 0.30, 0.45), Color(0.95, 0.55, 0.35), Color(0.70, 0.50, 0.40), Color(1.00, 0.60, 0.35), 0.90, 0.60],
	[9.0, Color(0.20, 0.25, 0.36), Color(0.78, 0.62, 0.45), Color(0.66, 0.60, 0.54), Color(1.00, 0.86, 0.66), 1.35, 0.75],
	[16.0, Color(0.20, 0.27, 0.40), Color(0.80, 0.66, 0.48), Color(0.66, 0.60, 0.54), Color(1.00, 0.85, 0.62), 1.30, 0.75],
	[18.0, Color(0.25, 0.22, 0.35), Color(0.95, 0.45, 0.25), Color(0.60, 0.40, 0.35), Color(1.00, 0.50, 0.25), 0.70, 0.50],
	[19.5, Color(0.08, 0.08, 0.18), Color(0.50, 0.30, 0.30), Color(0.30, 0.25, 0.30), Color(0.80, 0.40, 0.40), 0.20, 0.35],
	[21.0, Color(0.02, 0.03, 0.08), Color(0.07, 0.08, 0.13), Color(0.08, 0.09, 0.14), Color(0.45, 0.55, 0.90), 0.10, 0.25],
	[24.0, Color(0.02, 0.03, 0.08), Color(0.07, 0.08, 0.13), Color(0.08, 0.09, 0.14), Color(0.45, 0.55, 0.90), 0.10, 0.25],
]

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var weather: int = Weather.CLEAR
var outdoor := true
var follow_target: Node3D = null

var _cloud := 0.0           # 0 céu limpo .. 1 tempestade (suavizado)
var _next_change := 0.0
var _lightning_t := 0.0
var _flash := 0.0
var _rain: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _base_fog_density := 0.00045
var _base_fog_color := Color(0.66, 0.6, 0.54)
var _grey := Color(0.42, 0.44, 0.48)


func setup(p_env: Environment, p_sun: DirectionalLight3D) -> void:
	env = p_env
	sun = p_sun
	sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	_base_fog_density = env.fog_density
	_base_fog_color = env.fog_light_color
	_build_rain()
	_next_change = randf_range(WEATHER_MIN, WEATHER_MAX)
	_apply(0.0)


# Chamado pelo main a cada quadro de jogo.
func update(delta: float) -> void:
	Game.world_time += delta / DAY_SECONDS * 24.0
	_update_weather(delta)
	_apply(delta)
	_update_rain(delta)


func set_outdoor(v: bool) -> void:
	outdoor = v
	if _rain:
		_rain.emitting = v and weather >= Weather.RAIN
		_rain.visible = v


func weather_name() -> String:
	return WEATHER_NAMES[weather]


func set_weather(w: int) -> void:
	if w == weather:
		return
	weather = w
	_next_change = randf_range(WEATHER_MIN, WEATHER_MAX)
	weather_changed.emit(w)


func day_number() -> int:
	return int(floor(Game.world_time / 24.0)) + 1


func clock_text() -> String:
	var h := fposmod(Game.world_time, 24.0)
	return "Dia %d  %02d:%02d" % [day_number(), int(h), int(fmod(h, 1.0) * 60.0)]


# ------------------------------------------------------------ céu e sol
func _palette(hour: float) -> Array:
	var h := fposmod(hour, 24.0)
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= a[0] and h <= b[0]:
			var t: float = (h - a[0]) / max(b[0] - a[0], 0.001)
			t = smoothstep(0.0, 1.0, t)
			return [
				(a[1] as Color).lerp(b[1], t),
				(a[2] as Color).lerp(b[2], t),
				(a[3] as Color).lerp(b[3], t),
				(a[4] as Color).lerp(b[4], t),
				lerpf(a[5], b[5], t),
				lerpf(a[6], b[6], t),
			]
	var k: Array = KEYS[0]
	return [k[1], k[2], k[3], k[4], k[5], k[6]]


func _apply(_delta: float) -> void:
	if env == null:
		return
	var hour := fposmod(Game.world_time, 24.0)
	var p := _palette(hour)
	var c := _cloud
	var overcast := _grey
	# sol: sobe de manhã, se põe à noite
	var elev := 70.0 * sin((hour - 6.0) / 12.0 * PI)
	sun.rotation_degrees = Vector3(-clampf(elev, -20.0, 80.0), 135.0, 0.0)
	sun.light_color = (p[3] as Color).lerp(overcast, c * 0.7)
	sun.light_energy = p[4] * (1.0 - 0.65 * c)
	sky_mat.sky_top_color = (p[0] as Color).lerp(overcast * 0.6, c * 0.6)
	sky_mat.sky_horizon_color = (p[1] as Color).lerp(overcast, c * 0.5)
	sky_mat.ground_horizon_color = (p[1] as Color).darkened(0.35).lerp(overcast * 0.5, c * 0.5)
	env.fog_light_color = (p[2] as Color).lerp(overcast, c * 0.6)
	env.fog_density = _base_fog_density * (1.0 + 2.2 * c)
	env.ambient_light_energy = p[5] * (1.0 - 0.25 * c) + _flash
	env.adjustment_saturation = 0.92 * (1.0 - 0.25 * c)
	env.glow_intensity = 0.7 + 0.4 * c


func _update_weather(delta: float) -> void:
	_next_change -= delta
	if _next_change <= 0.0:
		_pick_weather()
	var target: float = WEATHER_CLOUD[weather]
	_cloud = move_toward(_cloud, target, delta / TRANSITION)
	if weather == Weather.STORM:
		_lightning_t -= delta
		if _lightning_t <= 0.0:
			_lightning_t = randf_range(4.0, 14.0)
			_flash = 2.2
	_flash = move_toward(_flash, 0.0, delta * 4.0)


func _pick_weather() -> void:
	# transições prováveis: de céu limpo vai para nublado; de chuva pode virar tempestade ou parar
	var roll := randf()
	var next := weather
	match weather:
		Weather.CLEAR:
			next = Weather.OVERCAST if roll < 0.6 else Weather.CLEAR
		Weather.OVERCAST:
			next = Weather.RAIN if roll < 0.5 else (Weather.CLEAR if roll < 0.8 else Weather.OVERCAST)
		Weather.RAIN:
			next = Weather.STORM if roll < 0.3 else (Weather.OVERCAST if roll < 0.7 else Weather.RAIN)
		Weather.STORM:
			next = Weather.RAIN if roll < 0.6 else Weather.STORM
	set_weather(next)


# ------------------------------------------------------------ chuva
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 700 if Game.quality == 0 else (1100 if Game.quality == 1 else 1600)
	_rain.lifetime = 1.1
	_rain.preprocess = 1.0
	_rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	_rain.emitting = false
	_rain.visible = false
	_rain.local_coords = false
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.particle_flag_align_y = true
	_rain_mat.direction = Vector3(0.08, -1.0, 0.04)
	_rain_mat.spread = 3.0
	_rain_mat.initial_velocity_min = 16.0
	_rain_mat.initial_velocity_max = 20.0
	_rain_mat.gravity = Vector3(0, -6.0, 0)
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(38, 1, 38)
	_rain_mat.scale_min = 0.8
	_rain_mat.scale_max = 1.2
	_rain.process_material = _rain_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.9)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.72, 0.8, 0.95, 0.32)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.no_depth_test = false
	quad.material = m
	_rain.draw_pass_1 = quad
	add_child(_rain)


func _update_rain(_delta: float) -> void:
	if _rain == null:
		return
	var want := outdoor and weather >= Weather.RAIN
	_rain.visible = outdoor
	_rain.emitting = want
	if follow_target and is_instance_valid(follow_target):
		_rain.global_position = follow_target.global_position + Vector3(0, 16.0, 0)
