"""Rigging e animação de personagens humanoides do KelwinSouls (Etapa 2), com Blender em modo headless.

Para cada .glb de entrada:
  1. importa e junta as malhas, aplica as transformações e mede o corpo (altura e larguras);
  2. ajusta um esqueleto humanoide às proporções medidas (quadril, joelhos, ombros, cotovelos,
     mãos, coluna e cabeça), com os lados laterais tirados das seções transversais da malha;
  3. prende a malha ao esqueleto com pesos automáticos (heat map do Blender);
  4. cria as ações: idle, walk, run, attack_light, attack_heavy, hit e death;
  5. exporta .glb com esqueleto e animações (o Godot importa cada ação como uma animação).

Uso (a partir da raiz do projeto):
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b -P tools/rig/rig_humanoid.py -- \
      --in game/assets/models/ravenkor__the_bloodsteel_duelist.glb \
      --out game/assets/models/ravenkor__the_bloodsteel_duelist__rig.glb \
      [--preview build/rig_preview/ravenkor.png]

O --preview renderiza um quadro de cada ação em grade, para conferir visualmente o resultado.
"""
import math
import os
import sys

import bpy
from mathutils import Vector


def args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    out = {"in": None, "out": None, "preview": None}
    i = 0
    while i < len(argv):
        k = argv[i].lstrip("-")
        if k in out and i + 1 < len(argv):
            out[k] = argv[i + 1]
            i += 2
        else:
            i += 1
    if not out["in"] or not out["out"]:
        raise SystemExit("uso: -- --in entrada.glb --out saida.glb [--preview png]")
    return out


def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    bpy.ops.import_scene.gltf(filepath=path)


def join_meshes():
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("o arquivo não tem malhas")
    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return body


def world_points(obj):
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def measure(pts):
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    zs = [p.z for p in pts]
    lo = Vector((min(xs), min(ys), min(zs)))
    hi = Vector((max(xs), max(ys), max(zs)))
    return lo, hi


def lateral_centroid(pts, z_lo, z_hi, cx, side, min_off):
    """Centroide das vértices de um lado (side = -1 esquerda, +1 direita) numa faixa de altura."""
    sel = [p for p in pts if z_lo <= p.z <= z_hi and side * (p.x - cx) > min_off]
    if not sel:
        return None
    n = len(sel)
    return Vector((sum(p.x for p in sel) / n, sum(p.y for p in sel) / n, sum(p.z for p in sel) / n))


def fit_joints(pts, lo, hi):
    """Estima as articulações a partir das proporções e dos centroides laterais da malha."""
    H = hi.z - lo.z
    W = hi.x - lo.x
    cx = (lo.x + hi.x) * 0.5
    cy = (lo.y + hi.y) * 0.5
    z0 = lo.z
    J = {}

    def at(fz, fx=0.0, fy=0.0):
        return Vector((cx + fx, cy + fy, z0 + fz))

    # pernas: centroide de cada lado numa faixa de altura da coxa e da canela
    for side, nm in ((-1, "l"), (1, "r")):
        thigh = lateral_centroid(pts, z0 + H * 0.40, z0 + H * 0.52, cx, side, W * 0.04)
        calf = lateral_centroid(pts, z0 + H * 0.16, z0 + H * 0.26, cx, side, W * 0.03)
        hx = abs(thigh.x - cx) if thigh else W * 0.12
        ax = abs(calf.x - cx) if calf else hx * 0.9
        J[f"hip_{nm}"] = Vector((cx + side * hx, cy, z0 + H * 0.50))
        J[f"knee_{nm}"] = Vector((cx + side * (hx + ax) * 0.5, cy, z0 + H * 0.27))
        J[f"ankle_{nm}"] = Vector((cx + side * ax, cy, z0 + H * 0.04))
        J[f"toe_{nm}"] = Vector((cx + side * ax, cy - H * 0.06, z0 + H * 0.005))
    # braços: ombro, cotovelo e punho a partir dos extremos laterais em cada faixa
    for side, nm in ((-1, "l"), (1, "r")):
        sh = lateral_centroid(pts, z0 + H * 0.76, z0 + H * 0.86, cx, side, W * 0.12)
        el = lateral_centroid(pts, z0 + H * 0.55, z0 + H * 0.66, cx, side, W * 0.18)
        wr = lateral_centroid(pts, z0 + H * 0.40, z0 + H * 0.50, cx, side, W * 0.22)
        sx = abs(sh.x - cx) if sh else W * 0.3
        ex = abs(el.x - cx) if el else sx * 1.1
        wx = abs(wr.x - cx) if wr else ex * 1.05
        J[f"shoulder_{nm}"] = Vector((cx + side * sx * 0.9, cy, z0 + H * 0.80))
        J[f"elbow_{nm}"] = Vector((cx + side * ex, cy, z0 + H * 0.61))
        J[f"wrist_{nm}"] = Vector((cx + side * wx, cy, z0 + H * 0.45))
    # tronco e cabeça
    J["pelvis"] = at(H * 0.52)
    J["spine"] = at(H * 0.62)
    J["chest"] = at(H * 0.72)
    J["neck"] = at(H * 0.84)
    J["head"] = at(H * 0.90)
    J["head_top"] = at(H * 1.0)
    return J


