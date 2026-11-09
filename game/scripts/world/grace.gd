# Graça (fogueira/sítio de graça): checkpoint, descanso, subir de nível, viagem rápida.
class_name Grace
extends Node3D

var grace_id := ""
var grace_name := ""
var discovered := false
var _flame: CPUParticles3D
var _light: OmniLight3D
var _sound: AudioStreamPlayer3D
var _player_near := false


func setup(data: Dictionary, terrain: Terrain) -> void:
	grace_id = data.id
	grace_name = data.name
	position = Vector3(data.pos[0], terrain.height_at(data.pos[0], data.pos[2]), data.pos[2])
	discovered = Game.discovered_graces.has(grace_id)


func _ready() -> void:
	add_to_group("graces")
	# espada fincada num monte de cinzas
	var ash := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.2
	s.height = 0.8
	ash.mesh = s
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(0.18, 0.16, 0.15)
	am.roughness = 1.0
	ash.material_override = am
	ash.position.y = -0.1
	add_child(ash)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 1.6, 0.03)
	blade.mesh = bm
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.6, 0.58, 0.55)
	steel.metallic = 0.9
	steel.roughness = 0.35
	blade.material_override = steel
	blade.position = Vector3(0, 0.95, 0)
	blade.rotation.z = 0.12
	add_child(blade)
	var guard := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.6, 0.07, 0.07)
	guard.mesh = gm
	guard.material_override = steel
	guard.position = Vector3(0.09, 1.75, 0)
	guard.rotation.z = 0.12
	add_child(guard)
	_flame = FX.flame(Color(1.0, 0.75, 0.35), 36, 0.32, 1.3)
	_flame.position.y = 0.3
	add_child(_flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.72, 0.35)
	_light.omni_range = 14.0
	_light.position.y = 1.4
	_light.shadow_enabled = false
	add_child(_light)
	_sound = AudioStreamPlayer3D.new()
	_sound.stream = Sfx.stream("fire_loop")
	_sound.volume_db = -8.0
	_sound.max_distance = 22.0
	_sound.unit_size = 4.0
	_sound.autoplay = true
	add_child(_sound)
	# feixe de luz dourada visível de longe (guia)
	var beam := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.05
	c.bottom_radius = 0.6
	c.height = 60.0
	c.cap_top = false
	c.cap_bottom = false
	beam.mesh = c
	var bmat := FX.additive_mat(Color(1.0, 0.75, 0.35), 0.25)
	bmat.vertex_color_use_as_albedo = false
	beam.material_override = bmat
	beam.position.y = 30.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.name = "Beam"
	add_child(beam)
	_refresh()


func _refresh() -> void:
	_light.light_energy = 3.0 if discovered else 1.2
	_flame.amount = 36 if discovered else 14
	get_node("Beam").visible = discovered


func _process(_delta: float) -> void:
	var p := Game.player as Player
	if p == null:
		return
	var near := p.global_position.distance_to(global_position) < 3.2
	if near != _player_near:
		_player_near = near
		if Game.hud:
			if near:
				Game.hud.set_prompt("[E] Tocar a Graça" if not discovered else "[E] Descansar na Graça")
			else:
				Game.hud.set_prompt("")
	_light.light_energy = (3.0 if discovered else 1.2) + sin(Time.get_ticks_msec() * 0.008) * 0.25


func _unhandled_input(event: InputEvent) -> void:
	if not _player_near or not event.is_action_pressed("interact"):
		return
	var p := Game.player as Player
	if p == null or p.is_busy():
		return
	get_viewport().set_input_as_handled()
	if not discovered:
		discovered = true
		if not Game.discovered_graces.has(grace_id):
			Game.discovered_graces.append(grace_id)
		Sfx.play("grace_discover", -2, 0.0)
		Game.hud.big_banner("GRAÇA ENCONTRADA", Color(1.0, 0.85, 0.5))
		FX.embers(get_tree().current_scene, global_position + Vector3(0, 1, 0), 80, 1.2)
		_refresh()
	Game.last_grace = grace_id
	Game.main.rest_at_grace(self)
