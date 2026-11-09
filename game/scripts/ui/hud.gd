# Interface completa: HUD, faixas, menus (título, Graça, mapa, pausa, final).
class_name HUD
extends CanvasLayer

signal menu_closed

const GOLD := Color(0.92, 0.8, 0.55)
const DIM := Color(0.75, 0.7, 0.62)

var font: SystemFont
var font_bold: SystemFont
var root: Control
var hp_bar: ProgressBar
var hp_back: ProgressBar
var st_bar: ProgressBar
var brasas_label: Label
var flask_label: Label
var embers_label: Label
var boss_box: Control
var boss_bar: ProgressBar
var boss_back: ProgressBar
var boss_name: Label
var prompt_label: Label
var toast_label: Label
var banner: Control
var banner_label: Label
var region_label: Label
var menu_layer: Control
var _boss: Node
var _toast_t := 0.0
var _hp_target := 1.0
var _boss_target := 1.0
var _menu_open := ""
var _loading_label: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Georgia", "Palatino Linotype", "Times New Roman", "serif"])
	font_bold = SystemFont.new()
	font_bold.font_names = font.font_names
	font_bold.font_weight = 700
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_hud()
	menu_layer = Control.new()
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_layer)
	Game.brasas_changed.connect(func(v): brasas_label.text = "%d" % v)
	Game.flasks_changed.connect(func(v): flask_label.text = "Lágrimas  %d" % v)
	Game.show_message.connect(_on_message)
	Game.hud = self
	set_hud_visible(false)


# ------------------------------------------------------------ helpers
func label(text: String, size := 22, color := GOLD, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold if bold else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func bar(color: Color, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 1.0
	b.value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.04, 0.75)
	bg.border_color = Color(0.45, 0.38, 0.28, 0.9)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", Color(1, 0.92, 0.7))
	b.add_theme_color_override("font_focus_color", Color(1, 0.92, 0.7))
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0, 0, 0, 0)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.5, 0.4, 0.25, 0.18)
	hover.border_color = Color(0.85, 0.7, 0.45, 0.6)
	hover.border_width_bottom = 1
	hover.border_width_top = 1
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.custom_minimum_size = Vector2(420, 48)
	b.pressed.connect(func():
		Sfx.play("ui_select", -6, 0.0)
		cb.call())
	b.focus_entered.connect(func(): Sfx.play("ui_move", -12, 0.0))
	b.mouse_entered.connect(func(): b.grab_focus())
	return b


func panel_bg(alpha := 0.82) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.02, 0.02, 0.025, alpha)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c


