# O Maculado das Cinzas (jogador): movimento, esquiva, combate, frascos, morte.
class_name Player
extends CharacterBody3D

signal died
signal hp_changed(hp: float, max_hp: float)
signal stamina_changed(st: float, max_st: float)

enum State { FREE, ATTACK, ROLL, STAGGER, DRINK, DEAD, REST, BACKSTEP }

const WALK := 4.6
const SPRINT := 7.4
const ROLL_SPEED := 8.8
const ROLL_TIME := 0.62
const IFRAME_START := 0.05
const IFRAME_END := 0.42
const GRAVITY := 22.0
const JUMP_V := 8.0

var model_name := "ravenkor__the_bloodsteel_duelist"
var rig: ModelRig
var cam: Node  # CameraRig
var state := State.FREE
var hp := 420.0
var stamina := 90.0
var _stamina_delay := 0.0
var _state_t := 0.0
var _invuln := false
var _guarding := false
var _combo := 0
var _queued_attack := ""
var _attack_hit_done := false
var _attack_hit_time := 0.0
var _attack_data: Dictionary = {}
var _dodge_held := 0.0
var _move_dir := Vector3.ZERO
var _roll_dir := Vector3.FORWARD
var _yaw := 0.0
var _prev_yaw := 0.0
var _step_t := 0.0
var _was_floor := true
var _drink_healed := false
var _in_water := false
var lock_target: Node3D = null

const ATTACKS := {
	"light": {"kind": "slash", "windup": 0.16, "strike": 0.12, "recover": 0.34, "dmg": 62.0, "range": 2.9, "arc": 150.0, "stamina": 15.0, "poise": 18.0, "lunge": 3.5, "sound": "swing_light"},
	"light2": {"kind": "slash_r", "windup": 0.13, "strike": 0.12, "recover": 0.34, "dmg": 66.0, "range": 2.9, "arc": 150.0, "stamina": 15.0, "poise": 18.0, "lunge": 3.5, "sound": "swing_light"},
	"light3": {"kind": "thrust", "windup": 0.18, "strike": 0.12, "recover": 0.45, "dmg": 78.0, "range": 3.4, "arc": 60.0, "stamina": 17.0, "poise": 24.0, "lunge": 6.0, "sound": "swing_light"},
	"heavy": {"kind": "overhead", "windup": 0.42, "strike": 0.14, "recover": 0.5, "dmg": 120.0, "range": 3.2, "arc": 90.0, "stamina": 28.0, "poise": 55.0, "lunge": 2.5, "sound": "swing_heavy"},
	"run": {"kind": "thrust", "windup": 0.1, "strike": 0.14, "recover": 0.45, "dmg": 80.0, "range": 3.4, "arc": 70.0, "stamina": 18.0, "poise": 30.0, "lunge": 7.5, "sound": "swing_heavy"},
	"jump": {"kind": "overhead", "windup": 0.12, "strike": 0.14, "recover": 0.45, "dmg": 105.0, "range": 3.0, "arc": 110.0, "stamina": 22.0, "poise": 50.0, "lunge": 2.0, "sound": "swing_heavy"},
}


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.6
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	rig = ModelRig.new()
	add_child(rig)
	rig.build(model_name)
	hp = Game.max_hp()
	stamina = Game.max_stamina()
	Game.player = self


func is_dead() -> bool:
	return state == State.DEAD


func is_busy() -> bool:
	return state != State.FREE


# ------------------------------------------------------------ entrada
func _unhandled_input(event: InputEvent) -> void:
	if state == State.DEAD or state == State.REST:
		return
	if event.is_action_pressed("mount"):
		_toggle_mount()
		return
	if Game.mounted:
		return   # montado: só o cavalo se move, sem golpes, rolamentos ou pulos
	if event.is_action_pressed("attack"):
		_request_attack("heavy" if Input.is_action_pressed("heavy_attack") else "light")
	elif event.is_action_pressed("heavy_attack") and event is InputEventJoypadMotion:
		_request_attack("heavy")
	elif event.is_action_pressed("use_flask"):
		_try_drink()
	elif event.is_action_pressed("jump"):
		if is_on_floor() and state == State.FREE:
			velocity.y = JUMP_V
			Sfx.play_at("jump", global_position, -6)
	elif event.is_action_released("dodge"):
		if _dodge_held < 0.28:
			_try_roll()
		_dodge_held = 0.0


