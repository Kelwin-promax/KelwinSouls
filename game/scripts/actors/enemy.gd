# Inimigo genérico (cinemático sobre o heightmap) com IA por estados e ataques procedurais.
class_name Enemy
extends Node3D

signal killed(enemy: Enemy)

enum S { IDLE, PATROL, CHASE, ATTACK, STAGGER, RETURN, DEAD, ROAR }

var model_name := ""
var level := 1
var role := "enemy"            # enemy | elite | boss
var display_name := ""
var spawn_pos := Vector3.ZERO
var rig: ModelRig
var state := S.IDLE
var hp := 300.0
var max_hp := 300.0
var poise := 40.0
var max_poise := 40.0
var damage := 60.0
var walk_speed := 2.2
var run_speed := 4.8
var aggro_range := 20.0
var leash := 50.0
var brasas_value := 80
var turn_speed := 5.0
var size_class := "small"       # small | large | huge
var attacks: Array = []
var hyper_armor := false
var _t := 0.0
var _think := 0.0
var _atk: Dictionary = {}
var _hit_done := false
var _hit_time := 0.0
var _patrol_target := Vector3.ZERO
var _yaw := 0.0
var _prev_yaw := 0.0
var _speed_now := 0.0
var _poise_regen_t := 0.0
var _body: AnimatableBody3D
var _combo_left := 0
var _cooldown := 0.0
var _step_t := 0.0
var _player: Player


# ------------------------------------------------------------ configuração
func setup(p_model: String, p_level: int, p_role: String, pos: Vector3) -> void:
	model_name = p_model
	level = p_level
	role = p_role
	spawn_pos = pos
	position = pos


func _ready() -> void:
	add_to_group("hittable")
	add_to_group("enemies")
	rig = ModelRig.new()
	add_child(rig)
	rig.build(model_name)
	var info := Game.model_info(model_name)
	display_name = info.get("title", model_name)
	var h := rig.height
	size_class = "small" if h < 2.7 else ("large" if h < 4.6 else "huge")
	_configure()
	_yaw = randf() * TAU
	rig.rotation.y = _yaw
	_patrol_target = spawn_pos
	# corpo físico para o jogador não atravessar
	_body = AnimatableBody3D.new()
	_body.collision_layer = 4
	_body.collision_mask = 0
	_body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = rig.radius * 0.8
	cyl.height = rig.height * 0.9
	cs.shape = cyl
	cs.position.y = rig.height * 0.45
	_body.add_child(cs)
	add_child(_body)