# ------------------------------------------------------------ HUD
func _build_hud() -> void:
	var tl := VBoxContainer.new()
	tl.position = Vector2(40, 34)
	tl.add_theme_constant_override("separation", 6)
	root.add_child(tl)
	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(420, 14)
	tl.add_child(hp_stack)
	hp_back = bar(Color(0.95, 0.85, 0.6, 0.9), 420, 14)
	hp_stack.add_child(hp_back)
	hp_bar = bar(Color(0.62, 0.07, 0.06), 420, 14)
	var tr := StyleBoxFlat.new()
	tr.bg_color = Color(0, 0, 0, 0)
	hp_bar.add_theme_stylebox_override("background", tr)
	hp_stack.add_child(hp_bar)
	st_bar = bar(Color(0.22, 0.5, 0.22), 300, 9)
	tl.add_child(st_bar)

	flask_label = label("Lágrimas  %d" % Game.flasks, 22)
	flask_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	flask_label.position = Vector2(40, -70)
	root.add_child(flask_label)
	embers_label = label("", 18, DIM)
	embers_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	embers_label.position = Vector2(40, -42)
	root.add_child(embers_label)

	var br := HBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.position = Vector2(-240, -70)
	root.add_child(br)
	var icon := label("◆", 24, Color(1.0, 0.6, 0.25))
	br.add_child(icon)
	brasas_label = label("%d" % Game.brasas, 28)
	br.add_child(brasas_label)

	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	boss_box.position = Vector2(-450, -140)
	boss_box.custom_minimum_size = Vector2(900, 0)
	root.add_child(boss_box)
	boss_name = label("", 24, Color(0.95, 0.9, 0.8))
	boss_box.add_child(boss_name)
	var bstack := Control.new()
	bstack.custom_minimum_size = Vector2(900, 12)
	boss_box.add_child(bstack)
	boss_back = bar(Color(0.95, 0.85, 0.6, 0.9), 900, 12)
	bstack.add_child(boss_back)
	boss_bar = bar(Color(0.55, 0.05, 0.04), 900, 12)
	var tr2 := StyleBoxFlat.new()
	tr2.bg_color = Color(0, 0, 0, 0)
	boss_bar.add_theme_stylebox_override("background", tr2)
	bstack.add_child(boss_bar)
	boss_box.visible = false

	prompt_label = label("", 24, Color(0.95, 0.9, 0.78))
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-200, -230)
	prompt_label.custom_minimum_size = Vector2(400, 0)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_label)

	toast_label = label("", 24, Color(0.95, 0.88, 0.7))
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position = Vector2(-400, -300)
	toast_label.custom_minimum_size = Vector2(800, 0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(toast_label)

	region_label = label("", 40, Color(0.95, 0.9, 0.8))
	region_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	region_label.position = Vector2(-500, 150)
	region_label.custom_minimum_size = Vector2(1000, 0)
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region_label.modulate.a = 0.0
	root.add_child(region_label)

	banner = Control.new()
	banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.6)
	band.anchor_left = 0; band.anchor_right = 1; band.anchor_top = 0.42; band.anchor_bottom = 0.58
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(band)
	banner_label = label("", 72, GOLD)
	banner_label.anchor_left = 0; banner_label.anchor_right = 1; banner_label.anchor_top = 0.42; banner_label.anchor_bottom = 0.58
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_child(banner_label)
	banner.modulate.a = 0.0
	root.add_child(banner)
	_update_embers()


func set_hud_visible(v: bool) -> void:
	for c in root.get_children():
		if c != banner:
			c.visible = v and (c != boss_box or _boss != null)


func _update_embers() -> void:
	embers_label.text = "Grandes Brasas  %d / 2" % Game.great_embers.size() if Game.great_embers.size() < 2 else "Grandes Brasas  %d" % Game.great_embers.size()


func bind_player(p: Player) -> void:
	p.hp_changed.connect(func(hp, mx):
		_hp_target = clampf(hp / mx, 0.0, 1.0)
		hp_bar.value = _hp_target)
	p.stamina_changed.connect(func(st, mx): st_bar.value = clampf(st / mx, 0.0, 1.0))
	Game.stats_changed.connect(_resize_bars)
	_resize_bars()


func _resize_bars() -> void:
	var w := 300.0 + (Game.vigor - 10) * 14.0
	hp_bar.custom_minimum_size.x = w
	hp_back.custom_minimum_size.x = w
	hp_bar.get_parent().custom_minimum_size.x = w
	st_bar.custom_minimum_size.x = 220.0 + (Game.endurance - 10) * 10.0
	flask_label.text = "Lágrimas  %d" % Game.flasks
	brasas_label.text = "%d" % Game.brasas
	_update_embers()


func _process(delta: float) -> void:
	hp_back.value = move_toward(hp_back.value, hp_bar.value, delta * 0.35) if hp_back.value > hp_bar.value else hp_bar.value
	if boss_box.visible:
		boss_back.value = move_toward(boss_back.value, boss_bar.value, delta * 0.25) if boss_back.value > boss_bar.value else boss_bar.value
	if _toast_t > 0.0:
		_toast_t -= delta
		toast_label.modulate.a = clampf(_toast_t, 0.0, 1.0)


func set_prompt(t: String) -> void:
	prompt_label.text = t


func _on_message(text: String, kind: String) -> void:
	if kind == "item":
		Sfx.play("souls_pickup", -4, 0.0)
		_update_embers()
	toast_label.text = text
	_toast_t = 3.5