func _toggle_mount() -> void:
	if Game.mounted:
		_dismount()
		return
	var h = Game.horse
	if h == null or not is_instance_valid(h) or state != State.FREE or not is_on_floor():
		return
	if global_position.distance_to(h.global_position) > 3.5:
		Game.message("Aproxime-se do cavalo para montar", "small")
		return
	Game.mounted = true
	velocity = Vector3.ZERO
	h.mount_by(self)
	Sfx.play_at("roll", global_position, -8)


func _dismount() -> void:
	Game.mounted = false
	var h = Game.horse
	var side := Vector3.RIGHT
	if h and is_instance_valid(h):
		side = h.global_transform.basis.x
		h.dismount()
	global_position += side * 1.6
	global_position.y = Game.ground_height(global_position.x, global_position.z) + 0.3
	rig.position.y = 0.0
	velocity = Vector3.ZERO


func _mounted_tick(delta: float, input: Vector2, cam_basis: Basis) -> void:
	var h = Game.horse
	if h == null or not is_instance_valid(h):
		Game.mounted = false
		rig.position.y = 0.0
		return
	h.drive(delta, input, cam_basis)
	global_position = h.global_position
	velocity = Vector3.ZERO
	_yaw = h.rotation.y
	rig.rotation.y = _yaw
	rig.position.y = lerpf(rig.position.y, h.saddle_height(), 1.0 - exp(-delta * 8.0))
	rig.tick(delta, h.speed01(), 0.0, true)


func _request_attack(kind: String) -> void:
	if state == State.ATTACK:
		if _state_t > _attack_data.get("windup", 0.0) + _attack_data.get("strike", 0.0) * 0.5:
			_queued_attack = kind
		return
	if state != State.FREE or stamina <= 1.0:
		return
	if kind == "light":
		if not is_on_floor():
			kind = "jump"
		elif _is_sprinting():
			kind = "run"
		else:
			kind = ["light", "light2", "light3"][_combo % 3]
	_start_attack(kind)


func _start_attack(kind: String) -> void:
	_attack_data = ATTACKS[kind]
	state = State.ATTACK
	_state_t = 0.0
	_attack_hit_done = false
	_use_stamina(_attack_data.stamina)
	if lock_target and is_instance_valid(lock_target):
		_face_towards(lock_target.global_position, 1.0)
	elif _move_dir.length() > 0.1:
		_yaw = atan2(-_move_dir.x, -_move_dir.z)
		rig.rotation.y = _yaw
	var hit_t := rig.attack_motion(_attack_data.kind, _attack_data.windup, _attack_data.strike, _attack_data.recover)
	_attack_hit_time = hit_t - _attack_data.strike * 0.5
	if kind.begins_with("light"):
		_combo += 1
	get_tree().create_timer(_attack_data.windup * 0.8).timeout.connect(func(): Sfx.play_at(_attack_data.sound, global_position, -2))


func _try_roll() -> void:
	if state != State.FREE and not (state == State.ATTACK and _state_t > _attack_data.windup + _attack_data.strike):
		return
	if stamina <= 1.0 or not is_on_floor():
		return
	_use_stamina(20.0)
	state = State.ROLL
	_state_t = 0.0
	_combo = 0
	if _move_dir.length() > 0.1:
		_roll_dir = _move_dir.normalized()
	else:
		_roll_dir = rig.global_transform.basis.z  # passo para trás
		state = State.BACKSTEP
	if state == State.ROLL:
		_yaw = atan2(-_roll_dir.x, -_roll_dir.z)
		rig.rotation.y = _yaw
		rig.roll_motion(ROLL_TIME * 0.9)
	Sfx.play_at("roll", global_position, -4)


