# Geometria arquitetônica gerada em código (Etapa 3): telhados com beirais, arcos e ameias.
# Usado pela cidadela, pelo pagode, pela forja e pelas pontes. Sem modelos externos.
class_name Arch
extends RefCounted


## Telhado de quatro águas. Os cantos da base sobem `upturn` metros (beirais curvos, como nos
## templos orientais). `center` é o centro da base, no nível do telhado.
static func hip_roof(parent: Node3D, center: Vector3, w: float, d: float, h: float, upturn: float, mat: Material) -> MeshInstance3D:
	var hw := w * 0.5
	var hd := d * 0.5
	# cantos (sobem `upturn`) e pontos médios do beiral (ficam na altura 0): o beiral forma uma curva
	var corners := [
		Vector3(-hw, upturn, -hd),
		Vector3(hw, upturn, -hd),
		Vector3(hw, upturn, hd),
		Vector3(-hw, upturn, hd),
	]
	var mids := [
		Vector3(0, 0, -hd),
		Vector3(hw, 0, 0),
		Vector3(0, 0, hd),
		Vector3(-hw, 0, 0),
	]
	var apex := Vector3(0, h, 0)
	var inside := Vector3(0, h * 0.3, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		_tri(st, corners[i], mids[i], apex, inside)
		_tri(st, mids[i], corners[(i + 1) % 4], apex, inside)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


## Adiciona um triângulo com a face voltada para fora de `inside`, e uma cópia de costas
## (dupla face: o telhado aparece também por baixo, sem depender da ordem dos vértices).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	var mid := (a + b + c) / 3.0
	if n.dot(mid - inside) < 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)


## Arco em meia-volta feito de aduelas (blocos). `center` é o centro do círculo (na linha do
## impostas), no plano XY. O arco abre para +Z ao longo da espessura `depth`.
static func arch(parent: Node3D, center: Vector3, radius: float, thickness: float, depth: float, segments: int, mat: Material) -> void:
	var arc_len := PI * radius / segments
	for i in segments:
		var a := PI * (i + 0.5) / segments
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(thickness, arc_len * 1.12, depth)
		mi.mesh = b
		mi.material_override = mat
		mi.position = center + Vector3(cos(a) * radius, sin(a) * radius, 0.0)
		mi.rotation.z = a - PI * 0.5
		parent.add_child(mi)


## Ameias (merlões) sobre um anel. Usa um MultiMesh para desenhar centenas de blocos numa chamada.
## `gap_center` / `gap_half` (radianos) deixam um vão sem ameia, para o portão.
static func merlons_ring(parent: Node3D, center: Vector3, radius: float, count: int, y_of: Callable, size: Vector3, mat: Material, gap_center := 0.0, gap_half := 0.0) -> void:
	var xforms: Array[Transform3D] = []
	for i in count:
		var a := TAU * i / count
		var da := absf(wrapf(a - gap_center, -PI, PI))
		if da < gap_half:
			continue
		var p := center + Vector3(sin(a) * radius, 0.0, cos(a) * radius)
		p.y = y_of.call(p.x, p.z)
		xforms.append(Transform3D(Basis(Vector3.UP, a), p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = size
	mm.mesh = box
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = 1400.0
	parent.add_child(mmi)
