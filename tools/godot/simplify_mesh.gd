# Executado em modo headless pelo pipeline Python:
#   godot --headless --script simplify_mesh.gd -- <entrada.glb> <saida.ksm> <triangulos_alvo>
# Lê a malha preparada pelo Python, gera LODs com o meshoptimizer do Godot
# e grava a LOD mais próxima do alvo num binário simples (.ksm) que o Python
# transforma no GLB final.
extends SceneTree


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		printerr("uso: -- entrada.glb saida.ksm alvo_tris")
		quit(1)
		return
	var src: String = a[0]
	var dst: String = a[1]
	var target: int = int(a[2])

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(src, state)
	if err != OK:
		printerr("falha ao carregar ", src, " erro ", err)
		quit(2)
		return

	var gmesh: GLTFMesh = state.get_meshes()[0]
	var im: ImporterMesh = gmesh.mesh
	var total := 0
	for s in im.get_surface_count():
		var arr: Array = im.get_surface_arrays(s)
		total += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3

	im.generate_lods(25.0, 60.0, [])

	var f := FileAccess.open(dst, FileAccess.WRITE)
	f.store_buffer("KSM1".to_ascii_buffer())
	f.store_32(im.get_surface_count())
	var out_total := 0
	for s in im.get_surface_count():
		var arr: Array = im.get_surface_arrays(s)
		var base_idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var surf_target := int(float(target) * float(base_idx.size() / 3) / float(max(total, 1)))
		var best: PackedInt32Array = base_idx
		var lods := im.get_surface_lod_count(s)
		for l in lods:
			var idx: PackedInt32Array = im.get_surface_lod_indices(s, l)
			if idx.size() / 3 >= surf_target * 0.8:
				best = idx
			else:
				# primeira LOD abaixo do alvo: usa ela se a anterior estiver longe demais
				if best.size() / 3 > surf_target * 1.6:
					best = idx
				break
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		if uv.size() != pos.size():
			uv.resize(pos.size())
		f.store_32(pos.size())
		f.store_32(best.size())
		f.store_32(s)
		f.store_buffer(pos.to_byte_array())
		f.store_buffer(nrm.to_byte_array())
		f.store_buffer(uv.to_byte_array())
		f.store_buffer(best.to_byte_array())
		out_total += best.size() / 3
		print("superficie %d: %d -> %d tris (%d LODs)" % [s, base_idx.size() / 3, best.size() / 3, lods])
	f.close()
	print("TOTAL %d -> %d" % [total, out_total])
	quit(0)
