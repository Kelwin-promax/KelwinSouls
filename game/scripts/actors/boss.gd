# Chefe: arena com muralha de névoa, barra de vida, fase 2, rugido, Grande Brasa.
class_name Boss
extends Enemy

signal defeated(boss: Boss)

var boss_id := ""
var arena_radius := 45.0
var is_great := false
var title := ""
var phase := 1
var fight_active := false
var _fog: MeshInstance3D
var _intro_done := false

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.55, 1.0);
void fragment() {
	float n = sin(UV.x * 140.0 + TIME * 1.3) * 0.5 + sin(UV.x * 57.0 - TIME * 0.7 + UV.y * 9.0) * 0.5;
	float fade = smoothstep(0.0, 0.15, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	ALBEDO = tint.rgb;
	ALPHA = clamp((0.25 + n * 0.12) * fade, 0.0, 1.0);
}
"""


func setup_boss(data: Dictionary) -> void:
	boss_id = data.id
	arena_radius = float(data.arena)
	is_great = bool(data.great)
	title = data.title
	setup(data.model, int(data.level), "boss", Vector3(data.pos[0], data.pos[1], data.pos[2]))


func _ready() -> void:
	super._ready()
	remove_from_group("enemies")
	add_to_group("bosses")
	add_to_group("enemies")
	display_name = title
	var mult := 7.0 if size_class == "small" else (4.5 if size_class == "large" else 3.2)
	max_hp *= mult
	hp = max_hp
	max_poise *= 2.5
	poise = max_poise
	damage *= 1.25
	hyper_armor = size_class != "small"
	brasas_value = int(2500 * level * (2.0 if is_great else 1.0))
	aggro_range = arena_radius * 0.7
	leash = arena_radius * 1.6
	# chefes ganham ataques extras
	attacks.append({"kind": "spin", "windup": 0.7, "strike": 0.3, "recover": 0.9, "range": rig.radius + rig.height * 0.6, "arc": 360.0, "mult": 1.2, "poise": 70.0, "lunge": 0.0})
	attacks.append({"kind": "thrust", "windup": 0.5, "strike": 0.2, "recover": 1.0, "range": rig.radius + rig.height * 1.4, "arc": 40.0, "mult": 1.4, "poise": 80.0, "lunge": 12.0})
	_make_fog()


func _make_fog() -> void:
	_fog = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = arena_radius
	cyl.bottom_radius = arena_radius
	cyl.height = 40.0
	cyl.radial_segments = 96
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_fog.mesh = cyl
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	sm.shader = sh
	_fog.material_override = sm
	_fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog.visible = false
	add_child(_fog)
	_fog.top_level = true
	_fog.global_position = spawn_pos + Vector3(0, 12, 0)


var required_embers := 0
var _deny_t := 0.0


func _check_aggro(dist: float) -> void:
	if _player == null:
		return
	var d := _player.global_position - spawn_pos
	d.y = 0
	if Game.great_embers.size() < required_embers:
		# barreira dourada: exige Grandes Brasas
		_fog.visible = d.length() < arena_radius + 30.0
		if d.length() < arena_radius + 1.5:
			var p := spawn_pos + d.normalized() * (arena_radius + 1.5)
			_player.global_position.x = p.x
			_player.global_position.z = p.z
			if Time.get_ticks_msec() / 1000.0 > _deny_t:
				_deny_t = Time.get_ticks_msec() / 1000.0 + 4.0
				Game.message("Uma força dourada o repele. São necessárias %d Grandes Brasas." % required_embers, "small")
		return
	if d.length() < arena_radius * 0.85:
		_aggro()


func _aggro() -> void:
	if state == S.DEAD or fight_active:
		if fight_active and state != S.DEAD and state != S.ROAR:
			super._aggro()
		return
	fight_active = true
	_fog.visible = true
	Sfx.play_at("fog_gate", global_position, 0)
	Sfx.play_music("music_boss", 1.0)
	if Game.hud:
		Game.hud.show_boss(self)
	state = S.ROAR
	_t = 0.0
	rig.roar_motion(1.8)
	Sfx.play_at("boss_roar", global_position + Vector3(0, rig.height * 0.7, 0), 4, 0.05, 120.0)
	if _player and _player.cam:
		_player.cam.shake(0.25, 1.2)
		_player.cam.set_extra_distance(clampf(rig.height * 0.5, 0.0, 5.0))
	if Game.main and Game.main.has_method("play_boss_intro"):
		Game.main.play_boss_intro(self)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if fight_active and state != S.DEAD and _player and not _player.is_dead():
		# mantém o jogador dentro da arena
		var d := _player.global_position - spawn_pos
		d.y = 0
		if d.length() > arena_radius - 1.0:
			var p := spawn_pos + d.normalized() * (arena_radius - 1.0)
			_player.global_position.x = p.x
			_player.global_position.z = p.z
		# chefe não sai da arena
		var b := global_position - spawn_pos
		b.y = 0
		if b.length() > arena_radius - rig.radius:
			var q := spawn_pos + b.normalized() * (arena_radius - rig.radius)
			global_position.x = q.x
			global_position.z = q.z
		if state == S.RETURN:
			state = S.CHASE


func attack_speed_mult() -> float:
	return 1.0 if phase == 1 else 1.3


func _on_damaged() -> void:
	if Game.hud:
		Game.hud.update_boss(hp, max_hp)
	if phase == 1 and hp < max_hp * 0.5:
		phase = 2
		damage *= 1.15
		run_speed *= 1.2
		turn_speed *= 1.3
		state = S.ROAR
		_t = 0.0
		rig.roar_motion(1.8)
		Sfx.play_at("boss_roar", global_position + Vector3(0, rig.height * 0.7, 0), 6, 0.05, 120.0)
		FX.embers(get_tree().current_scene, global_position + Vector3(0, rig.height * 0.5, 0), 120, rig.radius * 2.0)
		var aura := OmniLight3D.new()
		aura.light_color = Color(1.0, 0.3, 0.15)
		aura.light_energy = 2.0
		aura.omni_range = rig.height * 2.0
		aura.position.y = rig.height * 0.6
		add_child(aura)


func _die() -> void:
	super._die()
	fight_active = false
	_fog.visible = false
	if Game.hud:
		Game.hud.hide_boss()
		Game.hud.big_banner("GRANDE INIMIGO ABATIDO", Color(1.0, 0.82, 0.45))
	Sfx.play("enemy_felled", 0, 0.0)
	Sfx.play_music("music_explore", 4.0)
	if _player and _player.cam:
		_player.cam.set_extra_distance(0.0)
		_player.cam.release_lock()
	if not Game.defeated_bosses.has(boss_id):
		Game.defeated_bosses.append(boss_id)
	if is_great and not Game.great_embers.has(boss_id):
		Game.great_embers.append(boss_id)
		get_tree().create_timer(4.5).timeout.connect(func():
			Game.message("Grande Brasa de %s obtida" % title.split(",")[0], "item"))
	Game.flasks_max = min(Game.flasks_max + 1, 12)
	Game.save_game()
	defeated.emit(self)


func reset_fight() -> void:
	fight_active = false
	_fog.visible = false
	phase = 1
	hp = max_hp
	poise = max_poise
	global_position = spawn_pos
	state = S.IDLE
	_t = 0.0
	rig.new_tween().kill()
	rig.pose.rotation = Vector3.ZERO
	rig.pose.position = Vector3.ZERO
