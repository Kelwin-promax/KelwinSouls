# Recorta o salão principal do "Complete Medieval Tiled Castle Interior" (Teranox, CC-BY-4.0),
# posiciona nas coordenadas do jogo e gera a grade de colisão.
# Uso: blender -b --factory-startup --python tools/blender/castle_hall.py -- <castle.glb> assets/castle_hall.glb assets/castle_hall_grid.json
#
# Blender (x, y, z) -> Babylon (-x, z, -y). A entrada em arco do salão fica em +Y no Blender,
# então ela aponta para a muralha do jogo (z menor) e a alcova gradeada fica no fundo.
import bpy, sys, json, mathutils
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index('--') + 1:]
src, dst, grid_out = argv
PIECES = ('polySurface47',)              # salão + celas gradeadas
OFFSET = mathutils.Vector((-1.92, -8.33, 0))   # centraliza o arco em x = 0 e encosta a entrada em z = 37.5
CELL = 0.5                               # metros por célula da grade

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
keep = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(PIECES)]
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o not in keep: bpy.data.objects.remove(o, do_unlink=True)
for o in keep:                           # aplica a transformação herdada e solta dos nós do Sketchfab
    mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mathutils.Matrix.Translation(OFFSET) @ mw
for o in list(bpy.data.objects):
    if o.type == 'EMPTY': bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()

# ---- grade de colisão em coordenadas do jogo: '.' chão livre, '#' parede/grade, ' ' fora do salão
dg = bpy.context.evaluated_depsgraph_get(); verts, polys = [], []
for o in keep:
    e = o.evaluated_get(dg); me = e.to_mesh(); b = len(verts)
    verts += [e.matrix_world @ v.co for v in me.vertices]; polys += [[b + i for i in p.vertices] for p in me.polygons]
bvh = BVHTree.FromPolygons(verts, polys)
gx = [-v.x for v in verts]; gz = [-v.y for v in verts]
x0, x1, z0, z1 = min(gx), max(gx), min(gz), max(gz)
nx, nz = int((x1 - x0) / CELL) + 1, int((z1 - z0) / CELL) + 1
rows = []
for j in range(nz):
    r = ''
    for i in range(nx):
        x, z = x0 + (i + 0.5) * CELL, z0 + (j + 0.5) * CELL
        bx, by = -x, -z
        hit = bvh.ray_cast(mathutils.Vector((bx, by, 1.2)), mathutils.Vector((0, 0, -1)), 2.0)
        floor = hit[0] is not None and abs(hit[0].z) < 0.6
        wall = any(bvh.find_nearest(mathutils.Vector((bx, by, h)), CELL * 0.55)[0] is not None for h in (0.6, 1.1, 1.6, 2.1))
        r += '#' if wall else ('.' if floor else ' ')
    rows.append(r)
json.dump({'x0': round(x0, 3), 'z0': round(z0, 3), 'cell': CELL, 'nx': nx, 'nz': nz, 'rows': rows}, open(grid_out, 'w'), separators=(',', ':'))
print("GRID", nx, nz, "x", round(x0, 2), round(x1, 2), "z", round(z0, 2), round(z1, 2))

bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=False, export_apply=True)
print("EXPORTED", dst)
