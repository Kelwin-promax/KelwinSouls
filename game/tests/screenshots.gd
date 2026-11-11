# Captura de tela das novas construções e sistemas (com janela, não headless).
# Uso (a partir da raiz do repositório):
#   Godot_v4.7.2-stable_win64_console.exe --path game -s res://tests/screenshots.gd
# Os PNGs vão para build/shots/. O save do jogador é preservado.
extends SceneTree

const SAVE := "user://kelwinsouls_save.json"
var out_dir := ""

var game: Node
var _main: Node
var _save_backup := ""
var _had_save := false


func _initialize() -> void:
	game = root.get_node("Game")
	_run.call_deferred()


func _run() -> void:
	_backup_save()
	out_dir = ProjectSettings.globalize_path("res://").path_join("../build/shots").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	current_scene = _main
	for i in 9000:
		if _main.title_cam != null and _main.terrain != null and _main._npcs.size() == 2:
			break
		await process_frame
	await _main._start_play()
	await _frames(30)

	var p = game.player
	# cidadela: vista do portão, de frente para a muralha e a torre
	await _shot_at(Vector3(0, 0, -470), "citadel_gate")
	await _shot_at(Vector3(0, 0, -1100 + 120), "citadel_keep")
	# pagode
	await _shot_at(Vector3(2650, 0, 2900), "pagoda")
	# forja
	await _shot_at(Vector3(2128, 0, 672), "forge")
	# cavalo e montaria
	var g: Dictionary = game.grace_by_id("graca_vale")
	await _shot_at(Vector3(g.pos[0] - 6.0, 0, g.pos[2] + 6.0), "horse_and_vesper")
	p.global_position = game.horse.global_position + Vector3(1.0, 0, 0)
	await _frames(5)
	p._toggle_mount()
	await _frames(20)
	await _capture("mounted")
	p._toggle_mount()
	# masmorra: dentro do labirinto
	var d = _main._dungeons[0]
	_main.enter_dungeon(d)
	await _frames(60)
	await _capture("dungeon_interior")
	await _main.leave_dungeon(d)
	# clima: tempestade e noite
	_main.day_night.set_weather(3)
	game.world_time = 22.0
	await _frames(240)
	await _shot_at(Vector3(0, 0, -470), "citadel_storm_night")
	print("CAPTURAS em %s" % out_dir)
	_restore_save()
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot_at(pos: Vector3, name: String) -> void:
	var p = game.player
	var ground: float = _main.terrain.height_at(pos.x, pos.z)
	p.global_position = Vector3(pos.x, ground + 0.3, pos.z)
	p.velocity = Vector3.ZERO
	_main.terrain.update(p.global_position, true)
	_main.props.update(p.global_position)
	await _frames(90)
	await _capture(name)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("[shot] %s" % name)


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SAVE)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(SAVE)


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(SAVE, FileAccess.WRITE)
		f.store_string(_save_backup)
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
