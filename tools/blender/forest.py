# Prepara a floresta morta "Forrest" (kampsolutions, CC-BY-4.0) para o jogo: nivela o escaneamento,
# alinha o lado maior com o eixo z do jogo, aplica a escala, reduz polígonos e gera a grade do mapa.
# Uso: blender -b --factory-startup --python tools/blender/forest.py -- <forrest.glb> assets/forest.glb assets/forest_grid.json
#
# Blender (x, y, z) -> Babylon (-x, z, -y).
import bpy, sys, json, math, statistics
import mathutils
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index('--') + 1:]
src, dst, grid_out = argv
SCALE = 3.5          # o escaneamento tem ~8 unidades de altura: troncos ~28 m
DECIMATE = 0.5       # fração de polígonos mantida nas malhas grandes
CELL = 0.5           # metros por célula da grade de colisão
HCELL = 1.0          # metros por amostra de altura do chão
BODY = (0.9, 1.5)    # alturas acima do chão testadas contra troncos (m)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']

def bake(M):
    for o in meshes: o.data.transform(M); o.data.update()

# aplica a transformação herdada e solta dos nós do Sketchfab (no arquivo, "cima" é -Y)
for o in meshes:
    mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = Matrix.Identity(4); o.data.transform(mw)
for o in list(bpy.data.objects):
    if o.type == 'EMPTY': bpy.data.objects.remove(o, do_unlink=True)
bake(Matrix.Rotation(-math.pi / 2, 4, 'X'))
bpy.context.view_layer.update()

def build_bvh():
    verts, polys = [], []
    for o in meshes:
        b = len(verts); verts += [v.co.copy() for v in o.data.vertices]
        polys += [[b + i for i in p.vertices] for p in o.data.polygons]
    return BVHTree.FromPolygons(verts, polys), verts

def extents(verts):
    return min(v.x for v in verts), max(v.x for v in verts), min(v.y for v in verts), max(v.y for v in verts), min(v.z for v in verts), max(v.z for v in verts)

def ground_samples(bvh, verts, step):
    """chão = primeira superfície vista de baixo para cima (de cima, os raios bateriam nos galhos)"""
    x0, x1, y0, y1, z0, z1 = extents(verts); out = []
    x = x0
    while x < x1:
        y = y0
        while y < y1:
            h = bvh.ray_cast(Vector((x, y, z0 - 1)), Vector((0, 0, 1)), z1 - z0 + 2)
            if h[0] is not None: out.append(h[0].copy())
            y += step
        x += step
    return out

# 1) nivela: plano ajustado ao chão (mínimos quadrados, duas passadas para ignorar pontos soltos)
bvh, verts = build_bvh()
pts = ground_samples(bvh, verts, 0.5)
def fit(p):
    n = len(p); mx = sum(v.x for v in p) / n; my = sum(v.y for v in p) / n; mz = sum(v.z for v in p) / n
    sxx = sum((v.x - mx) ** 2 for v in p); syy = sum((v.y - my) ** 2 for v in p); sxy = sum((v.x - mx) * (v.y - my) for v in p)
    sxz = sum((v.x - mx) * (v.z - mz) for v in p); syz = sum((v.y - my) * (v.z - mz) for v in p)
    det = sxx * syy - sxy * sxy
    a = (sxz * syy - syz * sxy) / det; b = (syz * sxx - sxz * sxy) / det
    return a, b, mx, my, mz
a, b, mx, my, mz = fit(pts)
keep = [v for v in pts if abs(v.z - (mz + a * (v.x - mx) + b * (v.y - my))) < 0.6]
a, b, mx, my, mz = fit(keep)
normal = Vector((-a, -b, 1)).normalized()
print("NORMAL", normal, "tilt", math.degrees(normal.angle(Vector((0, 0, 1)))))
bake(normal.rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4())

# 2) alinha o lado maior (PCA do chão) com o eixo Y e centraliza
bvh, verts = build_bvh(); pts = ground_samples(bvh, verts, 0.5)
n = len(pts); mx = sum(v.x for v in pts) / n; my = sum(v.y for v in pts) / n
sxx = sum((v.x - mx) ** 2 for v in pts); syy = sum((v.y - my) ** 2 for v in pts); sxy = sum((v.x - mx) * (v.y - my) for v in pts)
ang = 0.5 * math.atan2(2 * sxy, sxx - syy)          # direção do eixo principal
zmed = statistics.median(v.z for v in pts)
bake(Matrix.Scale(SCALE, 4) @ Matrix.Rotation(math.pi / 2 - ang, 4, 'Z') @ Matrix.Translation(Vector((-mx, -my, -zmed))))

