"""Texturas procedurais tileáveis (ruído espectral via FFT) para terreno e construções.

Saída: game/assets/textures/<nome>_albedo.png e <nome>_normal.png
Uso:   python tools/gen_textures.py
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "textures")
S = 1024
rng = np.random.default_rng(42)


def spectral(beta=2.0, lo=2, hi=None, size=S):
    """Ruído 1/f^beta naturalmente periódico (tileável)."""
    w = rng.normal(size=(size, size))
    F = np.fft.fft2(w)
    fx = np.fft.fftfreq(size) * size
    k = np.sqrt(fx[None, :] ** 2 + fx[:, None] ** 2)
    k[0, 0] = 1
    amp = 1 / k ** (beta / 2)
    amp[k < lo] = 0
    if hi:
        amp[k > hi] = 0
    n = np.real(np.fft.ifft2(F * amp))
    n -= n.min()
    return n / (n.max() + 1e-9)


def cells(count=60, size=S):
    """Ruído de Voronoi tileável (distância ao 1º e 2º ponto)."""
    pts = rng.uniform(0, size, (count, 2))
    yy, xx = np.mgrid[0:size, 0:size]
    d1 = np.full((size, size), 1e9); d2 = np.full((size, size), 1e9)
    for px, py in pts:
        dx = np.abs(xx - px); dx = np.minimum(dx, size - dx)
        dy = np.abs(yy - py); dy = np.minimum(dy, size - dy)
        d = np.sqrt(dx * dx + dy * dy)
        d2 = np.where(d < d1, d1, np.minimum(d2, d))
        d1 = np.minimum(d1, d)
    return d1, d2


def bricks(rows=8, cols=4, mortar=0.04, size=S):
    yy, xx = np.mgrid[0:size, 0:size] / size
    r = np.floor(yy * rows)
    off = (r % 2) * 0.5 / cols
    u = ((xx + off) * cols) % 1
    v = (yy * rows) % 1
    m = np.minimum(np.minimum(u, 1 - u) * rows / cols * 0.5 * cols / rows * 2, np.minimum(v, 1 - v))
    edge = np.clip(np.minimum(np.minimum(u, 1 - u) * (rows / cols), np.minimum(v, 1 - v)) / mortar, 0, 1)
    bid = (r * 31 + np.floor((xx + off) * cols) * 17) % 97 / 97
    return edge, bid


def colorize(t, stops):
    """stops: [(pos, (r,g,b)), ...] gradiente."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    ps = [p for p, _ in stops]
    for c in range(3):
        out[..., c] = np.interp(t, ps, [col[c] for _, col in stops])
    return out


def normal_from_height(hm, strength=4.0):
    gx = (np.roll(hm, -1, 1) - np.roll(hm, 1, 1)) * strength
    gy = (np.roll(hm, -1, 0) - np.roll(hm, 1, 0)) * strength
    n = np.stack([-gx, -gy, np.ones_like(hm)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return (n * 0.5 + 0.5) * 255


def save(name, rgb, height, strength=4.0):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, f"{name}_albedo.png"))
    Image.fromarray(normal_from_height(height, strength).astype(np.uint8), "RGB").save(os.path.join(OUT, f"{name}_normal.png"))
    print("  ", name)


