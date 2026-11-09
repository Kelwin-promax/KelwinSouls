"""Sintetizador de efeitos sonoros e músicas do KelwinSouls (100% gerado → sem direitos autorais).

Uso:  python tools/gen_audio.py
Saída: game/assets/audio/*.wav (44.1 kHz, 16 bits)
"""
from __future__ import annotations

import os
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "audio")
rng = np.random.default_rng(7)


# ------------------------------------------------------------------ blocos básicos
def t_(dur):
    return np.arange(int(SR * dur)) / SR


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def env(n, a=0.01, d=0.1, s=0.0, r=0.2, sl=None):
    """ADSR em amostras; se sl (sustain length) None, usa o que sobrar."""
    A, D, R = int(a * SR), int(d * SR), int(r * SR)
    S = max(n - A - D - R, 0) if sl is None else int(sl * SR)
    e = np.concatenate([np.linspace(0, 1, A, endpoint=False), np.linspace(1, s, D, endpoint=False),
                        np.full(S, s), np.linspace(s, 0, R)])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def exp_env(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def lowpass(x, cutoff):
    """Filtro de 1 polo; cutoff pode ser array (varredura)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def lp_fast(x, cutoff, order=2):
    """Passa-baixas via FFT (cutoff fixo) — rápido para sinais longos."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / (1 + (f / cutoff) ** (2 * order))
    return np.fft.irfft(X, len(x))


def bandpass(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= (1 / (1 + (f / hi) ** 4)) * (1 / (1 + (lo / np.maximum(f, 1)) ** 4))
    return np.fft.irfft(X, len(x))


def reverb(x, decay=1.8, mix=0.35, pre=0.02):
    n = int(SR * decay)
    ir = rng.normal(0, 1, n) * np.exp(-np.arange(n) / (SR * decay / 6.9))
    ir = lp_fast(ir, 6000)
    ir = np.concatenate([np.zeros(int(pre * SR)), ir])
    L = len(x) + len(ir)
    wet = np.fft.irfft(np.fft.rfft(x, L) * np.fft.rfft(ir, L), L)[: len(x) + len(ir) - 1]
    wet /= np.max(np.abs(wet)) + 1e-9
    dry = np.pad(x, (0, len(wet) - len(x)))
    return dry * (1 - mix) + wet * mix * np.max(np.abs(x))


def sine(f, dur, phase=0.0):
    f = np.broadcast_to(np.asarray(f, dtype=np.float64), (int(SR * dur),))
    return np.sin(2 * np.pi * np.cumsum(f) / SR + phase)


def saw(f, dur):
    f = np.broadcast_to(np.asarray(f, dtype=np.float64), (int(SR * dur),))
    ph = np.cumsum(f) / SR
    return 2 * (ph % 1) - 1


def norm(x, peak=0.9):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def save(name, x, peak=0.9, stereo=False):
    os.makedirs(OUT, exist_ok=True)
    x = norm(x, peak)
    if stereo and x.ndim == 1:
        x = np.stack([x, x], -1)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(2 if data.ndim == 2 else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("  ", name, f"{len(x) / SR:.2f}s")


# ------------------------------------------------------------------ efeitos
def whoosh(dur, f0, f1, weight=1.0):
    n = int(SR * dur)
    sweep = np.concatenate([np.geomspace(f0, f1, n // 2), np.geomspace(f1, f0 * 0.6, n - n // 2)])
    x = lowpass(noise(dur), sweep) * env(n, a=dur * 0.35, d=dur * 0.3, s=0.2, r=dur * 0.3)
    body = sine(np.linspace(120 * weight, 60 * weight, n), dur) * env(n, dur * 0.4, dur * 0.2, 0.1, dur * 0.3) * 0.25
    return x + body


def impact(dur=0.5, thump=70, ring=None, grit=0.6):
    n = int(SR * dur)
    x = sine(np.geomspace(thump * 2.2, thump * 0.6, n), dur) * exp_env(n, 0.09)
    x += lp_fast(noise(dur), 2500) * exp_env(n, 0.03) * grit
    if ring:
        for k, (f, a) in enumerate(ring):
            x += sine(f, dur, k) * exp_env(n, 0.25 / (k + 1)) * a
    return x


def footstep(kind):
    dur = 0.22
    n = int(SR * dur)
    if kind == "stone":
        x = bandpass(noise(dur), 300, 4000) * exp_env(n, 0.018) + sine(110, dur) * exp_env(n, 0.03) * 0.4
    elif kind == "grass":
        x = bandpass(noise(dur), 800, 6000) * env(n, 0.01, 0.06, 0.2, 0.12) * 0.7 + sine(80, dur) * exp_env(n, 0.03) * 0.3
    else:  # metal (armadura)
        x = bandpass(noise(dur), 200, 3000) * exp_env(n, 0.02) + sine(1900, dur) * exp_env(n, 0.04) * 0.08
    return x


def fire_loop(dur=8.0):
    n = int(SR * dur)
    base = lp_fast(noise(dur), 500) * 0.6 + bandpass(noise(dur), 800, 3000) * 0.15
    crackle = np.zeros(n)
    for _ in range(int(dur * 18)):
        p = rng.integers(0, n - 2000)
        L = rng.integers(80, 900)
        crackle[p:p + L] += rng.uniform(-1, 1, L) * np.exp(-np.arange(L) / (L / 4)) * rng.uniform(0.3, 1.0)
    x = base + bandpass(crackle, 1000, 9000) * 0.9
    fade = int(0.4 * SR)  # emenda para loop
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    return x[:-fade]


def wind_loop(dur=16.0):
    n = int(SR * dur)
    mod = 0.5 + 0.5 * np.sin(2 * np.pi * np.arange(n) / SR * 0.11) * np.sin(2 * np.pi * np.arange(n) / SR * 0.043 + 1)
    x = bandpass(noise(dur), 150, 900) * (0.4 + 0.6 * mod)
    x += bandpass(noise(dur), 900, 2200) * 0.08 * mod
    fade = int(1.0 * SR)
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    return x[:-fade]


def roar(dur=2.2, f=55):
    n = int(SR * dur)
    vib = f * (1 + 0.08 * np.sin(2 * np.pi * 7 * np.arange(n) / SR)) * np.concatenate(
        [np.linspace(0.8, 1.2, n // 3), np.linspace(1.2, 0.7, n - n // 3)])
    x = saw(vib, dur) * 0.7 + saw(vib * 1.51, dur) * 0.3
    x = x * (1 + 0.9 * lp_fast(noise(dur), 40))
    x = lp_fast(x, 1400) + bandpass(noise(dur), 300, 2500) * 0.5
    return reverb(x * env(n, 0.15, 0.4, 0.7, 0.8), 2.5, 0.3)


def chord_pad(freqs, dur, bright=1200, detune=0.004):
    n = int(SR * dur)
    x = np.zeros(n)
    for f in freqs:
        for d in (-detune, 0, detune):
            x += saw(f * (1 + d), dur) * 0.33
    return lp_fast(x, bright)


def bell(f, dur=3.0):
    n = int(SR * dur)
    parts = [(1, 1), (2.76, 0.5), (5.4, 0.25), (8.93, 0.12)]
    return sum(sine(f * m, dur) * exp_env(n, dur / (2 + k * 1.5)) * a for k, (m, a) in enumerate(parts))


def choir(freqs, dur):
    """'Coro' sintético: ondas dente-de-serra filtradas por formantes de 'ah'."""
    n = int(SR * dur)
    x = np.zeros(n)
    for f in freqs:
        v = f * (1 + 0.006 * np.sin(2 * np.pi * 5 * np.arange(n) / SR + rng.uniform(0, 6)))
        x += saw(v, dur)
    y = bandpass(x, 600, 1100) * 1.0 + bandpass(x, 1100, 1400) * 0.5 + bandpass(x, 2300, 2900) * 0.25
    return y


NOTE = lambda m: 440.0 * 2 ** ((m - 69) / 12)  # noqa: E731


def music_explore(dur=72.0):
    # progressão menor lenta: Dm - Bb - F - A (graus em MIDI)
    prog = [[50, 57, 62, 65], [46, 53, 58, 62], [41, 53, 57, 60], [45, 52, 57, 61]]
    seg = dur / len(prog)
    parts = []
    for ch in prog:
        p = chord_pad([NOTE(m) for m in ch], seg, bright=900) * env(int(seg * SR), 3.0, 1.0, 0.8, 3.0)
        p += choir([NOTE(m + 12) for m in ch[1:]], seg) * env(int(seg * SR), 4.0, 1, 0.6, 3.5) * 0.35
        parts.append(p)
    x = np.zeros(int(dur * SR) + SR * 4)
    for i, p in enumerate(parts):
        s = int(i * seg * SR)
        x[s:s + len(p)] += p
    # sinos esparsos
    for k in range(10):
        s = int(rng.uniform(2, dur - 4) * SR)
        b = bell(NOTE(rng.choice([74, 77, 81, 69, 72])), 4.0) * 0.18
        x[s:s + len(b)] += b
    x = reverb(x[: int(dur * SR)], 3.5, 0.45)[: int(dur * SR)]
    fade = int(3 * SR)
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    return x[:-fade]


def music_boss(dur=48.0, bpm=96):
    n = int(SR * dur)
    x = np.zeros(n + SR * 3)
    beat = 60 / bpm
    kick = impact(0.6, 50, None, 0.3)
    snare = bandpass(noise(0.4), 200, 5000) * exp_env(int(0.4 * SR), 0.08) + sine(180, 0.4) * exp_env(int(0.4 * SR), 0.05)
    taiko = impact(1.0, 38, None, 0.5)
    pattern = [1, 0, 0, 1, 2, 0, 1, 0, 1, 0, 1, 1, 2, 0, 3, 0]
    steps = int(dur / (beat / 2))
    for s in range(steps):
        p = pattern[s % len(pattern)]
        pos = int(s * beat / 2 * SR)
        if p == 1:
            x[pos:pos + len(kick)] += kick * 0.9
        elif p == 2:
            x[pos:pos + len(snare)] += snare * 0.5
        elif p == 3:
            x[pos:pos + len(taiko)] += taiko * 1.1
    prog = [[38, 45, 50, 53], [36, 43, 48, 51], [34, 41, 46, 50], [37, 44, 49, 52]]
    seg = dur / len(prog)
    for i, ch in enumerate(prog):
        s = int(i * seg * SR)
        L = int(seg * SR)
        pad = chord_pad([NOTE(m) for m in ch], seg, 1600) * env(L, 0.5, 0.5, 0.8, 1.0) * 0.5
        c = choir([NOTE(m + 12) for m in ch], seg) * env(L, 1.0, 0.5, 0.8, 1.0) * 0.6
        ost = np.zeros(L)
        for k in range(int(seg / (beat / 2))):
            q = int(k * beat / 2 * SR)
            note = NOTE(ch[0] + 12 + [0, 7, 12, 7, 3, 7, 12, 15][k % 8])
            nn = saw(note, beat / 2 * 0.9) * env(int(beat / 2 * 0.9 * SR), 0.005, 0.1, 0.4, 0.05)
            ost[q:q + len(nn)] += lp_fast(nn, 2000)
        x[s:s + L] += pad + c + ost * 0.18
    x = reverb(x[:n], 2.2, 0.25)[:n]
    fade = int(2 * SR)
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    return x[:-fade]


def main():
    print("sintetizando efeitos...")
    save("swing_light", whoosh(0.32, 400, 5000))
    save("swing_heavy", whoosh(0.6, 200, 3000, 0.7))
    save("swing_big", whoosh(0.9, 120, 1800, 0.5))
    save("hit_flesh", impact(0.45, 90, None, 1.0))
    save("hit_metal", impact(0.7, 120, [(1350, 0.35), (2210, 0.2), (3420, 0.1)], 0.7))
    save("hit_heavy", reverb(impact(1.0, 45, [(400, 0.2)], 1.0), 1.2, 0.25))
    save("block", impact(0.8, 160, [(980, 0.5), (1720, 0.35), (2950, 0.2), (4100, 0.1)], 0.5))
    save("parry", reverb(impact(0.9, 200, [(1568, 0.6), (2350, 0.4), (3136, 0.3)], 0.3), 1.0, 0.3))
    save("roll", bandpass(noise(0.45), 200, 2500) * env(int(0.45 * SR), 0.05, 0.15, 0.4, 0.2))
    for i in range(3):
        save(f"step_grass_{i}", footstep("grass"))
        save(f"step_stone_{i}", footstep("stone"))
    save("player_hurt", reverb(lowpass(saw(np.geomspace(210, 140, int(0.35 * SR)), 0.35), 1400) * env(int(0.35 * SR), 0.01, 0.1, 0.5, 0.2) + impact(0.35, 90, None, 0.8) * 0.6, 0.6, 0.2))
    save("enemy_hurt", lowpass(saw(np.geomspace(140, 90, int(0.4 * SR)), 0.4), 900) * env(int(0.4 * SR), 0.01, 0.1, 0.5, 0.25))
    save("enemy_death", reverb(lowpass(saw(np.geomspace(120, 45, int(1.4 * SR)), 1.4), 700) * env(int(1.4 * SR), 0.02, 0.3, 0.5, 0.9)
                               + bandpass(noise(1.4), 2000, 9000) * env(int(1.4 * SR), 0.5, 0.3, 0.3, 0.6) * 0.15, 2.0, 0.35))
    save("boss_roar", roar(2.4, 52))
    save("dragon_roar", roar(3.2, 38))
    save("dragon_breath", reverb(lp_fast(noise(3.0), 1800) * env(int(3 * SR), 0.2, 0.3, 0.9, 1.0) + roar(3.0, 30)[: int(3 * SR)] * 0.3, 1.5, 0.3))
    gulp = np.concatenate([lp_fast(noise(0.12), 700) * exp_env(int(0.12 * SR), 0.03) for _ in range(3)])
    save("flask", reverb(np.concatenate([gulp, bell(NOTE(84), 1.2) * 0.4]), 1.2, 0.3))
    save("grace_discover", reverb(sum(bell(NOTE(m), 4.0) * a for m, a in [(62, 0.6), (69, 0.5), (74, 0.45), (78, 0.3)]), 3.0, 0.5))
    save("grace_rest", reverb(chord_pad([NOTE(m) for m in (50, 57, 62, 66)], 3.0, 1500) * env(int(3 * SR), 1.0, 0.5, 0.6, 1.4)
                              + bell(NOTE(86), 3.0) * 0.2, 3.0, 0.5))
    save("souls_pickup", reverb(sum(sine(NOTE(m), 1.0) * exp_env(SR, 0.25) * (0.5 ** k) for k, m in enumerate([81, 88, 93, 100])), 1.5, 0.4))
    save("you_died", reverb(impact(2.5, 35, None, 0.7) + choir([NOTE(m) for m in (38, 45, 50, 53)], 5.0)[: int(2.5 * SR)] * env(int(2.5 * SR), 0.8, 0.5, 0.6, 1.0) * 0.6, 4.0, 0.5))
    save("enemy_felled", reverb(impact(1.5, 45, None, 0.6) + chord_pad([NOTE(m) for m in (50, 57, 62, 66, 69)], 4.0, 2500)[: int(1.5 * SR)] * env(int(1.5 * SR), 0.05, 0.3, 0.7, 0.8)
                                + choir([NOTE(m) for m in (62, 66, 69)], 1.5) * env(int(1.5 * SR), 0.2, 0.3, 0.7, 0.8) * 0.5, 4.0, 0.5))
    save("fog_gate", reverb(lowpass(noise(1.6), np.geomspace(300, 3000, int(1.6 * SR))) * env(int(1.6 * SR), 0.5, 0.4, 0.4, 0.6), 2.0, 0.5))
    save("ui_move", sine(NOTE(84), 0.06) * exp_env(int(0.06 * SR), 0.02))
    save("ui_select", reverb(bell(NOTE(79), 0.6) * 0.6, 0.8, 0.3))
    save("level_up", reverb(sum(bell(NOTE(m), 2.5) * 0.5 for m in (67, 71, 74, 79)), 2.0, 0.4))
    save("jump", bandpass(noise(0.25), 300, 3000) * env(int(0.25 * SR), 0.02, 0.1, 0.2, 0.1))
    save("land", impact(0.35, 70, None, 0.7))
    print("sintetizando loops...")
    save("fire_loop", fire_loop(), 0.7)
    save("wind_loop", wind_loop(), 0.6)
    print("compondo músicas (pode demorar ~1 min)...")
    save("music_explore", music_explore(), 0.6)
    save("music_boss", music_boss(), 0.75)


if __name__ == "__main__":
    main()