func big_banner(text: String, color: Color, hold := 2.6) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.6).from(0.0)
	tw.parallel().tween_property(banner_label, "scale", Vector2(1.0, 1.0), 2.5).from(Vector2(0.96, 0.96))
	tw.tween_interval(hold)
	tw.tween_property(banner, "modulate:a", 0.0, 1.2)


func region_banner(text: String) -> void:
	region_label.text = text
	var tw := create_tween()
	tw.tween_property(region_label, "modulate:a", 1.0, 1.2).from(0.0)
	tw.tween_interval(2.5)
	tw.tween_property(region_label, "modulate:a", 0.0, 1.5)


func show_boss(b: Node) -> void:
	_boss = b
	boss_name.text = b.display_name
	boss_bar.value = clampf(b.hp / b.max_hp, 0, 1)
	boss_back.value = boss_bar.value
	boss_box.visible = true


func update_boss(hp: float, mx: float) -> void:
	boss_bar.value = clampf(hp / mx, 0.0, 1.0)


func hide_boss() -> void:
	_boss = null
	boss_box.visible = false


# ------------------------------------------------------------ menus
func is_menu_open() -> bool:
	return _menu_open != ""


func close_menu() -> void:
	for c in menu_layer.get_children():
		c.queue_free()
	_menu_open = ""
	menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_closed.emit()


func _open(name: String) -> Control:
	close_menu()
	_menu_open = name
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(c)
	menu_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


func _vbox(parent: Control, x := 0.5, y := 0.5) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.anchor_left = x; v.anchor_right = x; v.anchor_top = y; v.anchor_bottom = y
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	parent.add_child(v)
	return v


func _focus_first(v: Control) -> void:
	for c in v.get_children():
		if c is Button:
			c.call_deferred("grab_focus")
			return


func title_screen(on_new: Callable, on_continue: Callable, on_quit: Callable) -> void:
	var c := _open("title")
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(shade)
	var v := _vbox(c, 0.5, 0.62)
	var t := label("KELWINSOULS", 110, Color(0.95, 0.85, 0.62), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := label("As Terras de Kelwin aguardam o último Maculado", 24, DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 40); v.add_child(sp)
	if Game.has_save():
		v.add_child(button("Continuar", on_continue))
	v.add_child(button("Novo Jogo", on_new))
	v.add_child(button("Configurações", func(): settings_menu(func(): title_screen(on_new, on_continue, on_quit))))
	v.add_child(button("Sair", on_quit))
	var credits := label("Feito com Godot 4 + Python  •  sons e texturas gerados proceduralmente", 16, Color(0.6, 0.56, 0.5))
	credits.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	credits.position = Vector2(-380, -40)
	c.add_child(credits)
	_focus_first(v)


func lore_intro(on_done: Callable) -> void:
	var c := _open("intro")
	c.add_child(panel_bg(1.0))
	var pages := [
		"No princípio havia apenas a névoa, e na névoa ardia a Brasa Primordial.",
		"Dela brotou a Árvore de Brasa, e em seu coração forjou-se o Anel de Kelwin,\na lei que dava forma à vida, à morte e ao fogo.",
		"O Rei Kelwin reinou por eras sob a luz dourada.\nMas quando a chama começou a minguar, o Rei despedaçou o Anel\npara não ser consumido por ela.",
		"Os Fragmentos, as Grandes Brasas, foram tomados pelos seus herdeiros,\nsemideuses que, enlouquecidos pelo poder, guerrearam até que restassem apenas cinzas.",
		"Você é um Maculado das Cinzas.\nMorto, exilado e agora chamado de volta pela Graça.",
		"Reúna as Grandes Brasas. Atravesse os portões de Marfim.\nE decida o destino da Chama.",
	]
	var l := label("", 30, Color(0.9, 0.86, 0.78))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(l)
	var skip := label("[Espaço / Enter] continuar", 16, Color(0.6, 0.55, 0.5))
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.position = Vector2(-280, -40)
	c.add_child(skip)
	var idx := [0]
	var show_page := func():
		l.text = pages[idx[0]]
		var tw := create_tween()
		tw.tween_property(l, "modulate:a", 1.0, 1.0).from(0.0)
	show_page.call()
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.modulate.a = 0.0
	c.add_child(btn)
	btn.grab_focus()
	btn.pressed.connect(func():
		idx[0] += 1
		if idx[0] >= pages.size():
			close_menu()
			on_done.call()
		else:
			show_page.call())


func death_screen() -> void:
	var c := _open("death")
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.7)
	band.anchor_left = 0; band.anchor_right = 1; band.anchor_top = 0.4; band.anchor_bottom = 0.6
	c.add_child(band)
	var l := label("VOCÊ MORREU", 96, Color(0.62, 0.06, 0.05))
	l.anchor_left = 0; l.anchor_right = 1; l.anchor_top = 0.4; l.anchor_bottom = 0.6
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(l)
	c.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(c, "modulate:a", 1.0, 1.4)
	tw.parallel().tween_property(l, "scale", Vector2(1.04, 1.04), 3.5).from(Vector2.ONE)
	_menu_open = ""


