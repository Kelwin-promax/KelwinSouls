"""Gerador do mundo de KelwinSouls: As Terras de Kelwin (8 km x 8 km).

Saídas em game/assets/world/:
  height.bin    float32 (N x N), altura em metros, célula de CELL metros
  splat0.png    RGBA: grama, terra/trilha, rocha, neve
  splat1.png    RGBA: cinza vulcânica, lama do pântano, solo de ossos, solo carmesim
  map.png       mapa ilustrado (tela de mapa do jogo)
  world.json    regiões, Graças, chefes, inimigos e props

Uso:  python tools/gen_world.py [semente]
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from catalog import CATALOG  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "world")

N = 2049            # amostras por lado
CELL = 4.0          # metros por célula  → 8192 m
SIZE = (N - 1) * CELL
HALF = SIZE / 2
WATER = 22.0        # nível da água

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 1337
rng = np.random.default_rng(SEED)

# coordenadas de mundo (x para leste, z para sul) — igual ao Godot
lin = np.linspace(-HALF, HALF, N)
X, Z = np.meshgrid(lin, lin)          # X[i, j] = x da coluna j ; Z[i, j] = z da linha i


# ------------------------------------------------------------------ ruído
def _grad_noise(x, y, perm, grads):
    xi = np.floor(x).astype(np.int64)
    yi = np.floor(y).astype(np.int64)
    xf, yf = x - xi, y - yi
    u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
    v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)

    def g(ix, iy, dx, dy):
        h = perm[(perm[ix & 255] + iy) & 255]
        gr = grads[h]
        return gr[..., 0] * dx + gr[..., 1] * dy

    n00 = g(xi, yi, xf, yf)
    n10 = g(xi + 1, yi, xf - 1, yf)
    n01 = g(xi, yi + 1, xf, yf - 1)
    n11 = g(xi + 1, yi + 1, xf - 1, yf - 1)
    return (n00 * (1 - u) + n10 * u) * (1 - v) + (n01 * (1 - u) + n11 * u) * v


def fbm(scale, octaves=6, lac=2.0, gain=0.5, ridged=False, seed_off=0):
    r = np.random.default_rng(SEED + seed_off)
    perm = r.permutation(256)
    ang = r.uniform(0, 2 * np.pi, 256)
    grads = np.stack([np.cos(ang), np.sin(ang)], -1)
    total = np.zeros_like(X)
    amp, freq, norm = 1.0, 1.0 / scale, 0.0
    ox, oz = r.uniform(0, 1000, 2)
    for _ in range(octaves):
        n = _grad_noise(X * freq + ox, Z * freq + oz, perm, grads)
        if ridged:
            n = 1.0 - np.abs(n * 1.4)
            n = n * n
        total += n * amp
        norm += amp
        amp *= gain
        freq *= lac
    return total / norm


def blob(cx, cz, r, power=2.0):
    d = np.sqrt((X - cx) ** 2 + (Z - cz) ** 2) / r
    return np.clip(1 - d, 0, 1) ** power


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ regiões
REGIONS = {
    "vale_inicial":     dict(name="Vale das Brasas Caídas", c=(0, 2900), r=1300, color=(96, 122, 64)),
    "cemiterio":        dict(name="Ossuário de Ghelm", c=(-2500, 2300), r=1000, color=(110, 104, 96)),
    "pantano_espinhos": dict(name="Pântano dos Espinhos", c=(-2900, -300), r=1300, color=(70, 82, 58)),
    "cidadela_marfim":  dict(name="Cidadela de Marfim", c=(0, -1100), r=900, color=(170, 160, 140)),
    "fornalha":         dict(name="A Grande Fornalha", c=(2800, 300), r=1300, color=(80, 50, 40)),
    "abismo_obsidiana": dict(name="Abismo de Obsidiana", c=(2400, -2700), r=1000, color=(40, 36, 48)),
    "picos_gelidos":    dict(name="Picos do Véu Gélido", c=(-2300, -2800), r=1300, color=(210, 220, 230)),
    "pagode_carmesim":  dict(name="Pagode Carmesim", c=(2500, 2700), r=1000, color=(120, 40, 40)),
}

CACHE = os.path.join(ROOT, "build", f"relief_{SEED}.npz")
_cached = os.path.exists(CACHE) and "--fresh" not in sys.argv
if _cached:
    print("relevo em cache:", CACHE)
    _c = np.load(CACHE)
    h, mt, sw, ad, pg, noise_detail = (_c[k] for k in ("h", "mt", "sw", "ad", "pg", "nd"))
else:
    print("gerando relevo (lento na primeira vez)...")
    h = 55 + fbm(900, 6) * 45 + fbm(220, 4, seed_off=3) * 10
    # vale inicial: prados suaves
    h = h * (1 - 0.5 * blob(0, 2900, 1500, 1)) + 45 * blob(0, 2900, 1500, 1) * 0.5
    # cemitério: morros
    h += blob(-2500, 2300, 1100, 1.5) * (40 + fbm(300, 4, seed_off=5) * 40)
    # pântano: baixada alagada
    sw = blob(-2900, -300, 1500, 1.2)
    h = h * (1 - sw) + (WATER - 3 + fbm(150, 4, seed_off=7) * 8) * sw
    # cidadela: platô alto com penhascos
    pl = smoothstep(0.0, 0.25, blob(0, -1100, 1000, 1.0))
    h = h * (1 - pl) + (190 + fbm(400, 3, seed_off=9) * 6) * pl
    # picos gelados: montanhas serrilhadas
    mt = blob(-2300, -2800, 1700, 1.3)
    h += mt * (200 + fbm(700, 7, ridged=True, seed_off=11) * 380)
    # fornalha: vulcão com cratera
    vd = np.sqrt((X - 3000) ** 2 + (Z - 300) ** 2)
    cone = np.clip(1 - vd / 1100, 0, 1) ** 1.6 * 420
    crater = np.clip(1 - vd / 260, 0, 1) ** 0.7 * 170
    h += cone - crater + blob(2800, 300, 1500, 1) * fbm(250, 5, ridged=True, seed_off=13) * 40
    # abismo de obsidiana: anel de penhascos e fosso
    ad = np.sqrt((X - 2400) ** 2 + (Z + 2700) ** 2)
    h += np.clip(1 - np.abs(ad - 700) / 260, 0, 1) ** 2 * 160
    h -= np.clip(1 - ad / 600, 0, 1) ** 1.2 * 70
    # pagode: colinas com terraços
    pg = blob(2500, 2700, 1100, 1.2)
    terr = 70 + fbm(350, 4, seed_off=17) * 60
    h = h * (1 - pg) + (np.round(terr / 12) * 12 * 0.6 + terr * 0.4) * pg
    # borda do mundo: cordilheira intransponível
    edge = np.maximum(np.abs(X), np.abs(Z))
    h += smoothstep(3300, 4000, edge) * (380 + fbm(500, 6, ridged=True, seed_off=19) * 300)
    noise_detail = fbm(60, 3, seed_off=23)
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    np.savez(CACHE, h=h, mt=mt, sw=sw, ad=ad, pg=pg, nd=noise_detail)

# pântano mais alagado (ajuste aplicado depois do cache)
h = h - sw * 3.5

# ------------------------------------------------------------------ pontos de interesse
def hz(x, z):
    j = int(round((x + HALF) / CELL)); i = int(round((z + HALF) / CELL))
    return float(h[np.clip(i, 0, N - 1), np.clip(j, 0, N - 1)])


def flatten(cx, cz, r, target=None, blend=1.6):
    global h
    t = hz(cx, cz) if target is None else target
    d = np.sqrt((X - cx) ** 2 + (Z - cz) ** 2)
    w = 1 - smoothstep(r, r * blend, d)
    h = h * (1 - w) + t * w
    return t


GRACES = [
    ("graca_despertar", "Graça do Despertar", 0, 3500),
    ("graca_vale", "Graça da Capela em Ruínas", 350, 2500),
    ("graca_cemiterio", "Graça do Ossuário", -2300, 2600),
    ("graca_pantano", "Graça do Brejo Sufocante", -2500, 200),
    ("graca_portao", "Graça do Portão de Marfim", 0, -350),
    ("graca_cidadela", "Graça do Trono Vazio", 130, -1120),
    ("graca_fornalha", "Graça da Bigorna Ardente", 2100, 650),
    ("graca_abismo", "Graça da Borda do Abismo", 1750, -2500),
    ("graca_picos", "Graça do Passo Congelado", -1700, -2300),
    ("graca_pagode", "Graça do Templo Carmesim", 2200, 2300),
]

BOSSES = [
    # id, modelo, região, x, z, raio da arena, é chefe principal (dá Grande Brasa)
    ("holy_rider", "the_holy_rider__mounted_crusader", "vale_inicial", 250, 2050, 45, False),
    ("osskaroth", "osskaroth__the_boneheap_revenant", "cemiterio", -2750, 1950, 45, True),
    ("morvessa", "morvessa__the_thorn_matriarch", "pantano_espinhos", -3050, -650, 50, True),
    ("gastaroid", "gastaroid_queen", "pantano_espinhos", -2400, -1100, 50, False),
    ("zarakhul", "zarakhul__the_bloodthorn_centaur", "pantano_espinhos", -3300, 400, 45, False),
    ("aurencast", "aurencast__the_ivory_oathkeeper", "cidadela_marfim", 0, -700, 40, False),
    ("ivorae", "ivorae__the_faceless_queen", "cidadela_marfim", 0, -1390, 50, False),
    ("rhaum", "rhaum__the_hellforged_colossus", "fornalha", 2500, 900, 60, True),
    ("vormak", "vormak__the_ashen_headsman", "fornalha", 2300, -150, 45, False),
    ("titan", "hellforged_behemoth__the_infernal_titan", "fornalha", 3000, 300, 70, False),
    ("nexmora", "nexmora__the_obsidian_matriarch", "abismo_obsidiana", 2400, -2700, 55, True),
    ("veltharion", "veltharion__the_frostbound_cavalier", "picos_gelidos", -2100, -2650, 50, True),
    ("zhenkar", "zhenkar__the_crimson_oni_shogun", "pagode_carmesim", 2650, 2850, 45, True),
]
DRAGONS = [
    ("kelvhar", "red_dragon", "fornalha", 2900, 700),
    ("ancestral", "drogon_-_dragon_game_of_thrones", "picos_gelidos", -2700, -2200),
]

print("aplainando arenas e graças...")
for _, _, _, x, z, r, _ in BOSSES:
    flatten(x, z, r)
for _, _, x, z in GRACES:
    flatten(x, z, 10, blend=2.5)

# ------------------------------------------------------------------ estradas
print("traçando estradas...")
path_mask = np.zeros_like(h)
ROADS = [("graca_despertar", "graca_vale"), ("graca_vale", "graca_cemiterio"), ("graca_vale", "graca_portao"),
         ("graca_portao", "graca_cidadela"), ("graca_vale", "graca_pagode"), ("graca_portao", "graca_fornalha"),
         ("graca_portao", "graca_pantano"), ("graca_pantano", "graca_picos"), ("graca_fornalha", "graca_abismo"),
         ("graca_cemiterio", "graca_pantano")]
gpos = {g[0]: (g[2], g[3]) for g in GRACES}
for a, b in ROADS:
    (x0, z0), (x1, z1) = gpos[a], gpos[b]
    L = math.hypot(x1 - x0, z1 - z0)
    steps = int(L / 8)
    for s in range(steps + 1):
        t = s / steps
        bend = math.sin(t * math.pi) * 180 * math.sin(len(a) + len(b))
        nx, nz = -(z1 - z0) / L, (x1 - x0) / L
        x = x0 + (x1 - x0) * t + nx * bend
        z = z0 + (z1 - z0) * t + nz * bend
        j = int((x + HALF) / CELL); i = int((z + HALF) / CELL)
        rr = 3
        i0, i1, j0, j1 = max(i - rr, 0), min(i + rr + 1, N), max(j - rr, 0), min(j + rr + 1, N)
        ii, jj = np.mgrid[i0:i1, j0:j1]
        d = np.sqrt((ii - i) ** 2 + (jj - j) ** 2) / rr
        path_mask[i0:i1, j0:j1] = np.maximum(path_mask[i0:i1, j0:j1], np.clip(1 - d, 0, 1))
# suaviza o relevo ao longo das estradas
def box_blur(a, r, passes=3):
    for _ in range(passes):
        for ax in (0, 1):
            p = np.pad(a, [(r + 1, r) if k == ax else (0, 0) for k in (0, 1)], mode="edge")
            c = np.cumsum(p, axis=ax)
            a = (np.take(c, range(2 * r + 1, c.shape[ax]), axis=ax) - np.take(c, range(0, c.shape[ax] - 2 * r - 1), axis=ax)) / (2 * r + 1)
    return a


hb = box_blur(h, 3)
pm = np.clip(path_mask * 1.5, 0, 1)
h = h * (1 - pm) + (hb - 0.4) * pm

# lagos e pântanos rasos (dá para atravessar a pé, com água pela cintura)
h = np.maximum(h, WATER - 1.4)

# ------------------------------------------------------------------ splat
print("pintando biomas...")
gy, gx = np.gradient(h, CELL)
slope = np.sqrt(gx ** 2 + gy ** 2)
noise = noise_detail

W = {k: v for k, v in [
    ("grass", np.ones_like(h)),
    ("dirt", path_mask * 2.0 + np.clip(noise - 0.15, 0, 1) * 1.5),
    ("rock", smoothstep(0.55, 0.95, slope) * 4),
    ("snow", smoothstep(260, 340, h) * (1 + mt * 3) + mt * smoothstep(120, 200, h) * 2),
    ("ash", blob(2800, 300, 1500, 0.8) * 4 + np.clip(1 - ad / 900, 0, 1) * 3),
    ("mud", sw * 3 + smoothstep(WATER + 3, WATER - 1, h) * 2),
    ("bone", blob(-2500, 2300, 1000, 1.0) * 3),
    ("crimson", pg * 2.5),
]}
W["grass"] *= (1 - smoothstep(0.4, 0.8, slope))
W["rock"] = W["rock"] + np.clip(1 - ad / 600, 0, 1) * 2  # fosso de obsidiana rochoso
order = ["grass", "dirt", "rock", "snow", "ash", "mud", "bone", "crimson"]
stack = np.stack([W[k] for k in order], -1)
stack /= np.maximum(stack.sum(-1, keepdims=True), 1e-6)

os.makedirs(OUT, exist_ok=True)
SPLAT_N = 2048
for si in range(2):
    # N-1 == SPLAT_N: sem redimensionar (o Pillow pré-multiplica alfa ao redimensionar RGBA)
    img = (np.clip(stack[:-1, :-1, si * 4:(si + 1) * 4], 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, f"splat{si}.png"))

h.astype("<f4").tofile(os.path.join(OUT, "height.bin"))

# ------------------------------------------------------------------ props (árvores, rochas, ruínas)
print("distribuindo vegetação e ruínas...")


def scatter(count, weight_fn, min_spacing=0.0, tries=20):
    pts = []
    for _ in range(count * tries):
        if len(pts) >= count:
            break
        x, z = rng.uniform(-HALF + 300, HALF - 300, 2)
        i = int((z + HALF) / CELL); j = int((x + HALF) / CELL)
        if rng.random() < weight_fn(i, j):
            y = float(h[i, j])
            if y < WATER + 0.5 and weight_fn is not mud_tree_w:
                continue
            pts.append([round(float(x), 1), round(y, 2), round(float(z), 1), round(float(rng.uniform(0, 6.283)), 2),
                        round(float(rng.uniform(0.7, 1.4)), 2)])
    return pts


def near_poi(i, j, r=60):
    x = j * CELL - HALF; z = i * CELL - HALF
    for _, _, _, bx, bz, br, _ in BOSSES:
        if (x - bx) ** 2 + (z - bz) ** 2 < (br + 10) ** 2:
            return True
    for _, _, gx_, gz_ in GRACES:
        if (x - gx_) ** 2 + (z - gz_) ** 2 < r ** 2:
            return True
    return path_mask[i, j] > 0.1


def tree_w(i, j):
    if near_poi(i, j) or slope[i, j] > 0.6:
        return 0
    return float(stack[i, j, 0]) * 0.9 + float(stack[i, j, 6]) * 0.3


def pine_w(i, j):
    if near_poi(i, j) or slope[i, j] > 0.8:
        return 0
    return float(stack[i, j, 3]) * 0.8 + float(mt[i, j]) * 0.4


def dead_w(i, j):
    if near_poi(i, j) or slope[i, j] > 0.7:
        return 0
    return float(stack[i, j, 4]) * 0.6 + float(stack[i, j, 6]) * 0.7 + float(stack[i, j, 7]) * 0.4


def mud_tree_w(i, j):
    if near_poi(i, j):
        return 0
    return float(stack[i, j, 5]) * 0.9


def rock_w(i, j):
    if near_poi(i, j, 30):
        return 0
    return 0.15 + float(stack[i, j, 2]) * 0.6


props = {
    "tree": scatter(4500, tree_w),
    "pine": scatter(3000, pine_w),
    "dead_tree": scatter(2500, dead_w),
    "swamp_tree": scatter(1200, mud_tree_w),
    "rock": scatter(3500, rock_w),
}

# ruínas: aglomerados em cada região
ruins = []
for key, reg in REGIONS.items():
    cx, cz = reg["c"]
    for _ in range(14):
        a = rng.uniform(0, 6.283); d = rng.uniform(150, reg["r"] * 0.9)
        x = cx + math.cos(a) * d; z = cz + math.sin(a) * d
        if abs(x) > HALF - 500 or abs(z) > HALF - 500:
            continue
        i = int((z + HALF) / CELL); j = int((x + HALF) / CELL)
        if slope[i, j] > 0.5 or h[i, j] < WATER + 1:
            continue
        kind = {"cemiterio": "graveyard", "pagode_carmesim": "shrine", "fornalha": "obelisks",
                "picos_gelidos": "ice_spikes", "abismo_obsidiana": "obelisks"}.get(key, "ruin")
        ruins.append(dict(kind=kind, pos=[round(x, 1), round(float(h[i, j]), 2), round(z, 1)],
                          rot=round(float(rng.uniform(0, 6.283)), 2), seed=int(rng.integers(1 << 30))))

# ------------------------------------------------------------------ inimigos
REGION_ENEMIES = {
    "vale_inicial": ["vaelrith__the_veiled_horn"],
    "cemiterio": ["gravestone_golem_-_cemetery_guardian", "vaelrith__the_veiled_horn"],
    "pantano_espinhos": ["varkhen__the_obsidian_oathbreaker", "vaelrith__the_veiled_horn"],
    "cidadela_marfim": ["astravyne__the_ivory_bloodlancer", "drakvald__the_ivory_dreadmarshal"],
    "fornalha": ["gorthazul__the_ashhorn_behemoth", "volcanic_obsidian_golem_creature"],
    "abismo_obsidiana": ["varkhen__the_obsidian_oathbreaker", "volcanic_obsidian_golem_creature"],
    "picos_gelidos": ["sylvaris__the_frostveil_duelist", "drakvald__the_ivory_dreadmarshal"],
    "pagode_carmesim": ["sylvaris__the_frostveil_duelist", "astravyne__the_ivory_bloodlancer"],
}
LEVEL = {"vale_inicial": 1, "cemiterio": 2, "pantano_espinhos": 3, "pagode_carmesim": 3, "fornalha": 4,
         "picos_gelidos": 4, "abismo_obsidiana": 5, "cidadela_marfim": 5}
enemies = []
for key, reg in REGIONS.items():
    cx, cz = reg["c"]
    groups = 12 if key != "vale_inicial" else 9
    for _ in range(groups):
        for _try in range(30):
            a = rng.uniform(0, 6.283); d = rng.uniform(100, reg["r"])
            x = cx + math.cos(a) * d; z = cz + math.sin(a) * d
            if abs(x) > HALF - 500 or abs(z) > HALF - 500:
                continue
            i = int((z + HALF) / CELL); j = int((x + HALF) / CELL)
            if slope[i, j] > 0.45 or h[i, j] < WATER + 0.5:
                continue
            if any((x - gx_) ** 2 + (z - gz_) ** 2 < 90 ** 2 for _, _, gx_, gz_ in GRACES):
                continue
            n = int(rng.integers(1, 4))
            for k in range(n):
                ex, ez = x + rng.uniform(-8, 8), z + rng.uniform(-8, 8)
                model = REGION_ENEMIES[key][int(rng.integers(len(REGION_ENEMIES[key])))]
                enemies.append(dict(model=model, region=key, level=LEVEL[key],
                                    pos=[round(float(ex), 1), round(hz(ex, ez), 2), round(float(ez), 1)]))
            break

# ------------------------------------------------------------------ json
world = dict(
    seed=SEED, n=N, cell=CELL, size=SIZE, water=WATER,
    regions={k: dict(name=v["name"], center=list(v["c"]), radius=v["r"], level=LEVEL[k]) for k, v in REGIONS.items()},
    graces=[dict(id=g, name=n, region=min(REGIONS, key=lambda r: (REGIONS[r]["c"][0] - x) ** 2 + (REGIONS[r]["c"][1] - z) ** 2),
                 pos=[x, hz(x, z), z]) for g, n, x, z in GRACES],
    bosses=[dict(id=b, model=m, region=r, pos=[x, hz(x, z), z], arena=ar, great=g,
                 title=CATALOG[m]["title"], level=LEVEL[r] + 1) for b, m, r, x, z, ar, g in BOSSES],
    dragons=[dict(id=d, model=m, region=r, pos=[x, hz(x, z), z], title=CATALOG[m]["title"]) for d, m, r, x, z in DRAGONS],
    ember_tree=[0, hz(0, -1530), -1530],
    start=[0, hz(0, 3530), 3530],
    enemies=enemies, props=props, ruins=ruins,
)
with open(os.path.join(OUT, "world.json"), "w", encoding="utf-8") as f:
    json.dump(world, f, ensure_ascii=False, separators=(",", ":"))

# ------------------------------------------------------------------ mapa ilustrado
print("desenhando mapa...")
M = 1024
pal = np.array([[88, 102, 58], [120, 100, 70], [105, 100, 92], [225, 228, 232],
                [60, 50, 46], [62, 66, 48], [150, 140, 120], [120, 45, 40]], dtype=np.float64)
col = stack @ pal
shade = np.clip(0.8 + (gx * -0.6 + gy * -0.6) * 1.0, 0.35, 1.35)[..., None]
col = col * shade
col = np.where((h < WATER)[..., None], np.array([38, 52, 60], np.float64), col)
col = np.where((path_mask > 0.3)[..., None], col * 0.7 + np.array([150, 120, 80]) * 0.3, col)
parch = np.array([200, 180, 140], np.float64)  # tom de pergaminho
col = col * 0.8 + parch * 0.2
img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").resize((M, M), Image.LANCZOS)
d = ImageDraw.Draw(img)
try:
    from PIL import ImageFont
    font = ImageFont.truetype("georgiai.ttf", 22)
except OSError:
    font = None
for k, reg in REGIONS.items():
    x, z = reg["c"]
    px, pz = (x + HALF) / SIZE * M, (z + HALF) / SIZE * M
    if font:
        w = d.textlength(reg["name"], font=font)
        d.text((px - w / 2 + 1, pz - 34 + 1), reg["name"], fill=(235, 220, 190), font=font)
        d.text((px - w / 2, pz - 34), reg["name"], fill=(40, 25, 10), font=font)
    else:
        d.text((px - len(reg["name"]) * 3, pz - 30), reg["name"], fill=(30, 20, 10))
img.save(os.path.join(OUT, "map.png"))
print(f"pronto: {len(enemies)} inimigos, {sum(len(v) for v in props.values())} props, {len(ruins)} ruínas")
