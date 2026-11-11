# NPC com diálogo ramificado (Etapa 4). Os textos ficam em DIALOGUES; cada nó tem
# "text", "options" ([{label, id}]) e opcionalmente "effect" (nome de um efeito em _apply_effect).
# id "end" encerra a conversa. Estado persistente em Game.npc_flags.
class_name Npc
extends Node3D

const TALK_RANGE := 3.2

const DIALOGUES := {
	"vesper": {
		"start": {
			"text": "Você ainda respira, Maculado. Os outros já esqueceram o próprio nome. Eu sou a Irmã Vesper, do Juramento Velado. Guardo a última fogueira deste vale.",
			"options": [
				{"label": "Quem é você, de fato?", "id": "quem"},
				{"label": "Onde estou?", "id": "onde"},
				{"label": "Preciso ir.", "id": "end"},
			],
		},
		"quem": {
			"text": "Juramentada à Chama antes de a Cidadela cair. Os cavaleiros de Marfim juraram proteger as Brasas e, um a um, enlouqueceram com elas.",
			"options": [
				{"label": "Como posso ajudar?", "id": "ajuda"},
				{"label": "Voltar", "id": "start"},
			],
		},
		"onde": {
			"text": "O Vale das Brasas Caídas. Ao norte, a Cidadela de Marfim. Entre ruínas e pântanos, as Grandes Brasas repousam com os chefes que as guardam.",
			"options": [
				{"label": "Voltar", "id": "start"},
			],
		},
		"ajuda": {
			"text": "Traga-me a prova de que você enfrentou um dos guardiões. Quando sua lâmina vencer um deles, eu abençoarei suas lágrimas.",
			"options": [
				{"label": "Pedir a bênção", "id": "bencao"},
				{"label": "Voltar", "id": "start"},
			],
		},
		"bencao": {
			"text": "Que a Chama ilumine seu caminho. Tome: uma nova Lágrima Ígnea, abençoada pela fé.",
			"effect": "vesper_bencao",
			"once": "vesper_bencao",
			"after": "bencao_feita",
			"options": [
				{"label": "Obrigado, Irmã.", "id": "end"},
			],
		},
		"bencao_feita": {
			"text": "A bênção já foi concedida. Que a Chama o acompanhe.",
			"options": [
				{"label": "Até logo.", "id": "end"},
			],
		},
	},
	"ferreiro": {
		"start": {
			"text": "Mais uma alma reacendida perto da minha forja. Nunca apague o fogo, Maculado. O ferro dos heróis sempre quebra antes da fé.",
			"options": [
				{"label": "Quem era você?", "id": "quem"},
				{"label": "Até logo.", "id": "end"},
			],
		},
		"quem": {
			"text": "Ferreiro da Ordem de Marfim. Forjei a espada que Ivorae usou no primeiro juramento. Depois descobri o que a Rainha fazia com o aço, e fugi para cá.",
			"options": [
				{"label": "Voltar", "id": "start"},
			],
		},
	},
}

const NAMES := {"vesper": "Irmã Vesper", "ferreiro": "Ferreiro Cinzento"}

var npc_id := ""
var display_name := ""
var rig: ModelRig
var _talking := false
var _near := false
var _t := 0.0


func setup(id: String, pos: Vector3, model_name := "") -> void:
	npc_id = id
	display_name = NAMES.get(id, id)
	position = pos
	if model_name != "":
		rig = ModelRig.new()
		add_child(rig)
		rig.build(model_name)
	else:
		_build_blacksmith()


func _ready() -> void:
	add_to_group("npcs")


func _build_blacksmith() -> void:
	# sem modelo humanoide próprio: figura de primitivas com avental e martelo
	rig = ModelRig.new()
	add_child(rig)
	var pose := Node3D.new()
	rig.add_child(pose)
	rig.pose = pose
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.22, 0.2, 0.19)
	cloth.roughness = 0.95
	var apron := StandardMaterial3D.new()
	apron.albedo_color = Color(0.36, 0.22, 0.14)
	apron.roughness = 0.8
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.5, 0.38, 0.3)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.5, 0.5, 0.52)
	steel.metallic = 0.9
	steel.roughness = 0.3
	_mesh(pose, _cap(0.3, 0.9), cloth, Vector3(0, 0.95, 0))
	_mesh(pose, _box(Vector3(0.42, 0.7, 0.05)), apron, Vector3(0, 0.75, -0.3))
	_mesh(pose, _sphere(0.2), skin, Vector3(0, 1.75, 0))
	_mesh(pose, _cap(0.09, 0.7), cloth, Vector3(-0.42, 1.05, 0), Vector3(0, 0, 0.2))
	_mesh(pose, _cap(0.09, 0.7), cloth, Vector3(0.42, 1.05, 0), Vector3(0, 0, -0.2))
	_mesh(pose, _cap(0.1, 0.8), cloth, Vector3(-0.16, 0.35, 0))
	_mesh(pose, _cap(0.1, 0.8), cloth, Vector3(0.16, 0.35, 0))
	# martelo na mão direita
	_mesh(pose, _box(Vector3(0.08, 0.5, 0.08)), apron, Vector3(0.5, 0.9, -0.1))
	_mesh(pose, _box(Vector3(0.22, 0.14, 0.14)), steel, Vector3(0.5, 1.2, -0.1))
	rig.height = 1.9
	rig.radius = 0.35


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _process(delta: float) -> void:
	_t += delta
	if rig:
		rig.tick(delta, 0.0, 0.0, true)
	var p := Game.player as Player
	if p == null:
		return
	var near := p.global_position.distance_to(global_position) < TALK_RANGE and not _talking
	if near != _near:
		_near = near
		if Game.hud:
			if near:
				Game.hud.set_prompt("[E] Conversar com %s" % display_name)
			else:
				Game.hud.set_prompt("")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _near:
		return
	var p := Game.player as Player
	if p == null or p.is_busy():
		return
	# a conversa pode ter sido encerrada pela pausa; libera o estado
	if _talking and not Game.hud.is_menu_open():
		_talking = false
	if _talking:
		return
	get_viewport().set_input_as_handled()
	_talking = true
	_near = false
	Game.hud.set_prompt("")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show("start")


func _show(node_id: String) -> void:
	var node: Dictionary = DIALOGUES[npc_id][node_id]
	if node.has("once") and Game.npc_flags.get(node.once, false):
		node = DIALOGUES[npc_id][node.after]
	if node.has("effect"):
		_apply_effect(node.effect)
	var opts: Array = []
	for o in node.options:
		opts.append(o)
	Game.hud.dialogue_menu(display_name, node.text, opts, func(next: String):
		if next == "end":
			Game.hud.close_menu()
			_end()
		else:
			_show(next))


func _end() -> void:
	_talking = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_effect(effect: String) -> void:
	match effect:
		"vesper_bencao":
			if Game.npc_flags.get("vesper_bencao", false):
				return
			Game.npc_flags["vesper_bencao"] = true
			Game.flasks_max += 1
			Game.flasks = Game.flasks_max
			Game.flasks_changed.emit(Game.flasks)
			Game.message("Lágrimas Ígneas aumentadas para %d" % Game.flasks_max, "item")
			Game.save_game()