func grace_menu(grace_name: String, on_leave: Callable) -> void:
	var c := _open("grace")
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.anchor_right = 0.42
	bg.anchor_bottom = 1.0
	c.add_child(bg)
	var v := _vbox(c, 0.2, 0.5)
	var t := label(grace_name, 34, GOLD)
	v.add_child(t)
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 20); v.add_child(sp)
	v.add_child(button("Subir de Nível", func(): level_menu(func(): grace_menu(grace_name, on_leave))))
	v.add_child(button("Viajar", func(): travel_menu(func(): grace_menu(grace_name, on_leave))))
	v.add_child(button("Partir", func():
		close_menu()
		on_leave.call()))
	_focus_first(v)


func level_menu(on_back: Callable) -> void:
	var c := _open("level")
	c.add_child(panel_bg(0.75))
	var v := _vbox(c)
	v.add_child(label("Nível %d" % Game.level, 40, GOLD))
	v.add_child(label("Brasas: %d     Custo: %d" % [Game.brasas, Game.level_cost()], 24, DIM))
	var info := label("Vida %d   •   Fôlego %d   •   Dano x%.2f" % [Game.max_hp(), Game.max_stamina(), Game.damage_mult()], 20, DIM)
	v.add_child(info)
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 20); v.add_child(sp)
	for s in [["vigor", "Vigor", Game.vigor], ["endurance", "Fôlego", Game.endurance], ["strength", "Força", Game.strength]]:
		var stat: String = s[0]
		v.add_child(button("%s   %d   →   %d" % [s[1], s[2], s[2] + 1], func():
			if Game.level_up(stat):
				Sfx.play("level_up", -4, 0.0)
				if Game.player:
					Game.player.hp = Game.max_hp()
					Game.player.hp_changed.emit(Game.max_hp(), Game.max_hp())
				Game.save_game()
				level_menu(on_back)
			else:
				Game.message("Brasas insuficientes", "small")))
	v.add_child(button("Voltar", on_back))
	_focus_first(v)


func travel_menu(on_back: Callable) -> void:
	var c := _open("travel")
	c.add_child(panel_bg(0.6))
	_map_view(c, true, on_back)


func map_menu() -> void:
	var c := _open("map")
	c.add_child(panel_bg(0.6))
	_map_view(c, false, func(): close_menu())


