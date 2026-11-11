# Teste de fumaça headless (Etapas 4 e 5): monta o mundo, inicia o jogo e exercita montaria,
# NPC, masmorra, cena do chefe, inventário e clima. Não depende de janela nem de áudio.
#
# Uso (a partir da raiz do repositório):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path game -s res://tests/smoke_test.gd
#
# O save do jogador é copiado antes e restaurado no fim, porque algumas ações gravam o save.
extends SceneTree

const SAVE := "user://kelwinsouls_save.json"
# classes carregadas em tempo de execução: no modo -s o autoload Game só existe depois do início
var ENEMY: GDScript

var _main: Node
var game: Node
var _failures := 0
var _save_backup := ""
var _had_save := false


func _initialize() -> void:
	game = root.get_node("Game")
	ENEMY = load("res://scripts/actors/enemy.gd")
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	print(("[ OK ] " if cond else "[FAIL] ") + what)
	if not cond:
		_failures += 1


func _run() -> void:
	_backup_save()
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	current_scene = _main
	for i in 6000:
		if _main.title_cam != null and _main.terrain != null and _main._npcs.size() == 2 and _main._dungeons.size() == 2:
			break
		await process_frame
	_check(_main._npcs.size() == 2, "dois NPCs criados")
	_check(_main._dungeons.size() == 2, "duas masmorras criadas")

	await _main._start_play()
	await _frames(5)
	_check(game.player != null, "jogador criado")
	_check(game.horse != null, "cavalo criado perto da Graça")

	await _test_mount()
	await _test_dungeon()
	await _test_boss_intro()
	_test_menus()
	_test_weather()

	_restore_save()
	print("---")
	print("RESULTADO: %s (%d falhas)" % ["OK" if _failures == 0 else "FALHOU", _failures])
	quit(0 if _failures == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _test_mount() -> void:
	var player: Node3D = game.player
	var horse: Node3D = game.horse
	player.global_position = horse.global_position + Vector3(1.0, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	await _frames(4)
	player._toggle_mount()
	_check(game.mounted, "montar no cavalo perto dele")
	var start: Vector3 = horse.global_position
	for i in 60:
		horse.drive(1.0 / 60.0, Vector2(0, -1), Basis.IDENTITY)
		player._mounted_tick(1.0 / 60.0, Vector2(0, -1), Basis.IDENTITY)
		await process_frame
	_check(horse.global_position.distance_to(start) > 3.0, "cavalo anda quando montado")
	_check(player.global_position.distance_to(horse.global_position) < 0.5, "jogador acompanha o cavalo")
	player._toggle_mount()
	_check(not game.mounted, "desmontar")


func _test_dungeon() -> void:
	var player: Node3D = game.player
	var d = _main._dungeons[0]
	_main.enter_dungeon(d)
	_check(game.dungeon_active and game.dungeon == d, "entrar na masmorra")
	await _frames(3)
	var start: Vector3 = d.start_world()
	_check(d.is_walkable(start), "início da masmorra é transitável")
	var walls := 0
	for y in range(0, 19):
		for x in range(0, 19):
			if d._walls[y * 19 + x] == 1:
				walls += 1
	_check(walls > 80 and walls < 19 * 19, "labirinto tem paredes e corredores (%d paredes)" % walls)
	# o jogador precisa ficar no piso da masmorra (não ser puxado para o terreno)
	for i in 150:
		await process_frame
	_check(abs(player.global_position.y - -400.0) < 1.5, "jogador fica no piso da masmorra (y=%.2f)" % player.global_position.y)
	var n_enemies := 0
	for e in d._inner.get_children():
		if e.is_in_group("enemies"):
			n_enemies += 1
	_check(n_enemies >= 2, "masmorra tem inimigos (%d)" % n_enemies)
	_check(d._guard != null, "masmorra tem guardião")
	# simula a morte do guardião e abre o baú
	d._guard_dead = true
	d._open_chest()
	_check(game.dungeons_cleared.has(d.def.id), "baú registra a masmorra como concluída")
	await _main.leave_dungeon(d)
	_check(not game.dungeon_active, "sair da masmorra")
	_check(player.global_position.y > -50.0, "volta ao mundo aberto (y=%.1f)" % player.global_position.y)


func _test_boss_intro() -> void:
	var e: Node3D = ENEMY.new()
	e.setup("vaelrith__the_veiled_horn", 1, "enemy", game.player.global_position + Vector3(0, 0, -12))
	root.add_child(e)
	await _frames(3)
	_main.play_boss_intro(e)
	_check(_main._cutscene, "cena do chefe começa")
	var t0 := Time.get_ticks_msec()
	while _main._cutscene and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	_check(not _main._cutscene, "cena do chefe termina e devolve a câmera")
	e.queue_free()


func _test_menus() -> void:
	_main.hud.inventory_menu(_main.day_night.weather_name(), _main.day_night.clock_text())
	_check(_main.hud.is_menu_open(), "inventário abre")
	_main.hud.close_menu()
	var npc = _main._npcs[0]
	npc._show("start")
	_check(_main.hud.is_menu_open(), "diálogo da Irmã Vesper abre")
	_main.hud.close_menu()
	npc._show("ajuda")
	_main.hud.close_menu()
	var flasks_before: int = game.flasks_max
	npc._apply_effect("vesper_bencao")
	npc._apply_effect("vesper_bencao")
	_check(game.flasks_max == flasks_before + 1, "bênção de Vesper concede +1 Lágrima uma única vez")
	_check(game.world_time > 0.0, "relógio do mundo existe (%s)" % _main.day_night.clock_text())


func _test_weather() -> void:
	var dn = _main.day_night
	dn.set_weather(3)
	await _frames(90)
	_check(dn.weather == 3, "tempestade começa")
	_check(dn._rain.emitting, "chuva ativa na tempestade")
	dn.set_weather(0)
	await _frames(30)
	_check(dn.weather_name() == "Céu limpo", "clima volta a céu limpo")


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
