# Dragões. Dois comportamentos:
#  - "ground" (Dragão Ancestral): chefe terrestre com animações reais do modelo.
#  - "sky"    (Kelvhar): voa em círculos e faz rasantes cuspindo fogo; vulnerável ao pairar.
class_name Dragon
extends Boss

var mode := "ground"
var _sky_state := "circle"
var _sky_t := 0.0
var _orbit_angle := 0.0
var _altitude := 60.0
var _breath: CPUParticles3D
var _breath_active := false
var _anim_lock := 0.0

const GROUND_ATTACKS := [
	{"anim": "Battle_Attack01", "kind": "anim", "windup": 0.9, "strike": 0.3, "recover": 1.2, "range": 9.0, "arc": 120.0, "mult": 1.3, "poise": 90.0, "lunge": 2.0},
	{"anim": "Battle_Attack02", "kind": "anim", "windup": 0.8, "strike": 0.3, "recover": 1.2, "range": 9.0, "arc": 160.0, "mult": 1.2, "poise": 90.0, "lunge": 1.0},
	{"anim": "Battle_Attack03", "kind": "anim", "windup": 1.0, "strike": 0.3, "recover": 1.4, "range": 11.0, "arc": 90.0, "mult": 1.5, "poise": 110.0, "lunge": 4.0},
	{"anim": "Battle_Attack04", "kind": "anim", "windup": 1.0, "strike": 0.4, "recover": 1.4, "range": 10.0, "arc": 360.0, "mult": 1.1, "poise": 90.0, "lunge": 0.0},
	{"anim": "Battle_Skill01", "kind": "breath", "windup": 1.0, "strike": 2.2, "recover": 1.2, "range": 22.0, "arc": 40.0, "mult": 0.35, "poise": 30.0, "lunge": 0.0},
]


func setup_dragon(data: Dictionary, p_mode: String) -> void:
	mode = p_mode
	boss_id = data.id
	arena_radius = 80.0 if mode == "ground" else 140.0
	is_great = false
	title = data.title
	setup(data.model, 6, "boss", Vector3(data.pos[0], data.pos[1], data.pos[2]))


func _ready() -> void:
	super._ready()
	max_hp = 9000.0 if mode == "ground" else 6000.0
	hp = max_hp
	max_poise = 400.0
	poise = max_poise
	damage = 190.0
	hyper_armor = true
	brasas_value = 40000
	aggro_range = 50.0 if mode == "ground" else 120.0
	if mode == "ground":
		attacks = GROUND_ATTACKS.duplicate(true)
		rig.play_anim(["Battle_Stand"])
	else:
		_altitude = 55.0
		rig.play_anim(["flightTest", "angryFlightPose"])
	_breath = FX.flame(Color(1.0, 0.45, 0.15), 160, 1.6, 18.0)
	_breath.emitting = false
	_breath.spread = 14.0
	_breath.lifetime = 0.8
	_breath.local_coords = false
	add_child(_breath)
	_fog.visible = false


func _aggro() -> void:
	if mode == "sky":
		if not fight_active:
			fight_active = true
			if Game.hud:
				Game.hud.show_boss(self)
			Sfx.play_music("music_boss", 1.0)
			Sfx.play_at("dragon_roar", global_position, 10, 0.05, 400.0)
		return
	if not fight_active:
		rig.play_anim(["Neutural_Roar"])
		Sfx.play_at("dragon_roar", global_position, 8, 0.05, 300.0)
	super._aggro()


func _physics_process(delta: float) -> void:
	if mode == "sky":
		_sky_process(delta)
		return
	super._physics_process(delta)
	_drive_ground_anim()


func _drive_ground_anim() -> void:
	if state == S.DEAD:
		return
	if state == S.ATTACK:
		return
	if state == S.STAGGER:
		rig.play_anim(["Damage_GroggyLoop", "Groggy"])
	elif state == S.ROAR:
		rig.play_anim(["Neutural_Roar"])
	elif _speed_now > 0.8:
		rig.play_anim(["Battle_Walk"], clampf(_speed_now / walk_speed, 0.6, 2.0))
	else:
		rig.play_anim(["Battle_Stand"])


func _start_attack(a: Dictionary) -> void:
	if mode != "ground":
		return
	_atk = a.duplicate()
	state = S.ATTACK
	_t = 0.0
	_hit_done = false
	rig.play_anim([a.anim], attack_speed_mult(), 0.15)
	if rig.anim and rig.anim.current_animation != "":
		var L := rig.anim.current_animation_length / attack_speed_mult()
		_atk.windup = L * 0.45
		_atk.strike = L * 0.15 if a.kind != "breath" else L * 0.45
		_atk.recover = L * 0.4 if a.kind != "breath" else L * 0.1
	_hit_time = _atk.windup
	if a.kind == "breath":
		get_tree().create_timer(_atk.windup).timeout.connect(_start_breath)
	else:
		get_tree().create_timer(_atk.windup * 0.6).timeout.connect(func():
			if is_instance_valid(self): Sfx.play_at("swing_big", global_position, 4, 0.05, 80.0))