def main():
    print("gerando texturas...")
    fine, mid, big = spectral(1.2, 30), spectral(2.0, 4, 60), spectral(2.6, 1, 12)

    # grama: tufos escuros/claros + manchas secas
    blades = spectral(0.8, 120)
    t = mid * 0.5 + blades * 0.5
    g = colorize(t, [(0, (38, 48, 22)), (0.45, (66, 80, 36)), (0.7, (92, 98, 50)), (1, (120, 112, 66))])
    g = g * (0.8 + 0.3 * big[..., None])
    save("grass", g, blades * 0.6 + mid * 0.4, 3)

    # terra/trilha: cascalho
    d1, d2 = cells(220)
    pebble = np.clip(1 - d1 / 22, 0, 1)
    t = mid * 0.6 + fine * 0.4
    c = colorize(t, [(0, (62, 48, 34)), (0.5, (98, 80, 58)), (1, (130, 110, 84))])
    c = c * (0.85 + 0.25 * pebble[..., None])
    save("dirt", c, pebble * 0.6 + fine * 0.4, 5)

    # rocha: fraturas de Voronoi + estratos
    d1, d2 = cells(45)
    crack = np.clip((d2 - d1) / 10, 0, 1)
    strata = (np.sin(np.mgrid[0:S, 0:S][0] / S * 2 * np.pi * 9 + mid * 6) * 0.5 + 0.5)
    t = mid * 0.5 + fine * 0.3 + strata * 0.2
    c = colorize(t, [(0, (58, 56, 54)), (0.5, (96, 92, 86)), (1, (140, 134, 124))]) * (0.55 + 0.45 * crack[..., None])
    save("rock", c, crack * 0.6 + fine * 0.2 + strata * 0.2, 7)

    # neve
    t = big * 0.5 + fine * 0.5
    c = colorize(t, [(0, (190, 200, 214)), (0.6, (226, 232, 240)), (1, (248, 250, 255))])
    save("snow", c, fine, 1.5)

    # cinza vulcânica com veios de brasa
    d1, d2 = cells(70)
    vein = np.clip(1 - (d2 - d1) / 4, 0, 1) * (mid > 0.55)
    t = fine * 0.5 + mid * 0.5
    c = colorize(t, [(0, (22, 20, 20)), (0.5, (48, 42, 40)), (1, (78, 70, 64))])
    c = c * (1 - vein[..., None]) + np.array([255, 90, 20]) * vein[..., None]
    save("ash", c, fine * 0.7 + (1 - vein) * 0.3, 4)

    # lama do pântano
    t = mid * 0.7 + fine * 0.3
    c = colorize(t, [(0, (30, 32, 22)), (0.5, (52, 54, 36)), (1, (78, 76, 52))])
    wet = (big > 0.55)[..., None]
    c = np.where(wet, c * 0.6, c)
    save("mud", c, mid * 0.5 + fine * 0.5, 2.5)

    # solo de ossos (cemitério): terra pálida com fragmentos
    d1, _ = cells(300)
    bone = (d1 < 4) & (fine > 0.5)
    t = mid * 0.6 + fine * 0.4
    c = colorize(t, [(0, (70, 64, 56)), (0.5, (110, 102, 90)), (1, (150, 140, 124))])
    c[bone] = (205, 196, 176)
    save("bone", c, fine * 0.6 + bone * 0.4, 4)

    # solo carmesim (pagode)
    t = mid * 0.6 + fine * 0.4
    c = colorize(t, [(0, (54, 18, 16)), (0.5, (98, 36, 30)), (1, (140, 64, 50))])
    save("crimson", c, fine * 0.5 + mid * 0.5, 3)

    # alvenaria de pedra (ruínas)
    edge, bid = bricks(10, 4, 0.05)
    t = fine * 0.5 + mid * 0.3 + bid * 0.2
    c = colorize(t, [(0, (64, 62, 58)), (0.5, (106, 102, 94)), (1, (150, 144, 132))])
    c = c * (0.35 + 0.65 * edge[..., None])
    moss = (big > 0.6) & (edge > 0.5)
    c[moss] = c[moss] * 0.6 + np.array([50, 70, 30]) * 0.4
    save("stone_wall", c, edge * 0.7 + fine * 0.3, 6)

    # pedra de marfim (cidadela)
    edge, bid = bricks(6, 2, 0.03)
    t = fine * 0.4 + mid * 0.4 + bid * 0.2
    c = colorize(t, [(0, (170, 160, 140)), (0.5, (210, 200, 178)), (1, (236, 228, 210))])
    c = c * (0.5 + 0.5 * edge[..., None])
    save("ivory_stone", c, edge * 0.7 + fine * 0.3, 5)

    # casca de árvore
    yy, xx = np.mgrid[0:S, 0:S] / S
    ridges = np.abs(np.sin((xx * 22 + spectral(2.0, 2, 30) * 3) * np.pi))
    t = ridges * 0.6 + fine * 0.4
    c = colorize(t, [(0, (30, 22, 16)), (0.5, (62, 48, 36)), (1, (92, 76, 60))])
    save("bark", c, ridges * 0.7 + fine * 0.3, 6)

    # folhagem (copa)
    d1, _ = cells(400)
    leaf = np.clip(1 - d1 / 14, 0, 1)
    c = colorize(leaf * 0.7 + mid * 0.3, [(0, (20, 30, 12)), (0.5, (46, 62, 24)), (1, (86, 98, 40))])
    save("leaves", c, leaf, 3)

    # madeira (pagode)
    planks = (np.mgrid[0:S, 0:S][1] / S * 8) % 1
    grain = np.sin((np.mgrid[0:S, 0:S][0] / S * 80 + spectral(2.0, 2, 30) * 10)) * 0.5 + 0.5
    edge = np.clip(np.minimum(planks, 1 - planks) / 0.03, 0, 1)
    c = colorize(grain * 0.6 + fine * 0.4, [(0, (60, 30, 18)), (0.5, (96, 54, 32)), (1, (130, 80, 50))]) * (0.5 + 0.5 * edge[..., None])
    save("wood", c, edge * 0.5 + grain * 0.5, 3)

    # telhado laqueado vermelho
    edge, bid = bricks(16, 8, 0.08)
    c = colorize(fine * 0.5 + bid * 0.5, [(0, (90, 14, 12)), (0.5, (140, 24, 18)), (1, (180, 40, 26))]) * (0.4 + 0.6 * edge[..., None])
    save("roof", c, edge, 5)

    # obsidiana
    d1, d2 = cells(30)
    facet = (d2 - d1) / 40
    c = colorize(np.clip(facet + fine * 0.2, 0, 1), [(0, (8, 6, 12)), (0.5, (24, 20, 32)), (1, (60, 52, 80))])
    save("obsidian", c, facet, 8)

    # gelo
    c = colorize(big * 0.5 + fine * 0.5, [(0, (120, 160, 190)), (0.5, (170, 205, 225)), (1, (220, 240, 250))])
    save("ice", c, fine, 2)


if __name__ == "__main__":
    main()