func _map_view(c: Control, travel: bool, on_back: Callable) -> void:
	var tex := TextureRect.new()
	tex.texture = load("res://assets/world/map.png")
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.anchor_left = 0.5; tex.anchor_right = 0.5; tex.anchor_top = 0.5; tex.anchor_bottom = 0.5
	var S := 820.0
	tex.offset_left = -S / 2 - 160; tex.offset_right = S / 2 - 160; tex.offset_top = -S / 2; tex.offset_bottom = S / 2
	c.add_child(tex)
	var size: float = Game.world.size
	var to_map := func(p: Vector3) -> Vector2:
		return Vector2((p.x + size / 2) / size * S, (p.z + size / 2) / size * S)
	for g in Game.world.graces:
		if not Game.discovered_graces.has(g.id):
			continue
		var gp: Vector2 = to_map.call(Vector3(g.pos[0], 0, g.pos[2]))
		var gl := label("✦", 26, Color(1.0, 0.85, 0.4))
		gl.position = gp - Vector2(9, 16)
		tex.add_child(gl)
		if travel:
			var b := Button.new()
			b.flat = true
			b.tooltip_text = g.name
			b.position = gp - Vector2(14, 14)
			b.custom_minimum_size = Vector2(28, 28)
			var gid: String = g.id
			b.pressed.connect(func():
				close_menu()
				Game.main.fast_travel(gid))
			tex.add_child(b)
	for bdata in Game.world.bosses:
		if Game.defeated_bosses.has(bdata.id):
			var bp: Vector2 = to_map.call(Vector3(bdata.pos[0], 0, bdata.pos[2]))
			var bl := label("✕", 18, Color(0.5, 0.1, 0.08))
			bl.position = bp - Vector2(6, 12)
			tex.add_child(bl)
	if Game.player:
		var pp: Vector2 = to_map.call(Game.player.global_position)
		var pl := label("▲", 22, Color(0.95, 0.2, 0.15))
		pl.position = pp - Vector2(8, 14)
		tex.add_child(pl)
	var side := _vbox(c, 0.82, 0.5)
	side.add_child(label("Viagem Rápida" if travel else "Mapa", 34, GOLD))
	if travel:
		for g in Game.world.graces:
			if Game.discovered_graces.has(g.id):
				var gid: String = g.id
				side.add_child(button(g.name, func():
					close_menu()
					Game.main.fast_travel(gid)))
	side.add_child(button("Voltar", on_back))
	_focus_first(side)


func pause_menu(on_resume: Callable, on_title: Callable) -> void:
	var c := _open("pause")
	c.add_child(panel_bg(0.65))
	var v := _vbox(c)
	v.add_child(label("Pausa", 48, GOLD))
	var h := int(Game.play_time / 3600.0)
	var m := int(fmod(Game.play_time, 3600.0) / 60.0)
	v.add_child(label("Nível %d   •   Tempo %02d:%02d   •   Grandes Brasas %d" % [Game.level, h, m, Game.great_embers.size()], 20, DIM))
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 20); v.add_child(sp)
	v.add_child(button("Continuar", on_resume))
	v.add_child(button("Mapa", func(): map_menu()))
	v.add_child(button("Controles", func(): controls_menu(func(): pause_menu(on_resume, on_title))))
	v.add_child(button("Configurações", func(): settings_menu(func(): pause_menu(on_resume, on_title))))
	v.add_child(button("Salvar e voltar ao título", on_title))
	_focus_first(v)


func controls_menu(on_back: Callable) -> void:
	var c := _open("controls")
	c.add_child(panel_bg(0.8))
	var v := _vbox(c)
	v.add_child(label("Controles", 40, GOLD))
	var lines := [
		"WASD — mover        Mouse — câmera",
		"Botão esquerdo — ataque leve (combo de 3)",
		"Ctrl + botão esquerdo — ataque pesado",
		"Botão direito — defender",
		"Espaço (toque) — rolar   •   Espaço (segurar) / Shift — correr",
		"F — pular (ataque no ar = golpe descendente)",
		"Q / botão do meio — travar mira   •   roda do mouse — trocar alvo",
		"R — beber Lágrima Ígnea (cura)",
		"E — interagir / Graça        M — mapa        Esc — pausa",
		"Controle Xbox: RB/RT ataques, LB defesa, B rolar, X cura, A interagir, R3 travar",
	]
	for ln in lines:
		v.add_child(label(ln, 22, DIM))
	v.add_child(button("Voltar", on_back))
	_focus_first(v)