func _configure() -> void:
	var lv := 1.0 + 0.45 * (level - 1)
	match size_class:
		"small":
			max_hp = 260.0; damage = 70.0; walk_speed = 2.0; run_speed = 5.2; max_poise = 35.0; turn_speed = 6.0
			attacks = [
				{"kind": "slash", "windup": 0.55, "strike": 0.16, "recover": 0.65, "range": 2.6, "arc": 120.0, "mult": 1.0, "poise": 30.0, "lunge": 3.0},
				{"kind": "slash_r", "windup": 0.45, "strike": 0.16, "recover": 0.6, "range": 2.6, "arc": 120.0, "mult": 1.0, "poise": 30.0, "lunge": 3.0, "combo": true},
				{"kind": "thrust", "windup": 0.7, "strike": 0.15, "recover": 0.8, "range": 3.4, "arc": 50.0, "mult": 1.3, "poise": 40.0, "lunge": 7.0},
				{"kind": "overhead", "windup": 0.85, "strike": 0.16, "recover": 0.9, "range": 2.9, "arc": 70.0, "mult": 1.6, "poise": 60.0, "lunge": 2.0},
			]
		"large":
			max_hp = 620.0; damage = 110.0; walk_speed = 1.8; run_speed = 4.4; max_poise = 90.0; turn_speed = 3.5
			attacks = [
				{"kind": "overhead", "windup": 1.0, "strike": 0.2, "recover": 1.0, "range": 4.0, "arc": 70.0, "mult": 1.4, "poise": 70.0, "lunge": 2.0},
				{"kind": "sweep", "windup": 0.85, "strike": 0.22, "recover": 0.9, "range": 4.2, "arc": 170.0, "mult": 1.0, "poise": 60.0, "lunge": 1.0},
				{"kind": "thrust", "windup": 0.8, "strike": 0.2, "recover": 1.0, "range": 5.0, "arc": 50.0, "mult": 1.2, "poise": 60.0, "lunge": 8.0},
				{"kind": "slam", "windup": 1.2, "strike": 0.2, "recover": 1.2, "range": 4.6, "arc": 360.0, "mult": 1.6, "poise": 90.0, "lunge": 0.0, "aoe": true},
			]
		"huge":
			max_hp = 1200.0; damage = 150.0; walk_speed = 1.6; run_speed = 3.8; max_poise = 180.0; turn_speed = 2.4
			hyper_armor = true
			attacks = [
				{"kind": "slam", "windup": 1.3, "strike": 0.25, "recover": 1.3, "range": 6.0, "arc": 360.0, "mult": 1.5, "poise": 100.0, "lunge": 0.0, "aoe": true},
				{"kind": "sweep", "windup": 1.0, "strike": 0.3, "recover": 1.1, "range": 6.5, "arc": 200.0, "mult": 1.1, "poise": 80.0, "lunge": 1.0},
				{"kind": "overhead", "windup": 1.2, "strike": 0.25, "recover": 1.2, "range": 5.5, "arc": 60.0, "mult": 1.7, "poise": 120.0, "lunge": 2.5},
				{"kind": "spin", "windup": 0.9, "strike": 0.35, "recover": 1.2, "range": 6.0, "arc": 360.0, "mult": 1.0, "poise": 80.0, "lunge": 0.0},
			]
	if role == "elite":
		max_hp *= 1.6; damage *= 1.15; max_poise *= 1.4
	max_hp *= lv
	damage *= 1.0 + 0.25 * (level - 1)
	hp = max_hp
	poise = max_poise
	brasas_value = int((60 + 30 * level) * (1.0 if size_class == "small" else 2.2 if size_class == "large" else 4.0) * (1.6 if role == "elite" else 1.0))
	aggro_range = 20.0 + rig.height * 2.0


# ------------------------------------------------------------ interface "hittable"
func is_dead() -> bool:
	return state == S.DEAD


func get_radius() -> float:
	return rig.radius


func get_height() -> float:
	return rig.height


func take_hit(dmg: float, from: Vector3, poise_dmg: float) -> void:
	if state == S.DEAD:
		return
	hp -= dmg
	poise -= poise_dmg
	_poise_regen_t = 3.0
	rig.flash()
	var hp_pos := global_position + Vector3(0, rig.height * 0.6, 0)
	FX.blood(get_tree().current_scene, hp_pos)
	Sfx.play_at("hit_flesh" if size_class == "small" else "hit_heavy", hp_pos, 0)
	if randf() < 0.5:
		Sfx.play_at("enemy_hurt", hp_pos, -6, 0.2)
	if state in [S.IDLE, S.PATROL, S.RETURN]:
		_aggro()
	if hp <= 0.0:
		_die()
		return
	if poise <= 0.0:
		poise = max_poise
		_stagger(1.3)
	elif not hyper_armor and state != S.ATTACK and size_class == "small":
		_stagger(0.35)
	_on_damaged()


func _on_damaged() -> void:
	pass


func _stagger(dur: float) -> void:
	state = S.STAGGER
	_t = -dur
	rig.hit_motion(_player.global_position - global_position if _player else Vector3.FORWARD, 1.4 if dur > 1.0 else 0.8)
	if dur > 1.0:
		Sfx.play_at("parry", global_position + Vector3(0, rig.height * 0.5, 0), -3)


func _aggro() -> void:
	if state == S.DEAD:
		return
	state = S.CHASE
	_t = 0.0


