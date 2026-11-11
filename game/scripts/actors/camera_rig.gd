# Câmera em terceira pessoa estilo souls, com trava de mira (lock-on) e tremor.
class_name CameraRig
extends Node3D

var target = null   # Player
var yaw := 0.0
var pitch := -0.25
var distance := 4.6
var height := 1.65
var locked = null   # Enemy/Boss
var camera: Camera3D
var _arm: SpringArm3D
var _pitch_node: Node3D
var _shake_t := 0.0
var _shake_amp := 0.0
var _lock_marker: MeshInstance3D
var _dist_extra := 0.0


func _ready() -> void:
	top_level = true
	_pitch_node = Node3D.new()
	add_child(_pitch_node)
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.collision_mask = 1
	_arm.margin = 0.25
	var sph := SphereShape3D.new()
	sph.radius = 0.25
	_arm.shape = sph
	_pitch_node.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.1
	camera.far = 6000.0
	_arm.add_child(camera)
	camera.current = true
	_lock_marker = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	_lock_marker.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.95, 0.8)
	m.no_depth_test = true
	_lock_marker.material_override = m
	_lock_marker.visible = false
	add_child(_lock_marker)


func set_extra_distance(v: float) -> void:
	_dist_extra = v


func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func shake(amp: float, dur: float) -> void:
	_shake_amp = max(_shake_amp, amp)
	_shake_t = max(_shake_t, dur)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and locked == null:
		yaw -= event.relative.x * Game.mouse_sens * 0.01
		pitch -= event.relative.y * Game.mouse_sens * 0.01 * (-1.0 if Game.invert_y else 1.0)
		pitch = clampf(pitch, -1.25, 0.75)
	elif event.is_action_pressed("lock_on"):
		if locked:
			release_lock()
		else:
			_acquire_lock()
	elif event is InputEventMouseButton and event.pressed and locked and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_switch_lock(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)


func _acquire_lock() -> void:
	var best = null
	var best_score := INF
	var fwd := -camera.global_transform.basis.z
	for e in get_tree().get_nodes_in_group("hittable"):
		if e.is_dead():
			continue
		var to: Vector3 = e.global_position + Vector3(0, e.get_height() * 0.5, 0) - camera.global_position
		var d := to.length()
		if d > 40.0 + e.get_radius() * 3.0:
			continue
		var ang := fwd.angle_to(to.normalized())
		if ang > 0.9:
			continue
		var score := ang * 30.0 + d
		if score < best_score:
			best_score = score
			best = e
	if best:
		locked = best
		if target is Player:
			target.lock_target = best
		Sfx.play("ui_move", -10)


func _switch_lock(dir: int) -> void:
	var list := []
	for e in get_tree().get_nodes_in_group("hittable"):
		if not e.is_dead() and e != locked and e.global_position.distance_to(target.global_position) < 40.0:
			var to: Vector3 = e.global_position - camera.global_position
			var side := camera.global_transform.basis.x.dot(to.normalized())
			list.append([side, e])
	list.sort_custom(func(a, b): return a[0] < b[0])
	if list.is_empty():
		return
	for item in (list if dir > 0 else list.duplicate()):
		if (dir > 0 and item[0] > 0) or (dir < 0 and item[0] < 0):
			locked = item[1]
			target.lock_target = locked
			return
	locked = list[0][1] if dir < 0 else list[-1][1]
	target.lock_target = locked


func release_lock() -> void:
	locked = null
	if target is Player:
		target.lock_target = null


func _process(delta: float) -> void:
	if target == null:
		return
	var look_in := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if locked == null and look_in.length() > 0.1:
		yaw -= look_in.x * delta * 2.6
		pitch = clampf(pitch - look_in.y * delta * 1.8, -1.25, 0.75)
	if locked:
		if not is_instance_valid(locked) or locked.is_dead() or locked.global_position.distance_to(target.global_position) > 55.0:
			release_lock()
		else:
			var lp: Vector3 = locked.global_position + Vector3(0, locked.get_height() * 0.45, 0)
			var to: Vector3 = lp - (target.global_position + Vector3(0, height, 0))
			var want_yaw := atan2(-to.x, -to.z)
			yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-delta * 8.0))
			var flat := Vector2(to.x, to.z).length()
			var want_pitch := clampf(-atan2(-to.y, flat) * 0.6 - 0.22, -0.9, 0.3)
			pitch = lerpf(pitch, want_pitch, 1.0 - exp(-delta * 5.0))
			_lock_marker.visible = true
			_lock_marker.global_position = lp
	if locked == null:
		_lock_marker.visible = false
	var follow: Vector3 = target.global_position + Vector3(0, height, 0)
	global_position = global_position.lerp(follow, 1.0 - exp(-delta * 14.0)) if global_position.distance_to(follow) < 10.0 else follow
	rotation = Vector3(0, yaw, 0)
	_pitch_node.rotation.x = pitch
	_arm.spring_length = lerpf(_arm.spring_length, distance + _dist_extra, 1.0 - exp(-delta * 3.0))
	if _shake_t > 0.0:
		_shake_t -= delta
		camera.h_offset = randf_range(-1, 1) * _shake_amp * 0.3
		camera.v_offset = randf_range(-1, 1) * _shake_amp * 0.3
		if _shake_t <= 0.0:
			_shake_amp = 0.0
			camera.h_offset = 0.0
			camera.v_offset = 0.0
	# câmera nunca abaixo do terreno/água
	if Game.terrain or Game.dungeon_active:
		var cp := camera.global_position
		var gy: float = Game.ground_y(cp.x, cp.z) + 0.35
		if cp.y < gy:
			camera.global_position.y = gy