# 3) reduz polígonos
for o in meshes:
    if len(o.data.polygons) < 1500: continue
    m = o.modifiers.new('dec', 'DECIMATE'); m.ratio = DECIMATE
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
print("TRIS", sum(len(o.data.polygons) for o in meshes))

# 4) grade do mapa, em coordenadas do jogo
bvh, verts = build_bvh()
ex0, ex1, ey0, ey1, ez0, ez1 = extents(verts)
gx0, gx1, gz0, gz1 = -ex1, -ex0, -ey1, -ey0
nx, nz = int((gx1 - gx0) / CELL) + 1, int((gz1 - gz0) / CELL) + 1
def ground_at(x, z):
    h = bvh.ray_cast(Vector((-x, -z, ez0 - 1)), Vector((0, 0, 1)), ez1 - ez0 + 2)
    return h[0].z if h[0] is not None and h[0].z < 5 else None    # acima disso o raio passou por um buraco e bateu num tronco
H = [[ground_at(gx0 + (i + 0.5) * CELL, gz0 + (j + 0.5) * CELL) for i in range(nx)] for j in range(nz)]
def around(j, i):
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            if (di or dj) and 0 <= j + dj < nz and 0 <= i + di < nx: yield j + dj, i + di
# fecha buracos pequenos do escaneamento
for _ in range(4):
    fill = {}
    for j in range(nz):
        for i in range(nx):
            if H[j][i] is None:
                near = [H[a][b] for a, b in around(j, i) if H[a][b] is not None]
                if len(near) >= 5: fill[(j, i)] = sum(near) / len(near)
    for (j, i), v in fill.items(): H[j][i] = v

blocked = [[False] * nx for _ in range(nz)]
for j in range(nz):
    for i in range(nx):
        if H[j][i] is None: continue
        bx, by = -(gx0 + (i + 0.5) * CELL), -(gz0 + (j + 0.5) * CELL)
        # o tronco é o que existe bem acima do chão; o próprio chão fica longe dessas alturas
        blocked[j][i] = any(bvh.find_nearest(Vector((bx, by, H[j][i] + h)), CELL * 0.6)[0] is not None for h in BODY)

# afasta da borda irregular: chão só a 2 m ou mais de onde o escaneamento termina
M = int(2 / CELL); floor = [[H[j][i] is not None for i in range(nx)] for j in range(nz)]
def inner(j, i):
    return all(0 <= a < nz and 0 <= b < nx and floor[a][b] for a in range(j - M, j + M + 1) for b in range(i - M, i + M + 1))
rows = [''.join(' ' if not inner(j, i) else '#' if blocked[j][i] else '.' for i in range(nx)) for j in range(nz)]

# altura do chão: amostras a cada HCELL, com a mediana da vizinhança (ignora as raízes e os buracos dos troncos)
hx, hz = int((gx1 - gx0) / HCELL) + 2, int((gz1 - gz0) / HCELL) + 2
step = int(HCELL / CELL); R = 2
hs = []
for k in range(hz):
    row = []
    for l in range(hx):
        cj, ci = k * step, l * step
        v = [H[a][b] for a in range(cj - R, cj + R + 1) for b in range(ci - R, ci + R + 1) if 0 <= a < nz and 0 <= b < nx and H[a][b] is not None]
        row.append(round(statistics.median(v) * 100) if v else None)
    hs.append(row)
base = statistics.median(v for r in hs for v in r if v is not None)
hs = [[int(base) if v is None else int(v) for v in r] for r in hs]

json.dump({'x0': round(gx0, 3), 'z0': round(gz0, 3), 'cell': CELL, 'nx': nx, 'nz': nz, 'rows': rows, 'hcell': HCELL, 'hx': hx, 'hz': hz, 'heights': hs},
          open(grid_out, 'w'), separators=(',', ':'))
free = sum(r.count('.') for r in rows); solid = sum(r.count('#') for r in rows)
print("GRID", nx, nz, "x", round(gx0, 1), round(gx1, 1), "z", round(gz0, 1), round(gz1, 1), "free", free, "solid", solid, "y", round(ez0, 1), round(ez1, 1))
print("HEIGHT", min(min(r) for r in hs) / 100, max(max(r) for r in hs) / 100)

bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=False, export_apply=False, export_image_format='AUTO')
print("EXPORTED", dst)