func _die() -> void:
	state = S.DEAD
	hp = 0.0
	remove_from_group("hittable")
	if _body:
		_body.queue_free()
		_body = null
	rig.death_motion()
	Sfx.play_at("enemy_death", global_position + Vector3(0, 1, 0), 0)
	Game.add_brasas(brasas_value)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_callback(func(): FX.embers(get_tree().current_scene, global_position + Vector3(0, rig.height * 0.3, 0), int(40 + rig.height * 20), rig.radius * 1.5))
	tw.tween_property(rig, "scale", Vector3(1, 0.02, 1), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	killed.emit(self)


# ------------------------------------------------------------ IA
func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	_player = Game.player as Player
	_t += delta
	_cooldown -= delta
	if _poise_regen_t > 0.0:
		_poise_regen_t -= delta
	else:
		poise = min(max_poise, poise + max_poise * 0.3 * delta)
	var to_p := Vector3.ZERO
	var dist := INF
	if _player and not _player.is_dead():
		to_p = _player.global_position - global_position
		to_p.y = 0
		dist = to_p.length()
	var move := Vector3.ZERO
	match state:
		S.IDLE:
			if _t > randf_range(2.0, 6.0):
				state = S.PATROL
				_t = 0.0
				var a := randf() * TAU
				_patrol_target = spawn_pos + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 10.0)
			_check_aggro(dist)
		S.PATROL:
			var d := _patrol_target - global_position
			d.y = 0
			if d.length() < 1.0 or _t > 10.0:
				state = S.IDLE
				_t = 0.0
			else:
				move = d.normalized() * walk_speed * 0.6
				_turn_to(d, delta)
			_check_aggro(dist)
		S.CHASE:
			if _player == null or _player.is_dead() or global_position.distance_to(spawn_pos) > leash:
				state = S.RETURN
				_t = 0.0
			else:
				_turn_to(to_p, delta)
				var reach := _closest_attack_range()
				if dist > reach + _player.get_radius() + rig.radius * 0.3:
					var spd := run_speed if dist > 7.0 else walk_speed * 1.4
					move = to_p.normalized() * spd
				elif dist < rig.radius + 0.8:
					move = -to_p.normalized() * walk_speed * 0.6
				else:
					# rodeia o jogador um pouco
					move = to_p.normalized().cross(Vector3.UP) * walk_speed * 0.5 * (1.0 if int(_t * 0.3) % 2 == 0 else -1.0)
				if _cooldown <= 0.0 and _t > 0.4:
					_choose_attack(dist)
		S.ATTACK:
			_update_attack(delta, to_p)
			if _atk.size() > 0 and _t > _atk.windup and _t < _atk.windup + _atk.strike:
				move = -rig.global_transform.basis.z * _atk.lunge
		S.STAGGER:
			if _t >= 0.0:
				state = S.CHASE
				_t = 0.0
		S.RETURN:
			var d := spawn_pos - global_position
			d.y = 0
			if d.length() < 1.5:
				state = S.IDLE
				hp = max_hp
				_t = 0.0
			else:
				move = d.normalized() * run_speed * 0.8
				_turn_to(d, delta)
			if dist < aggro_range * 0.6:
				_aggro()
		S.ROAR:
			if _t >= 1.8:
				state = S.CHASE
				_t = 0.0
	_apply_move(move, delta)
	var turn: float = wrapf(_yaw - _prev_yaw, -PI, PI) / max(delta, 0.0001)
	_prev_yaw = _yaw
	if state != S.ATTACK:
		rig.tick(delta, clampf(_speed_now / run_speed, 0.0, 1.0), turn)
		if rig.anim:
			_drive_anim()


func _drive_anim() -> void:
	# modelos com esqueleto (rigged) têm a locomoção dirigida pelo ModelRig
	if rig.rigged:
		return
	rig.play_anim(["take", "idle", "stand"], 1.0 + clampf(_speed_now / run_speed, 0.0, 1.0))


func _check_aggro(dist: float) -> void:
	if dist < aggro_range:
		_aggro()


func _closest_attack_range() -> float:
	var r := INF
	for a in attacks:
		r = min(r, a.range)
	return r * 0.85


func _choose_attack(dist: float) -> void:
	var options := []
	for a in attacks:
		if dist <= a.range + _player.get_radius() + 0.4:
			options.append(a)
	if options.is_empty():
		return
	_start_attack(options[randi() % options.size()])


func _start_attack(a: Dictionary) -> void:
	_atk = a
	state = S.ATTACK
	_t = 0.0
	_hit_done = false
	var speed_mult := attack_speed_mult()
	_atk = a.duplicate()
	_atk.windup /= speed_mult
	_atk.recover /= speed_mult
	_hit_time = rig.attack_motion(_atk.kind, _atk.windup, _atk.strike, _atk.recover, 1.0) - _atk.strike * 0.5
	var sname := "swing_light" if size_class == "small" else ("swing_heavy" if size_class == "large" else "swing_big")
	get_tree().create_timer(max(_atk.windup - 0.15, 0.0)).timeout.connect(func():
		if is_instance_valid(self) and state == S.ATTACK:
			Sfx.play_at(sname, global_position, -2))
	_combo_left = 1 if randf() < 0.45 else 0


