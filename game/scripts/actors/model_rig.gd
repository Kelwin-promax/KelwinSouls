# Suporte de modelo + animação procedural para os modelos estáticos (sem esqueleto).
# Hierarquia: ModelRig (yaw) → pose (inclinações/saltos) → modelo .glb
# Modelos com AnimationPlayer (dragões, rainha) também passam por aqui.
class_name ModelRig
extends Node3D

## Correção de orientação do modelo (radianos). Os .glb olham para +Z; o Godot usa -Z como frente.
const DEFAULT_YAW_OFFSET := PI

var pose: Node3D
var model: Node3D
var anim: AnimationPlayer
var height := 2.0
var radius := 0.5
var _phase := 0.0
var _lean := Vector3.ZERO
var _bob := 0.0
var _breath := 0.0
var _flash_t := 0.0
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
var tween: Tween
## True quando o modelo tem esqueleto e clipes (idle, walk, run, attack_light, attack_heavy).
var rigged := false
var _clip_busy := 0.0          # tempo restante de um golpe animado (locomoção não sobrescreve)


func build(model_name: String, yaw_offset := DEFAULT_YAW_OFFSET, extra_scale := 1.0) -> void:
	pose = Node3D.new()
	add_child(pose)
	var scene := Game.model_scene(model_name)
	model = scene.instantiate()
	pose.add_child(model)
	model.rotation.y = yaw_offset
	var info := Game.model_info(model_name)
	if info.get("scale_applied", false):
		height = float(info.get("height_m", 2.0))
		var sz: Array = info.get("size_m", [1, 2, 1])
		radius = max(sz[0], sz[2]) * 0.32
	else:
		# modelos animados: mede o AABB e reescala para a altura do catálogo
		var aabb := _measure(model)
		var target := float(info.get("height_m", 4.0))
		var s: float = target / max(aabb.size.y, 0.001)
		model.scale = Vector3.ONE * s
		model.position.y = -aabb.position.y * s
		height = target
		radius = max(aabb.size.x, aabb.size.z) * s * 0.3
	if extra_scale != 1.0:
		pose.scale = Vector3.ONE * extra_scale
		height *= extra_scale
		radius *= extra_scale
	anim = _find_anim(model)
	rigged = anim != null and Game.has_rig(model_name)
	if anim:
		for a_name in anim.get_animation_list():
			var low := a_name.to_lower()
			if low.contains("stand") or low.contains("walk") or low.contains("flight") or low.contains("take") \
					or low.contains("groggyloop") or low.contains("skymove") or low.contains("aura") \
					or (rigged and (low == "idle" or low == "run")):
				anim.get_animation(a_name).loop_mode = Animation.LOOP_LINEAR
	_collect_meshes(model)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1, 0.9, 0.8, 0.0)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD


func _measure(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a: AABB = (n as Node3D).global_transform.affine_inverse() * m.global_transform * m.get_aabb() if m.is_inside_tree() else m.transform * m.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _find_anim(n: Node) -> AnimationPlayer:
	var list := n.find_children("*", "AnimationPlayer", true, false)
	return list[0] if list.size() > 0 else null


func _collect_meshes(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)


func play_anim(names: Array, speed := 1.0, blend := 0.25) -> bool:
	if anim == null:
		return false
	for nm in names:
		for a in anim.get_animation_list():
			if a.to_lower().contains(String(nm).to_lower()):
				if anim.current_animation != a:
					anim.play(a, blend, speed)
				else:
					anim.speed_scale = speed
				return true
	return false


func flash(strength := 1.0) -> void:
	_flash_t = 0.12 * strength
	for m in _meshes:
		m.material_overlay = _flash_mat
	_flash_mat.albedo_color.a = 0.55 * strength


func set_overlay(mat: Material) -> void:
	for m in _meshes:
		m.material_overlay = mat


## Reinicia um clipe mesmo que já seja o atual (para golpes seguidos começarem do início).
func _restart(clip_name: String, speed: float) -> void:
	anim.stop()
	anim.play(clip_name, 0.05, speed)


func _clip_length(part: String) -> float:
	for a in anim.get_animation_list():
		if a.to_lower().contains(part):
			return anim.get_animation(a).length
	return 0.0


## Locomoção por esqueleto: parado = idle, andando = walk, correndo = run (velocidade acompanha o passo).
func _drive_locomotion(speed01: float) -> void:
	if _clip_busy > 0.0:
		return
	if speed01 > 0.05:
		if speed01 > 0.6:
			play_anim(["run"], 0.8 + speed01 * 0.4, 0.2)
		else:
			play_anim(["walk"], 0.7 + speed01 * 0.9, 0.2)
	else:
		play_anim(["idle"], 1.0, 0.3)


## Atualiza o balanço procedural. speed01 = 0..1 (parado..correndo); turn = velocidade angular.
func tick(delta: float, speed01: float, turn: float, grounded := true) -> void:
	if rigged:
		_clip_busy = maxf(0.0, _clip_busy - delta)
		_drive_locomotion(speed01)
	_breath += delta * 1.6
	_phase += delta * (5.5 + speed01 * 6.0) * (1.0 if speed01 > 0.05 else 0.0)
	var target_bob := absf(sin(_phase)) * 0.09 * speed01 * height / 2.0
	_bob = lerpf(_bob, target_bob, 1.0 - exp(-delta * 14.0))
	var lean_fwd := -0.13 * speed01
	var lean_side := clampf(-turn * 0.06, -0.25, 0.25) * speed01
	_lean = _lean.lerp(Vector3(lean_fwd, 0, lean_side), 1.0 - exp(-delta * 6.0))
	if tween == null or not tween.is_running():
		pose.position.y = _bob + sin(_breath) * 0.006 * height
		pose.rotation.x = _lean.x + sin(_phase * 2.0) * 0.015 * speed01
		pose.rotation.z = _lean.z + sin(_phase) * 0.03 * speed01
		pose.rotation.y = lerp_angle(pose.rotation.y, 0.0, 1.0 - exp(-delta * 10.0))
		pose.position.z = lerpf(pose.position.z, 0.0, 1.0 - exp(-delta * 10.0))
		pose.position.x = lerpf(pose.position.x, 0.0, 1.0 - exp(-delta * 10.0))
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			for m in _meshes:
				m.material_overlay = null


func new_tween() -> Tween:
	if tween and tween.is_running():
		tween.kill()
	tween = create_tween()
	return tween


## Sequência de ataque procedural. kind: slash, slash_r, overhead, thrust, spin, slam, sweep
## Retorna o tempo até o golpe acertar (para sincronizar o dano).
func attack_motion(kind: String, windup: float, strike: float, recover: float, power := 1.0) -> float:
	if rigged and anim:
		# golpe com esqueleto: o clipe é esticado/encolhido para durar o mesmo tempo do golpe
		var total := windup + strike + recover
		var heavy := power >= 1.3 or kind in ["overhead", "spin", "slam"]
		var clip := "attack_heavy" if heavy else "attack_light"
		var len := _clip_length(clip)
		if len > 0.0 and total > 0.0:
			_restart(clip, clampf(len / total, 0.4, 2.5))
			_clip_busy = total
	var t := new_tween().set_trans(Tween.TRANS_SINE)
	var h := height
	match kind:
		"slash", "slash_r":
			var s := 1.0 if kind == "slash" else -1.0
			t.tween_property(pose, "rotation", Vector3(0.08, 0.75 * s * power, 0.1 * s), windup).set_ease(Tween.EASE_OUT)
			t.tween_property(pose, "rotation", Vector3(-0.18, -0.9 * s * power, -0.12 * s), strike).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(pose, "position:z", -0.35 * h * 0.5, strike)
		"overhead":
			t.tween_property(pose, "rotation", Vector3(0.38 * power, 0, 0), windup).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(pose, "position:y", 0.12 * h * 0.5, windup)
			t.tween_property(pose, "rotation", Vector3(-0.42 * power, 0, 0), strike).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(pose, "position:y", -0.05 * h * 0.5, strike)
			t.parallel().tween_property(pose, "position:z", -0.4 * h * 0.5, strike)
		"thrust":
			t.tween_property(pose, "rotation", Vector3(0.15, 0.2, 0), windup).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(pose, "position:z", 0.25 * h * 0.5, windup)
			t.tween_property(pose, "rotation", Vector3(-0.25, -0.05, 0), strike).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(pose, "position:z", -0.9 * h * 0.5, strike)
		"spin":
			t.tween_property(pose, "rotation", Vector3(0.1, 0.6, 0), windup).set_ease(Tween.EASE_OUT)
			t.tween_property(pose, "rotation", Vector3(-0.1, 0.6 - TAU, 0), strike * 1.4).set_ease(Tween.EASE_IN_OUT)
		"slam":
			t.tween_property(pose, "position:y", 0.45 * h * 0.5, windup).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(pose, "rotation", Vector3(0.35, 0, 0), windup)
			t.tween_property(pose, "position:y", -0.08 * h * 0.5, strike).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(pose, "rotation", Vector3(-0.5, 0, 0), strike)
		"sweep":
			t.tween_property(pose, "rotation", Vector3(0.0, -0.9, 0.25), windup).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(pose, "position:y", -0.1 * h * 0.5, windup)
			t.tween_property(pose, "rotation", Vector3(-0.1, 1.2, -0.2), strike).set_ease(Tween.EASE_IN)
	t.tween_interval(recover * 0.4)
	t.tween_property(pose, "rotation", Vector3.ZERO, recover * 0.6).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(pose, "position", Vector3.ZERO, recover * 0.6)
	return windup + strike * (1.0 if kind != "spin" else 1.0)


func roll_motion(dur: float) -> void:
	var t := new_tween()
	t.tween_property(pose, "rotation:x", -TAU, dur).from(0.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(pose, "position:y", -height * 0.25, dur * 0.5).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(pose, "position:y", 0.0, dur * 0.5).set_delay(dur * 0.5)
	t.tween_callback(func(): pose.rotation.x = 0.0)


func hit_motion(from_dir: Vector3, strength := 1.0) -> void:
	var local := global_transform.basis.inverse() * from_dir
	var t := new_tween()
	t.tween_property(pose, "rotation", Vector3(0.25 * strength * signf(local.z + 0.001), 0, -0.2 * strength * signf(local.x)), 0.08)
	t.tween_property(pose, "rotation", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_SINE)


func guard_pose(on: bool) -> void:
	if tween and tween.is_running():
		return
	pose.rotation.x = lerpf(pose.rotation.x, 0.12 if on else 0.0, 0.3)
	pose.position.y = lerpf(pose.position.y, -0.06 * height * 0.5 if on else 0.0, 0.3)


func death_motion(dur := 1.4) -> void:
	var t := new_tween()
	t.tween_property(pose, "rotation", Vector3(0.2, 0, 0.1), 0.25)
	t.tween_property(pose, "rotation", Vector3(PI * 0.48, 0.1, 0.15), dur).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(pose, "position:y", height * 0.12, dur)


func drink_motion(dur := 1.0) -> void:
	var t := new_tween()
	t.tween_property(pose, "rotation:x", -0.25, dur * 0.3)
	t.tween_interval(dur * 0.4)
	t.tween_property(pose, "rotation:x", 0.0, dur * 0.3)


func roar_motion(dur := 1.8) -> void:
	var t := new_tween()
	t.tween_property(pose, "rotation:x", -0.35, dur * 0.25)
	t.parallel().tween_property(pose, "position:y", 0.1 * height * 0.5, dur * 0.25)
	for i in 6:
		t.tween_property(pose, "rotation:z", 0.04 * (1 if i % 2 == 0 else -1), dur * 0.08)
	t.tween_property(pose, "rotation", Vector3.ZERO, dur * 0.27)
	t.parallel().tween_property(pose, "position:y", 0.0, dur * 0.27)