func settings_menu(on_back: Callable) -> void:
	var c := _open("settings")
	c.add_child(panel_bg(0.8))
	var v := _vbox(c)
	v.add_child(label("Configurações", 40, GOLD))
	var sens := label("Sensibilidade do mouse: %.2f" % Game.mouse_sens, 22, DIM)
	v.add_child(sens)
	var sl := HSlider.new()
	sl.min_value = 0.05
	sl.max_value = 0.8
	sl.step = 0.01
	sl.value = Game.mouse_sens
	sl.custom_minimum_size = Vector2(420, 30)
	sl.value_changed.connect(func(x):
		Game.mouse_sens = x
		sens.text = "Sensibilidade do mouse: %.2f" % x)
	v.add_child(sl)
	var q_names := ["Baixa", "Média", "Alta"]
	v.add_child(button("Qualidade gráfica: %s (aplica ao reiniciar)" % q_names[Game.quality], func():
		Game.quality = (Game.quality + 1) % 3
		Game.save_settings()
		settings_menu(on_back)))
	v.add_child(button("Inverter eixo Y: %s" % ("Sim" if Game.invert_y else "Não"), func():
		Game.invert_y = not Game.invert_y
		Game.save_settings()
		settings_menu(on_back)))
	v.add_child(button("Tela cheia", func():
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN))
	v.add_child(button("Voltar", func():
		Game.save_settings()
		on_back.call()))
	_focus_first(v)


func ending_choice(on_choice: Callable) -> void:
	var c := _open("ending")
	c.add_child(panel_bg(0.7))
	var v := _vbox(c)
	var t := label("Diante de você, a Brasa Primordial agoniza.\nO Anel de Kelwin aguarda uma mão que o reforje.", 30, Color(0.92, 0.86, 0.76))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 30); v.add_child(sp)
	v.add_child(button("Reacender a Chama (Era do Ouro)", func(): on_choice.call("fire")))
	v.add_child(button("Deixar a Chama se apagar (Era das Cinzas)", func(): on_choice.call("dark")))
	if Game.great_embers.size() >= 5:
		v.add_child(button("Fundir as Grandes Brasas em si mesmo (Era do Maculado)", func(): on_choice.call("lord")))
	_focus_first(v)


func ending_text(kind: String, on_done: Callable) -> void:
	var c := _open("ending_text")
	c.add_child(panel_bg(1.0))
	var texts := {
		"fire": "Você ofertou a própria alma à Brasa Primordial.\nA Árvore de Brasa voltou a arder, e uma nova Era do Ouro começou.\nMas toda chama, um dia, volta a minguar...",
		"dark": "Você deu as costas à chama moribunda.\nA luz dourada se apagou, e as Terras de Kelwin mergulharam na Era das Cinzas,\numa era sem deuses, onde os homens finalmente caminham sozinhos.",
		"lord": "Com cinco Grandes Brasas ardendo no peito, você reforjou o Anel à sua imagem.\nNem ouro nem cinza: começou a Era do Maculado, e seu nome será o novo Rei de Kelwin.",
	}
	var l := label(texts.get(kind, ""), 30, Color(0.9, 0.85, 0.75))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(l)
	var fin := label("FIM — obrigado por jogar KelwinSouls", 22, GOLD)
	fin.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	fin.position = Vector2(-260, -80)
	c.add_child(fin)
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 2.0).from(0.0)
	tw.tween_interval(9.0)
	tw.tween_callback(func():
		close_menu()
		on_done.call())


func loading_screen(text: String) -> void:
	var c := _open("loading")
	c.add_child(panel_bg(1.0))
	var l := label(text, 28, DIM)
	_loading_label = l
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-300, -20)
	l.custom_minimum_size = Vector2(600, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(l)
	var t := label("KELWINSOULS", 56, Color(0.8, 0.7, 0.5), true)
	t.set_anchors_preset(Control.PRESET_CENTER)
	t.position = Vector2(-300, -120)
	t.custom_minimum_size = Vector2(600, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(t)


func loading_text(text: String) -> void:
	if _menu_open == "loading" and is_instance_valid(_loading_label):
		_loading_label.text = text