func attack_speed_mult() -> float:
	return 1.0


func _update_attack(delta: float, to_p: Vector3) -> void:
	if _t < _atk.windup * 0.75 and to_p.length() > 0.1:
		_turn_to(to_p, delta * 0.8)
	if not _hit_done and _t >= _hit_time:
		_hit_done = true
		_resolve_hit()
	if _t >= _atk.windup + _atk.strike + _atk.recover:
		state = S.CHASE
		_t = 0.0
		_cooldown = randf_range(0.3, 1.4) if size_class != "small" else randf_range(0.6, 1.8)
		if _combo_left > 0 and _player and _player.global_position.distance_to(global_position) < _closest_attack_range() * 1.6:
			_combo_left -= 1
			_cooldown = 0.0
			_choose_attack(_player.global_position.distance_to(global_position))


func _resolve_hit() -> void:
	var fwd := -rig.global_transform.basis.z
	var origin := global_position + Vector3(0, rig.height * 0.5, 0)
	var roll := 0.3
	match _atk.kind:
		"overhead", "slam": roll = PI * 0.5
		"slash_r": roll = -0.3
		"sweep": roll = 0.05
	if _atk.get("aoe", false):
		var center := global_position + fwd * rig.radius * 1.2
		FX.burst(get_tree().current_scene, center + Vector3(0, 0.2, 0), Color(0.8, 0.6, 0.4), 60, 9.0, 0.25, 0.7, -10.0)
		Sfx.play_at("hit_heavy", center, 2)
		if Game.player and Game.player.cam and Game.player.global_position.distance_to(center) < 25.0:
			Game.player.cam.shake(0.4, 0.3)
	else:
		FX.slash(get_tree().current_scene, Transform3D(rig.global_transform.basis, origin), _atk.range, roll, Color(1.0, 0.35, 0.2), _atk.kind == "slash_r")
	if _player == null or _player.is_dead():
		return
	var to := _player.global_position - global_position
	var dy := to.y
	to.y = 0
	var dist := to.length() - _player.get_radius()
	if dist > _atk.range + rig.radius * 0.3 or absf(dy) > rig.height:
		return
	if _atk.arc < 359.0 and to.length() > 0.01 and rad_to_deg(fwd.angle_to(to.normalized())) > _atk.arc * 0.5:
		return
	_player.take_hit(damage * _atk.mult, global_position, _atk.poise)


func _turn_to(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	_yaw = lerp_angle(_yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-delta * turn_speed))
	rig.rotation.y = _yaw


func _apply_move(move: Vector3, delta: float) -> void:
	# separação entre inimigos
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self or o.is_dead():
			continue
		var d: Vector3 = global_position - o.global_position
		d.y = 0
		var min_d: float = rig.radius + o.get_radius()
		if d.length() < min_d and d.length() > 0.01:
			move += d.normalized() * (min_d - d.length()) * 4.0
	# não atravessar o jogador
	if _player:
		var d := global_position - _player.global_position
		d.y = 0
		var min_d := rig.radius + 0.45
		if d.length() < min_d and d.length() > 0.01:
			move += d.normalized() * (min_d - d.length()) * 6.0
	var np := global_position + move * delta
	# dentro de masmorra, o inimigo não atravessa as paredes
	if Game.dungeon_active and Game.dungeon and not Game.dungeon.is_walkable(np):
		np = global_position
	var gy: float = Game.ground_y(np.x, np.z)
	# evita subir paredões
	if gy - global_position.y > 2.0 * delta * max(move.length(), 1.0) + 0.6 and state != S.ATTACK:
		np = global_position
		gy = global_position.y
	np.y = lerpf(global_position.y, gy, 1.0 - exp(-delta * 20.0))
	_speed_now = Vector2(np.x - global_position.x, np.z - global_position.z).length() / max(delta, 0.0001)
	global_position = np
	if _body:
		_body.global_position = global_position
	if _speed_now > 0.6:
		_step_t -= delta * _speed_now
		if _step_t <= 0.0:
			_step_t = 2.2 * max(rig.height * 0.5, 1.0)
			if _player and _player.global_position.distance_to(global_position) < 30.0:
				Sfx.play_at("step_stone_%d" % (randi() % 3), global_position, -10 + rig.height, 0.15, 30.0 + rig.height * 4)
