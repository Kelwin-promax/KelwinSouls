# Gera as animações extras do knight.glb, adicionadas ao fim da ação "Take 001":
#   andar, correr, rolamento e os cortes horizontal/diagonal do jogador.
# Uso: blender -b --factory-startup --python tools/blender/knight_anims.py -- assets/knight.glb assets/knight.glb
# Quadros (24 fps no Blender = x2.5 no Babylon): ver tabela CLIPS no fim do arquivo e KNIGHT no game.js.
import bpy, sys, math
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index('--') + 1:]
src, dst = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
act = arm.animation_data.action
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and not o.name.startswith('Icosphere')]
BASE = 52                       # primeiro quadro do idle (Babylon 130)
sc.frame_set(BASE)
base = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in arm.pose.bones}
order = sorted(arm.pose.bones, key=lambda p: len(p.bone.parent_recursive))
U = 6.25                        # unidades do modelo por metro (escala 0.16 no jogo)
TAU = math.pi * 2
X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
D = math.radians
# convenções (espaço da armadura): frente = -Y, direita do personagem = -X, cima = +Z
# +X inclina para a frente; perna/braço para a frente = -X; joelho dobra = +X

def smooth(t): t = min(1.0, max(0.0, t)); return t * t * (3 - 2 * t)
def smoother(t): t = min(1.0, max(0.0, t)); return t * t * t * (t * (t * 6 - 15) + 10)

def min_z():
    dg = bpy.context.evaluated_depsgraph_get(); m = 1e9
    for o in meshes:
        e = o.evaluated_get(dg); me = e.to_mesh(); W = e.matrix_world
        m = min(m, min((W @ v.co).z for v in me.vertices)); e.to_mesh_clear()
    return m

def reset():
    for pb in arm.pose.bones:
        l, q, k = base[pb.name]; pb.location, pb.rotation_quaternion, pb.scale = l, q, k
    bpy.context.view_layer.update()

def apply(offs):
    """offs: nome -> (rots [(eixo, ângulo)], translação, pivô). Tudo em espaço da armadura,
    aplicado dos pais para os filhos sobre a pose base."""
    for pb in order:
        if pb.name not in offs: continue
        rots, tr, piv = (offs[pb.name] + (None, None))[:3]
        M = pb.matrix.copy(); h = piv if piv is not None else pb.head.copy()
        W = Matrix.Identity(4)
        for ax, a in rots: W = Matrix.Rotation(a, 4, ax.normalized()) @ W
        W = Matrix.Translation(h) @ W @ Matrix.Translation(-h)
        if tr is not None: W = Matrix.Translation(tr) @ W
        P = M @ pb.matrix_basis.inverted()                 # parte vinda dos pais/rest
        Dm = P.inverted() @ W @ P                          # delta rígido no espaço local do osso
        R = Dm.to_3x3().normalized().to_quaternion()
        pb.location = Dm @ pb.location
        pb.rotation_quaternion = (R @ pb.rotation_quaternion).normalized()
        bpy.context.view_layer.update()

def bake(start, n, posefn, loop=False, ground=False):
    prev = None
    sc.frame_set(BASE); reset(); z0 = min_z()
    for i in range(n + 1):
        f = start + i
        u = (i % n) / n if loop else i / n
        reset(); apply(posefn(u))
        if ground:                                         # mantém o corpo apoiado no chão
            dz = z0 - min_z()
            if abs(dz) > 1e-4: apply({'_rootJoint': ([], Vector((0, 0, dz)))})
        for pb in arm.pose.bones:
            if prev is not None and pb.rotation_quaternion.dot(prev[pb.name]) < 0:
                pb.rotation_quaternion.negate()           # mantém continuidade dos quaternions
            for p in ('location', 'rotation_quaternion', 'scale'):
                pb.keyframe_insert(p, frame=f, group=pb.name)
        prev = {pb.name: pb.rotation_quaternion.copy() for pb in arm.pose.bones}

# ------------------------------ andar / correr ------------------------------
def gait(g):
    def pose(ph):
        s, c = math.sin(TAU * ph), math.cos(TAU * ph)
        cs = math.cos(TAU * (ph + 0.07)); csl = -cs        # joelho dobra no começo do balanço
        sl = -s                                            # perna esquerda meio ciclo depois
        knee = lambda cc: g['knee'] * max(0.0, cc) ** 1.3 + g['kneeBase']
        hipR, hipL = -g['hip'] * s, -g['hip'] * sl
        kR, kL = knee(cs), knee(csl)
        bob = g['bob'] * math.cos(2 * TAU * ph) - g['drop']
        twist = g['twist'] * s
        return {
            '_rootJoint':     ([], Vector((0, 0, bob * U))),
            'Body_Low_01':    ([(Z, twist)], None),
            'Body_High_02':   ([(X, g['lean']), (Z, -2.2 * twist)], None),
            'Head_03':        ([(X, -g['lean'] * 0.6), (Z, 1.2 * twist)], None),
            'Leg_High_R_039': ([(X, hipR - g['hipBias'])], None),
            'Leg_High_L_042': ([(X, hipL - g['hipBias'])], None),
            'Leg_Low_R_040':  ([(X, kR)], None),
            'Leg_Low_L_043':  ([(X, kL)], None),
            'Foot_R_041':     ([(X, -(hipR + kR) * 0.7 + g['toe'] * max(0.0, -s) * max(0.0, c))], None),
            'Foot_L_044':     ([(X, -(hipL + kL) * 0.7 + g['toe'] * max(0.0, -sl) * max(0.0, -c))], None),
            'Arm_High_R_04':  ([(X, g['arm'] * s + g['armBias'])], None),   # braço direito vai com a perna esquerda
            'Arm_High_L_021': ([(X, -g['arm'] * 0.45 * s)], None),          # escudo balança menos
            'Arm_Low_R_05':   ([(X, -g['elbow'] * (0.5 + 0.5 * s))], None),
        }
    return pose