def build_armature(J):
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm_obj = bpy.context.view_layer.objects.active
    arm_obj.name = "Rig"
    arm = arm_obj.data
    arm.name = "RigData"
    eb = arm.edit_bones
    eb.remove(eb[0])

    def bone(name, head, tail, parent=None, connect=False):
        b = eb.new(name)
        b.head = head
        b.tail = tail
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        return b

    bone("pelvis", J["pelvis"], J["spine"], None)
    bone("spine", J["spine"], J["chest"], "pelvis", True)
    bone("chest", J["chest"], J["neck"], "spine", True)
    bone("neck", J["neck"], J["head"], "chest", True)
    bone("head", J["head"], J["head_top"], "neck", True)
    for nm in ("l", "r"):
        bone(f"thigh_{nm}", J[f"hip_{nm}"], J[f"knee_{nm}"], "pelvis")
        bone(f"calf_{nm}", J[f"knee_{nm}"], J[f"ankle_{nm}"], f"thigh_{nm}", True)
        bone(f"foot_{nm}", J[f"ankle_{nm}"], J[f"toe_{nm}"], f"calf_{nm}", True)
        bone(f"upper_arm_{nm}", J[f"shoulder_{nm}"], J[f"elbow_{nm}"], "chest")
        bone(f"forearm_{nm}", J[f"elbow_{nm}"], J[f"wrist_{nm}"], f"upper_arm_{nm}", True)
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def _seg_dist(p, a, b):
    ab = b - a
    L2 = ab.length_squared
    t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, (p - a).dot(ab) / L2))
    return (p - (a + ab * t)).length


def bind(body, arm_obj):
    """Pesos por proximidade: cada vértice segue os ossos mais próximos, com queda suave.

    Os pesos automáticos do Blender (heat map) falham em malhas abertas, como armaduras em
    camadas (vértices sem peso), então os pesos são calculados aqui e sempre existem.
    """
    aw = arm_obj.matrix_world
    bones = []
    for b in arm_obj.data.bones:
        h = aw @ b.head_local
        t = aw @ b.tail_local
        bones.append((b.name, h, t, max(0.07, 0.32 * (t - h).length)))
    for name, _, _, _ in bones:
        if name not in body.vertex_groups:
            body.vertex_groups.new(name=name)
    groups = {name: body.vertex_groups[name] for name, _, _, _ in bones}
    bw = body.matrix_world
    for v in body.data.vertices:
        wp = bw @ v.co
        cand = []
        for name, h, t, sigma in bones:
            d = _seg_dist(wp, h, t)
            cand.append((math.exp(-(d * d) / (2.0 * sigma * sigma)), name))
        cand.sort(reverse=True)
        top = cand[:4]
        total = sum(w for w, _ in top) or 1.0
        for w, name in top:
            if w / total > 0.01:
                groups[name].add([v.index], w / total, "REPLACE")
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    mod.use_vertex_groups = True
    body.parent = arm_obj
    body.matrix_parent_inverse = arm_obj.matrix_world.inverted()