func _try_drink() -> void:
	if state != State.FREE or not is_on_floor():
		return
	if Game.flasks <= 0:
		Game.message("Sem Lágrimas Ígneas", "small")
		return
	Game.flasks -= 1
	Game.flasks_changed.emit(Game.flasks)
	state = State.DRINK
	_state_t = 0.0
	_drink_healed = false
	rig.drink_motion(1.1)


func _is_sprinting() -> bool:
	return (Input.is_action_pressed("sprint") or _dodge_held >= 0.28) and _move_dir.length() > 0.1 and stamina > 0.5


# ------------------------------------------------------------ física
func _physics_process(delta: float) -> void:
	_state_t += delta
	if Input.is_action_pressed("dodge"):
		_dodge_held += delta
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis: Basis = cam.get_yaw_basis() if cam else Basis.IDENTITY
	_move_dir = (cam_basis * Vector3(input.x, 0, input.y))
	_move_dir.y = 0
	if state in [State.DEAD, State.REST]:
		_move_dir = Vector3.ZERO
	if Game.mounted and state != State.DEAD:
		_mounted_tick(delta, input, cam_basis)
		return
	_in_water = not Game.dungeon_active and global_position.y < Game.world.water - 0.3

	var hvel := Vector3(velocity.x, 0, velocity.z)
	var target_vel := Vector3.ZERO
	_guarding = false
	match state:
		State.FREE:
			var spd := WALK * clampf(input.length(), 0.0, 1.0)
			if _is_sprinting():
				spd = SPRINT
			if _in_water:
				spd *= 0.6
			if Input.is_action_pressed("guard"):
				_guarding = true
				spd *= 0.45
			target_vel = _move_dir.normalized() * spd if _move_dir.length() > 0.05 else Vector3.ZERO
			if _is_sprinting():
				_use_stamina(14.0 * delta, 0.3)
			if lock_target and is_instance_valid(lock_target) and not _is_sprinting():
				_face_towards(lock_target.global_position, delta * 10.0)
			elif _move_dir.length() > 0.05:
				_yaw = lerp_angle(_yaw, atan2(-_move_dir.x, -_move_dir.z), 1.0 - exp(-delta * 12.0))
				rig.rotation.y = _yaw
			_combo = 0 if _state_t > 0.6 else _combo
		State.ATTACK:
			var fwd := -rig.global_transform.basis.z
			var t := _state_t
			if t > _attack_data.windup and t < _attack_data.windup + _attack_data.strike:
				target_vel = fwd * _attack_data.lunge
			if not _attack_hit_done and t >= _attack_hit_time:
				_attack_hit_done = true
				_do_attack_hit()
			var total: float = _attack_data.windup + _attack_data.strike + _attack_data.recover
			if _queued_attack != "" and t > total * 0.72:
				var q := _queued_attack
				_queued_attack = ""
				state = State.FREE
				_request_attack(q)
			elif t >= total:
				state = State.FREE
				_state_t = 0.0
		State.ROLL:
			var k := 1.0 - smoothstep(0.55, 1.0, _state_t / ROLL_TIME)
			target_vel = _roll_dir * ROLL_SPEED * k
			_invuln = _state_t > IFRAME_START and _state_t < IFRAME_END
			if _state_t >= ROLL_TIME:
				state = State.FREE
				_invuln = false
		State.BACKSTEP:
			target_vel = _roll_dir * 6.0 * (1.0 - _state_t / 0.35)
			_invuln = _state_t < 0.22
			if _state_t >= 0.35:
				state = State.FREE
				_invuln = false
		State.STAGGER:
			target_vel = hvel * 0.85
			if _state_t >= 0.55:
				state = State.FREE
		State.DRINK:
			target_vel = _move_dir.normalized() * 1.4 if _move_dir.length() > 0.05 else Vector3.ZERO
			if not _drink_healed and _state_t > 0.6:
				_drink_healed = true
				hp = min(Game.max_hp(), hp + Game.max_hp() * 0.45)
				hp_changed.emit(hp, Game.max_hp())
				Sfx.play("flask", -4)
				FX.embers(get_parent(), global_position + Vector3(0, 1, 0), 40, 0.6)
			if _state_t >= 1.15:
				state = State.FREE
		State.DEAD, State.REST:
			target_vel = Vector3.ZERO

	var accel := 14.0 if is_on_floor() else 3.0
	if state in [State.ROLL, State.BACKSTEP, State.ATTACK]:
		accel = 30.0
	hvel = hvel.lerp(target_vel, 1.0 - exp(-delta * accel))
	velocity.x = hvel.x
	velocity.z = hvel.z
	# gravidade só quando há colisão de terreno carregada (evita cair no vazio no primeiro frame)
	var has_ground: bool = Game.dungeon_active or Game.terrain == null or Game.terrain.has_collision_at(global_position)
	if not is_on_floor() and has_ground:
		velocity.y -= GRAVITY * delta
	elif not has_ground:
		velocity.y = 0.0
		global_position.y = max(global_position.y, Game.ground_height(global_position.x, global_position.z))
	move_and_slide()
	# rede de segurança: nunca abaixo do terreno (ou do piso da masmorra)
	if not Game.dungeon_active and Game.terrain:
		var gy: float = Game.terrain.height_at(global_position.x, global_position.z)
		if global_position.y < gy - 1.5:
			global_position.y = gy + 0.2
			velocity.y = 0.0

	if is_on_floor() and not _was_floor:
		Sfx.play_at("land", global_position, -8)
	_was_floor = is_on_floor()

	# stamina
	if _stamina_delay > 0.0:
		_stamina_delay -= delta
	elif state != State.ATTACK and not _is_sprinting() and state != State.ROLL:
		var regen := 34.0 if not _guarding else 12.0
		stamina = min(Game.max_stamina(), stamina + regen * delta)
		stamina_changed.emit(stamina, Game.max_stamina())

	# passos
	var spd_now := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and spd_now > 1.0 and state == State.FREE:
		_step_t -= delta * spd_now
		if _step_t <= 0.0:
			_step_t = 2.4
			var reg: String = Game.terrain.region_at(global_position) if Game.terrain else ""
			var kind := "stone" if reg in ["cidadela_marfim", "fornalha", "abismo_obsidiana"] else "grass"
			Sfx.play_at("step_%s_%d" % [kind, randi() % 3], global_position, -14, 0.12, 25.0)

	var turn: float = wrapf(_yaw - _prev_yaw, -PI, PI) / max(delta, 0.0001)
	_prev_yaw = _yaw
	rig.tick(delta, clampf(spd_now / SPRINT, 0.0, 1.0) if state == State.FREE else 0.0, turn, is_on_floor())
	if state == State.FREE:
		rig.guard_pose(_guarding)