WALK = dict(hip=D(26), hipBias=D(2), knee=D(40), kneeBase=D(6), toe=D(18), bob=0.025, drop=0.02,
            twist=D(5), lean=D(4), arm=D(18), armBias=D(0), elbow=D(8))
RUN  = dict(hip=D(40), hipBias=D(8), knee=D(85), kneeBase=D(14), toe=D(25), bob=0.05, drop=0.07,
            twist=D(8), lean=D(14), arm=D(32), armBias=D(-10), elbow=D(18))

# ------------------------------ rolamento ------------------------------
# cambalhota para a frente por cima do ombro: o corpo se encolhe (coluna, quadril, joelhos,
# braços) e o conjunto gira 360° em torno do centro de massa, sempre apoiado no chão.
CENTER = Vector((0, 0, 5.0))    # centro de massa aproximado na pose base (~0.8 m)
def roll(u):
    tuck = smooth(u / 0.2) * (1 - smooth((u - 0.7) / 0.3))
    spin = TAU * smoother((u - 0.06) / 0.72)
    side = D(22) * math.sin(math.pi * smooth((u - 0.05) / 0.8))    # rola pelo ombro direito
    dive = D(18) * smooth(u / 0.12) * (1 - smooth((u - 0.12) / 0.2))   # mergulho inicial
    rise = D(14) * smooth((u - 0.72) / 0.12) * (1 - smooth((u - 0.86) / 0.14))   # sai agachado
    return {
        '_rootJoint':     ([(X, spin), (Y, side)], None, CENTER),
        'Body_Low_01':    ([(X, D(18) * tuck)], None),
        'Body_High_02':   ([(X, D(48) * tuck + dive + rise)], None),
        'Head_03':        ([(X, D(38) * tuck)], None),
        'Leg_High_R_039': ([(X, -D(105) * tuck)], None),
        'Leg_High_L_042': ([(X, -D(92) * tuck)], None),
        'Leg_Low_R_040':  ([(X, D(125) * tuck)], None),
        'Leg_Low_L_043':  ([(X, D(118) * tuck)], None),
        'Foot_R_041':     ([(X, -D(25) * tuck)], None),
        'Foot_L_044':     ([(X, -D(25) * tuck)], None),
        'Arm_High_R_04':  ([(X, -D(45) * tuck), (Z, D(20) * tuck)], None),
        'Arm_Low_R_05':   ([(X, -D(35) * tuck)], None),
        'Arm_High_L_021': ([(X, -D(35) * tuck), (Z, -D(15) * tuck)], None),  # escudo junto ao corpo
    }

# ------------------------------ cortes ------------------------------
# o braço da espada gira no ombro em torno do eixo n = frente x d, levando a lâmina de d
# (preparação) para -d (fim do golpe); o tronco acompanha parte do giro.
def slash(d, keys, torso=0.35, hips=0.12, step=D(10)):
    f = Vector((0, -1, 0)); d = d.normalized(); n = f.cross(d).normalized()
    def phi(u):                                       # interpola as chaves (u, ângulo) suavemente
        for (u0, a0), (u1, a1) in zip(keys, keys[1:]):
            if u <= u1: return a0 + (a1 - a0) * smooth((u - u0) / max(u1 - u0, 1e-6))
        return keys[-1][1]
    def pose(u):
        a = phi(u); k = abs(a) / D(110)
        return {
            'Body_Low_01':    ([(n, a * hips)], None),
            'Body_High_02':   ([(n, a * torso), (X, D(10) * k)], None),
            'Head_03':        ([(n, -a * torso * 0.6)], None),
            'Arm_High_R_04':  ([(n, a * (1 - torso - hips))], None),
            'Arm_Low_R_05':   ([(X, -D(25) * max(0.0, a) / D(110))], None),     # cotovelo recolhe na preparação
            'Leg_High_R_039': ([(X, -step * k)], None),                          # pequeno passo de apoio
            'Leg_Low_R_040':  ([(X, step * 1.2 * k)], None),
            'Leg_High_L_042': ([(X, step * 0.6 * k)], None),
            'Arm_High_L_021': ([(n, -a * 0.15)], None),
        }
    return pose

# chaves em fração do clipe (30 quadros): 0-8 prepara, 8-11 golpe, 11-16 fim, 16-30 volta
SWING = [(0, 0), (8 / 30, D(105)), (11 / 30, D(-65)), (16 / 30, D(-85)), (1, 0)]
HSLASH = slash(Vector((-1, 0, 0.05)), SWING)               # da direita para a esquerda, na altura do peito
DSLASH = slash(Vector((-1, 0, 1.1)), SWING, torso=0.3)     # de cima/direita para baixo/esquerda

CLIPS = [  # (início, quadros, pose, loop, chão)    Babylon = Blender x 2.5
    (150, 24, gait(WALK), True,  False),   # andar    375-435
    (180, 16, gait(RUN),  True,  False),   # correr   450-490
    (200, 14, roll,       False, True),    # rolar    500-535
    (220, 30, HSLASH,     False, False),   # corte H  550-625 (golpe 570-577.5)
    (260, 30, DSLASH,     False, False),   # corte D  650-725 (golpe 670-677.5)
]
for c in CLIPS: bake(*c)
print("RANGE", act.frame_range)
sc.frame_start, sc.frame_end = 0, int(act.frame_range[1])
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=True, export_force_sampling=True,
                          export_frame_range=False, export_optimize_animation_size=False, export_apply=False)
print("EXPORTED", dst)