# ------------------------------------------------------------------ ações
def pose(arm_obj):
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    return arm_obj.pose.bones


def key_rot(pb, frame, x=0.0, y=0.0, z=0.0):
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = (x, y, z)
    pb.keyframe_insert(data_path="rotation_euler", frame=frame)


def key_loc(pb, frame, x=0.0, y=0.0, z=0.0):
    pb.location = (x, y, z)
    pb.keyframe_insert(data_path="location", frame=frame)


def new_action(arm_obj, name):
    act = bpy.data.actions.new(name)
    arm_obj.animation_data_create()
    arm_obj.animation_data.action = act
    return act


def clear_pose(pbs):
    for pb in pbs:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)


def action_idle(arm_obj, pbs):
    act = new_action(arm_obj, "idle")
    n = 60
    for f, s in ((1, 0.0), (n // 2, 1.0), (n + 1, 0.0)):
        key_rot(pbs["chest"], f, x=0.025 * s)
        key_rot(pbs["head"], f, x=-0.01 * s)
        key_rot(pbs["upper_arm_l"], f, x=0.04 * s)
        key_rot(pbs["upper_arm_r"], f, x=0.04 * s)
    act.use_fake_user = True
    return act


def gait(arm_obj, pbs, name, stride, arm_swing, bob, frames):
    act = new_action(arm_obj, name)
    half = frames // 2
    for f, phase in ((1, 0), (half // 2 + 1, 1), (half + 1, 2), (half + half // 2 + 1, 3), (frames + 1, 4)):
        s = [1.0, 0.0, -1.0, 0.0, 1.0][phase]
        key_rot(pbs["thigh_l"], f, x=stride * s)
        key_rot(pbs["thigh_r"], f, x=-stride * s)
        key_rot(pbs["calf_l"], f, x=max(0.0, -s) * stride * 0.9)
        key_rot(pbs["calf_r"], f, x=max(0.0, s) * stride * 0.9)
        key_rot(pbs["upper_arm_l"], f, x=-arm_swing * s)
        key_rot(pbs["upper_arm_r"], f, x=arm_swing * s)
        key_rot(pbs["chest"], f, z=0.03 * s)
        key_loc(pbs["pelvis"], f, z=bob * abs(math.cos(phase * math.pi / 2)))
    act.use_fake_user = True
    return act


def action_attack(arm_obj, pbs, name, power):
    act = new_action(arm_obj, name)
    seq = [(1, 0.0), (14, -1.6 * power), (22, 1.1 * power), (34, 0.0)]
    for f, a in seq:
        key_rot(pbs["upper_arm_r"], f, x=a, y=0.0)
        key_rot(pbs["forearm_r"], f, x=-0.5 * abs(a) / max(power, 0.01))
        key_rot(pbs["chest"], f, z=-0.35 * a / max(power, 0.01) * 0.3, x=0.12 * a / max(power, 0.01) * 0.2)
        key_rot(pbs["spine"], f, z=-0.2 * a / max(power, 0.01) * 0.3)
    act.use_fake_user = True
    return act


def action_hit(arm_obj, pbs):
    act = new_action(arm_obj, "hit")
    for f, a in ((1, 0.0), (5, -0.35), (16, 0.0)):
        key_rot(pbs["chest"], f, x=a)
        key_rot(pbs["head"], f, x=a * 0.6)
    act.use_fake_user = True
    return act


def action_death(arm_obj, pbs):
    act = new_action(arm_obj, "death")
    for f, k in ((1, 0.0), (20, 0.35), (50, 0.8), (60, 1.0)):
        key_rot(pbs["chest"], f, x=-1.0 * k, z=0.25 * k)
        key_rot(pbs["spine"], f, x=-0.3 * k)
        key_rot(pbs["head"], f, x=-0.4 * k)
        key_rot(pbs["thigh_l"], f, x=0.9 * k)
        key_rot(pbs["thigh_r"], f, x=0.5 * k)
        key_rot(pbs["calf_l"], f, x=-0.4 * k)
        key_rot(pbs["upper_arm_l"], f, x=-0.6 * k)
        key_rot(pbs["upper_arm_r"], f, x=0.9 * k)
        key_loc(pbs["pelvis"], f, z=-0.25 * k)
    act.use_fake_user = True
    return act


def make_actions(arm_obj):
    pbs = pose(arm_obj)
    actions = {}
    clear_pose(pbs)
    actions["idle"] = action_idle(arm_obj, pbs)
    actions["walk"] = gait(arm_obj, pbs, "walk", 0.42, 0.3, 0.02, 40)
    actions["run"] = gait(arm_obj, pbs, "run", 0.7, 0.6, 0.05, 26)
    actions["attack_light"] = action_attack(arm_obj, pbs, "attack_light", 1.0)
    actions["attack_heavy"] = action_attack(arm_obj, pbs, "attack_heavy", 1.6)
    actions["hit"] = action_hit(arm_obj, pbs)
    actions["death"] = action_death(arm_obj, pbs)
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_obj.animation_data.action = None
    return actions


def export(path, arm_obj, body, actions):
    # cada ação vira uma animação no .glb (o Godot importa pelo nome)
    arm_obj.animation_data_create()
    bpy.ops.object.select_all(action="DESELECT")
    arm_obj.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_skins=True,
        export_apply=False,
        export_yup=True,
    )


def preview(path, arm_obj, body, actions):
    """Renderiza uma grade de quadros (idle/walk/attack/death) para conferir a animação."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1200
    scene.render.image_settings.file_format = "PNG"
    cam_data = bpy.data.cameras.new("PrevCam")
    cam = bpy.data.objects.new("PrevCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    lo, hi = measure(world_points(body))
    H = hi.z - lo.z
    cam.location = Vector((0, -H * 2.6, H * 0.6))
    cam.rotation_euler = (math.radians(84), 0, 0)
    light = bpy.data.lights.new("PrevSun", "SUN")
    light.energy = 3.0
    lo_obj = bpy.data.objects.new("PrevSun", light)
    scene.collection.objects.link(lo_obj)
    lo_obj.rotation_euler = (math.radians(50), 0, math.radians(30))
    base, ext = os.path.splitext(path)
    shots = [("idle", 20), ("walk", 10), ("attack_light", 16), ("death", 58)]
    for name, frame in shots:
        arm_obj.animation_data.action = actions[name]
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(dg)
        vs = ev.data.vertices
        mid = sum((v.co.z for v in vs), 0.0) / max(len(vs), 1)
        print(f"POSE {name} f={frame} verts={len(vs)} mean_z={round(mid, 4)} bbox={[round(c, 2) for c in ev.bound_box[6]]}")
        scene.render.filepath = f"{base}_{name}{ext}"
        bpy.ops.render.render(write_still=True)
    arm_obj.animation_data.action = None


def main():
    a = args()
    clean_scene()
    import_glb(a["in"])
    body = join_meshes()
    lo, hi = measure(world_points(body))
    pts = world_points(body)
    J = fit_joints(pts, lo, hi)
    arm_obj = build_armature(J)
    bind(body, arm_obj)
    mods = [m.type for m in body.modifiers]
    print(f"BIND grupos={len(body.vertex_groups)} modificadores={mods}")
    for m in body.modifiers:
        if m.type == "ARMATURE":
            print(f"MOD obj={m.object.name if m.object else None} vg={m.use_vertex_groups} env={m.use_bone_envelopes}")
    weighted = sum(1 for v in body.data.vertices if len(v.groups) > 0)
    print(f"PESOS vertices_com_peso={weighted} de {len(body.data.vertices)}")
    actions = make_actions(arm_obj)
    print("ACOES " + ", ".join(f"{k}={len(v.fcurves)}" for k, v in actions.items()))
    if a["preview"]:
        preview(a["preview"], arm_obj, body, actions)
    export(a["out"], arm_obj, body, actions)
    print(f"RIG OK {a['out']} altura={hi.z - lo.z:.2f} largura={hi.x - lo.x:.2f}")


if __name__ == "__main__":
    main()