func _face_towards(p: Vector3, w: float) -> void:
	var d := p - global_position
	d.y = 0
	if d.length() < 0.01:
		return
	_yaw = lerp_angle(_yaw, atan2(-d.x, -d.z), clampf(w, 0.0, 1.0))
	rig.rotation.y = _yaw


func _use_stamina(v: float, delay := 0.7) -> void:
	stamina = max(stamina - v, -10.0)
	_stamina_delay = delay
	stamina_changed.emit(stamina, Game.max_stamina())


# ------------------------------------------------------------ combate
func _do_attack_hit() -> void:
	var fwd := -rig.global_transform.basis.z
	var origin := global_position + Vector3(0, 1.1, 0)
	var roll := 0.0
	match _attack_data.kind:
		"overhead": roll = PI * 0.5
		"thrust": roll = 0.15
		"slash_r": roll = -0.3
		_: roll = 0.3
	FX.slash(get_parent(), Transform3D(rig.global_transform.basis, origin), _attack_data.range * 0.9, roll, Color(1.0, 0.45, 0.35), _attack_data.kind == "slash_r")
	var hit_any := false
	for e in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(e) or e.is_dead():
			continue
		var to: Vector3 = e.global_position - global_position
		var dy := to.y
		to.y = 0
		var dist: float = to.length() - e.get_radius()
		if dist > _attack_data.range or dy > e.get_height() + 1.0 or dy < -2.5:
			continue
		var ang := rad_to_deg(fwd.angle_to(to.normalized())) if to.length() > 0.01 else 0.0
		if ang > _attack_data.arc * 0.5 and to.length() > e.get_radius() + 0.6:
			continue
		var dmg: float = _attack_data.dmg * Game.damage_mult() * randf_range(0.95, 1.05)
		e.take_hit(dmg, global_position, _attack_data.poise)
		hit_any = true
	if hit_any and cam:
		cam.shake(0.18, 0.08)
		Engine.time_scale = 0.12
		get_tree().create_timer(0.045, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func take_hit(dmg: float, from: Vector3, poise := 30.0) -> void:
	if state == State.DEAD or _invuln:
		return
	var to_att := from - global_position
	to_att.y = 0
	var facing := -rig.global_transform.basis.z
	if _guarding and state == State.FREE and facing.dot(to_att.normalized()) > 0.3 and stamina > 0.0:
		_use_stamina(dmg * 0.55 + poise * 0.3, 0.9)
		hp -= dmg * 0.12
		Sfx.play_at("block", global_position, -2)
		FX.sparks(get_parent(), global_position + Vector3(0, 1.2, 0) + facing * 0.5)
		velocity += -to_att.normalized() * 3.0
		if stamina <= 0.0:
			state = State.STAGGER
			_state_t = -0.4
			Game.message("Guarda quebrada", "small")
	else:
		hp -= dmg
		Sfx.play_at("hit_flesh", global_position, 0)
		Sfx.play_at("player_hurt", global_position, -4)
		FX.blood(get_parent(), global_position + Vector3(0, 1.2, 0))
		rig.flash()
		if poise > 20.0 and state != State.ATTACK or poise > 60.0:
			state = State.STAGGER
			_state_t = 0.0
			rig.hit_motion(to_att, 1.0)
			velocity = -to_att.normalized() * min(poise * 0.12, 9.0) + Vector3(0, 2.0 if poise > 70.0 else 0.0, 0)
		if cam:
			cam.shake(0.3, 0.2)
	hp_changed.emit(hp, Game.max_hp())
	if hp <= 0.0:
		_die()


func _die() -> void:
	state = State.DEAD
	hp = 0.0
	_invuln = true
	lock_target = null
	rig.death_motion()
	Sfx.play("you_died", 0, 0.0)
	died.emit()


func respawn_at(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	state = State.FREE
	_invuln = false
	hp = Game.max_hp()
	stamina = Game.max_stamina()
	rig.new_tween().kill()
	rig.pose.rotation = Vector3.ZERO
	rig.pose.position = Vector3.ZERO
	hp_changed.emit(hp, Game.max_hp())
	stamina_changed.emit(stamina, Game.max_stamina())


## Trava os controles durante cutscenes (sem curar, ao contrário de set_resting).
func set_cutscene(on: bool) -> void:
	if on and state == State.FREE:
		state = State.REST
	elif not on and state == State.REST:
		state = State.FREE


func dismount_now() -> void:
	if Game.mounted:
		_dismount()


func set_resting(on: bool) -> void:
	state = State.REST if on else State.FREE
	if on:
		hp = Game.max_hp()
		hp_changed.emit(hp, Game.max_hp())


func get_radius() -> float:
	return 0.4


func get_height() -> float:
	return 1.8