func _update_attack(delta: float, to_p: Vector3) -> void:
	if _atk.kind == "breath":
		if _t < _atk.windup + _atk.strike:
			_turn_to(to_p, delta * 0.5)
			if _t > _atk.windup:
				_breath_damage(delta)
		else:
			_stop_breath()
		if _t >= _atk.windup + _atk.strike + _atk.recover:
			state = S.CHASE
			_t = 0.0
			_cooldown = 1.5
		return
	super._update_attack(delta, to_p)


func _head_transform() -> Transform3D:
	var fwd := -rig.global_transform.basis.z
	var p := global_position + Vector3(0, rig.height * 0.55, 0) + fwd * (rig.radius * 1.6)
	return Transform3D(rig.global_transform.basis, p)


func _start_breath() -> void:
	if not is_instance_valid(self) or state == S.DEAD:
		return
	_breath_active = true
	_breath.emitting = true
	Sfx.play_at("dragon_breath", global_position, 8, 0.05, 150.0)


func _stop_breath() -> void:
	_breath_active = false
	_breath.emitting = false


func _breath_damage(delta: float) -> void:
	var ht := _head_transform()
	_breath.global_transform = Transform3D(Basis.looking_at(-ht.basis.z + Vector3(0, -0.45, 0), Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5), ht.origin)
	if _player == null or _player.is_dead():
		return
	var to := _player.global_position + Vector3(0, 1, 0) - ht.origin
	var fwd := (-ht.basis.z + Vector3(0, -0.45, 0)).normalized()
	if to.length() < _atk.range and rad_to_deg(fwd.angle_to(to.normalized())) < _atk.arc * 0.5:
		_player.take_hit(damage * _atk.mult * delta * 4.0, global_position, 5.0)


# ------------------------------------------------------------ voo (Kelvhar)
func _sky_process(delta: float) -> void:
	if state == S.DEAD:
		return
	_player = Game.player as Player
	_sky_t += delta
	var center := spawn_pos
	var dist_p := INF
	if _player and not _player.is_dead():
		dist_p = Vector2(_player.global_position.x - center.x, _player.global_position.z - center.z).length()
	if not fight_active and dist_p < aggro_range:
		_aggro()
	if fight_active and (dist_p > arena_radius * 2.0 or _player == null or _player.is_dead()):
		fight_active = false
		_sky_state = "circle"
		if Game.hud:
			Game.hud.hide_boss()
		Sfx.play_music("music_explore", 3.0)
	var target: Vector3
	match _sky_state:
		"circle":
			_orbit_angle += delta * 0.18
			target = center + Vector3(cos(_orbit_angle) * 110.0, _altitude + 20.0, sin(_orbit_angle) * 110.0)
			target.y = Game.terrain.height_at(target.x, target.z) + _altitude
			rig.play_anim(["flightTest"])
			if fight_active and _sky_t > 9.0:
				_sky_state = "dive"
				_sky_t = 0.0
		"dive":
			target = _player.global_position + (global_position - _player.global_position).normalized() * 18.0
			target.y = Game.terrain.height_at(target.x, target.z) + 7.0
			rig.play_anim(["angryFlightPose"])
			if global_position.distance_to(target) < 6.0 or _sky_t > 6.0:
				_sky_state = "hover"
				_sky_t = 0.0
				Sfx.play_at("dragon_roar", global_position, 8, 0.05, 300.0)
		"hover":
			target = global_position
			var gy: float = Game.terrain.height_at(global_position.x, global_position.z)
			target.y = gy + 6.0
			rig.play_anim(["flight_fire", "angryFlightPose"])
			if _sky_t > 1.0 and _sky_t < 5.0:
				if not _breath_active:
					_atk = {"range": 26.0, "arc": 40.0, "mult": 0.35}
					_start_breath()
				_breath_damage(delta)
			elif _breath_active:
				_stop_breath()
			if _sky_t > 8.0:
				_sky_state = "circle"
				_sky_t = 0.0
	var to_t := target - global_position
	var spd := 22.0 if _sky_state != "hover" else 4.0
	global_position += to_t.limit_length(spd * delta)
	if _player and _sky_state == "hover":
		_turn_to(_player.global_position - global_position, delta)
	elif to_t.length() > 0.5:
		_turn_to(Vector3(to_t.x, 0, to_t.z), delta * 0.6)


func get_height() -> float:
	return rig.height if mode == "ground" else rig.height + 8.0


func _die() -> void:
	_stop_breath()
	if mode == "ground":
		rig.play_anim(["DaenerysDragon_Death"], 1.0, 0.2)
	else:
		var tw := create_tween()
		tw.tween_property(self, "global_position:y", Game.terrain.height_at(global_position.x, global_position.z), 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	super._die()
