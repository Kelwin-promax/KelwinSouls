"""Pipeline de assets do KelwinSouls (Python + Godot headless).

Para cada modelo .glb na raiz do projeto:
  1. Python: junta todos os pedaços de malha, aplica transformações, solda vértices,
     descarta UVs/tangentes extras, centraliza (pés em y=0), reescala para a altura
     do catálogo e reduz as texturas (2048 cor / 1024 demais).
  2. Godot (headless): simplifica a malha com o meshoptimizer até o orçamento de triângulos.
  3. Python: compacta e grava o GLB final em game/assets/models/.
Modelos animados (dragões, rainha) só têm as texturas reduzidas e a escala anotada.

Uso:  python tools/asset_pipeline.py [nome_parcial ...] [--force]
"""
from __future__ import annotations

import io
import json
import os
import struct
import subprocess
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from catalog import CATALOG  # noqa: E402
from glb import GLB, GLBWriter  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "models")
TMP = os.path.join(ROOT, "build", "tmp")
GODOT = os.environ.get("GODOT", r"C:\Users\51530462819\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
SIMPLIFY_GD = os.path.join(ROOT, "tools", "godot", "simplify_mesh.gd")

TEX_MAX = {"baseColorTexture": 2048, "emissiveTexture": 1024, "metallicRoughnessTexture": 1024,
           "normalTexture": 1024, "occlusionTexture": 1024}


# ---------------------------------------------------------------- texturas
def encode_image(data: bytes, max_side: int, kind: str) -> tuple[bytes, str]:
    im = Image.open(io.BytesIO(data))
    im.load()
    if max(im.size) > max_side:
        s = max_side / max(im.size)
        im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    has_alpha = im.mode in ("RGBA", "LA") and im.getchannel("A").getextrema()[0] < 250
    buf = io.BytesIO()
    if has_alpha or kind == "normalTexture":
        im.convert("RGBA" if has_alpha else "RGB").save(buf, "PNG", optimize=True)
        return buf.getvalue(), "image/png"
    im.convert("RGB").save(buf, "JPEG", quality=90)
    return buf.getvalue(), "image/jpeg"


def copy_material(src: GLB, mat_idx: int | None, w: GLBWriter, tex_cache: dict) -> int:
    if mat_idx is None:
        return w.add_material({"pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.8}})
    m = json.loads(json.dumps(src.json["materials"][mat_idx]))
    m.pop("extensions", None)

    def remap(slot: dict, kind: str):
        t = slot["index"]
        key = (t, kind)
        if key not in tex_cache:
            img_idx = src.json["textures"][t]["source"]
            data, _ = src.image_bytes(img_idx)
            tex_cache[key] = w.add_image(*encode_image(data, TEX_MAX[kind], kind))
        slot["index"] = tex_cache[key]
        slot.pop("texCoord", None)
        slot.pop("extensions", None)

    pbr = m.setdefault("pbrMetallicRoughness", {})
    for k in ("baseColorTexture", "metallicRoughnessTexture"):
        if k in pbr:
            remap(pbr[k], k)
    for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
        if k in m:
            remap(m[k], k)
    m["doubleSided"] = False
    return w.add_material(m)


# ---------------------------------------------------------------- malha
def gather(src: GLB):
    """Retorna {material: (pos, nrm, uv, idx)} com tudo em espaço de mundo."""
    groups: dict = {}
    mats = src.world_matrices()
    for ni, node in enumerate(src.json.get("nodes", [])):
        if "mesh" not in node or ni not in mats:
            continue
        M = mats[ni]
        N = np.linalg.inv(M[:3, :3]).T
        for p in src.json["meshes"][node["mesh"]]["primitives"]:
            if p.get("mode", 4) != 4:
                continue
            a = p["attributes"]
            pos = src.accessor(a["POSITION"]).astype(np.float64)
            pos = pos @ M[:3, :3].T + M[:3, 3]
            nrm = src.accessor(a["NORMAL"]).astype(np.float64) @ N.T if "NORMAL" in a else np.zeros_like(pos)
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
            uv = src.accessor(a["TEXCOORD_0"]).astype(np.float64) if "TEXCOORD_0" in a else np.zeros((len(pos), 2))
            idx = src.accessor(p["indices"]).reshape(-1).astype(np.int64) if "indices" in p else np.arange(len(pos))
            g = groups.setdefault(p.get("material"), [[], [], [], [], 0])
            g[0].append(pos); g[1].append(nrm); g[2].append(uv); g[3].append(idx + g[4])
            g[4] += len(pos)
    out = {}
    for k, g in groups.items():
        out[k] = [np.concatenate(g[0]), np.concatenate(g[1]), np.concatenate(g[2]), np.concatenate(g[3])]
    return out


def weld(pos, nrm, uv, idx, diag):
    q = np.empty((len(pos), 5), dtype=np.int64)
    q[:, :3] = np.round(pos / (diag * 1e-6))
    q[:, 3:] = np.round(uv * 1e5)
    view = np.ascontiguousarray(q).view(np.dtype((np.void, q.dtype.itemsize * 5))).ravel()
    _, first, inv = np.unique(view, return_index=True, return_inverse=True)
    # soma as normais dos vértices fundidos para suavizar a costura
    acc = np.zeros((len(first), 3))
    np.add.at(acc, inv, nrm)
    acc /= np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-12)
    new_idx = inv[idx]
    tri = new_idx.reshape(-1, 3)
    ok = (tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])
    return pos[first], acc, uv[first], tri[ok].reshape(-1)


def compact(pos, nrm, uv, idx):
    used = np.unique(idx)
    remap = np.full(len(pos), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    return pos[used], nrm[used], uv[used], remap[idx]


def write_static(path, name, surfaces, src, mat_keys, textures=True):
    w = GLBWriter()
    tex_cache: dict = {}
    prims = []
    for (pos, nrm, uv, idx), mk in zip(surfaces, mat_keys):
        mat = copy_material(src, mk, w, tex_cache) if textures else w.add_material({"name": f"m{len(prims)}"})
        prims.append({
            "attributes": {
                "POSITION": w.add_accessor(pos.astype(np.float32), "VEC3", 34962, minmax=True),
                "NORMAL": w.add_accessor(nrm.astype(np.float32), "VEC3", 34962),
                "TEXCOORD_0": w.add_accessor(uv.astype(np.float32), "VEC2", 34962),
            },
            "indices": w.add_accessor(idx.astype(np.uint32), "SCALAR", 34963),
            "material": mat,
        })
    w.add_node(name, w.add_mesh(name, prims))
    w.save(path)


def read_ksm(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:4] == b"KSM1"
    n = struct.unpack_from("<I", data, 4)[0]
    off = 8
    out = []
    for _ in range(n):
        nv, ni, _s = struct.unpack_from("<III", data, off)
        off += 12
        pos = np.frombuffer(data, np.float32, nv * 3, off).reshape(-1, 3); off += nv * 12
        nrm = np.frombuffer(data, np.float32, nv * 3, off).reshape(-1, 3); off += nv * 12
        uv = np.frombuffer(data, np.float32, nv * 2, off).reshape(-1, 2); off += nv * 8
        idx = np.frombuffer(data, np.int32, ni, off).astype(np.int64); off += ni * 4
        out.append((pos, nrm, uv, idx))
    return out


def process_static(name: str, info: dict) -> dict:
    src = GLB(os.path.join(ROOT, name + ".glb"))
    groups = gather(src)
    allpos = np.concatenate([g[0] for g in groups.values()])
    lo, hi = allpos.min(0), allpos.max(0)
    height = hi[1] - lo[1]
    scale = info["height_m"] / height
    center = np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])
    diag = float(np.linalg.norm(hi - lo))
    mat_keys, surfaces = [], []
    tris_in = 0
    for mk, (pos, nrm, uv, idx) in groups.items():
        tris_in += len(idx) // 3
        pos, nrm, uv, idx = weld(pos, nrm, uv, idx, diag)
        pos = (pos - center) * scale
        mat_keys.append(mk)
        surfaces.append((pos, nrm, uv, idx))

    os.makedirs(TMP, exist_ok=True)
    prep = os.path.join(TMP, name + ".prep.glb")
    ksm = os.path.join(TMP, name + ".ksm")
    write_static(prep, name, surfaces, src, mat_keys, textures=False)
    r = subprocess.run([GODOT, "--headless", "--script", SIMPLIFY_GD, "--", prep, ksm, str(info["tris"])],
                       capture_output=True, text=True, timeout=1800)
    if r.returncode != 0 or not os.path.exists(ksm):
        raise RuntimeError(f"Godot falhou ({r.returncode}):\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}")
    simp = [compact(*s) for s in read_ksm(ksm)]
    out_path = os.path.join(OUT, name + ".glb")
    write_static(out_path, name, simp, src, mat_keys)
    os.remove(prep)
    os.remove(ksm)
    size = info["height_m"] * (hi - lo) / height
    return dict(tris_in=tris_in, tris_out=sum(len(s[3]) // 3 for s in simp),
                size_m=[round(float(v), 2) for v in size], scale_applied=True)


def process_animated(name: str, info: dict) -> dict:
    """Mantém esqueleto/animações; só reduz as imagens embutidas."""
    src = GLB(os.path.join(ROOT, name + ".glb"))
    j = json.loads(json.dumps(src.json))
    kinds = {}
    for m in j.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        for k in ("baseColorTexture", "metallicRoughnessTexture"):
            if k in pbr:
                kinds[j["textures"][pbr[k]["index"]]["source"]] = k
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            if k in m:
                kinds[j["textures"][m[k]["index"]]["source"]] = k
        sg = m.get("extensions", {}).get("KHR_materials_pbrSpecularGlossiness", {})
        if "diffuseTexture" in sg:
            kinds[j["textures"][sg["diffuseTexture"]["index"]]["source"]] = "baseColorTexture"
    img_views = {}
    for i, img in enumerate(j.get("images", [])):
        data, _ = src.image_bytes(i)
        enc, mime = encode_image(data, TEX_MAX[kinds.get(i, "baseColorTexture")], kinds.get(i, "baseColorTexture"))
        img_views[img["bufferView"]] = enc
        img["mimeType"] = mime
    blob = bytearray()
    for vi, bv in enumerate(j["bufferViews"]):
        data = img_views.get(vi, src.buffer_view_bytes(vi))
        while len(blob) % 4:
            blob += b"\0"
        bv["byteOffset"] = len(blob)
        bv["byteLength"] = len(data)
        blob += data
    while len(blob) % 4:
        blob += b"\0"
    j["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    with open(os.path.join(OUT, name + ".glb"), "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942)); f.write(blob)
    anims = [a.get("name", f"anim{i}") for i, a in enumerate(j.get("animations", []))]
    return dict(animations=anims, scale_applied=False)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    man_path = os.path.join(OUT, "manifest.json")
    manifest = json.load(open(man_path, encoding="utf-8")) if os.path.exists(man_path) else {}
    for name, info in CATALOG.items():
        if args and not any(a in name for a in args):
            continue
        out_path = os.path.join(OUT, name + ".glb")
        if os.path.exists(out_path) and name in manifest and not force:
            print(f"[ok] {name} (já processado)")
            continue
        t = time.time()
        print(f"[..] {name}", flush=True)
        res = process_animated(name, info) if info.get("animated") else process_static(name, info)
        entry = {k: v for k, v in info.items() if k != "tris"}
        entry.update(res)
        entry["file"] = f"res://assets/models/{name}.glb"
        entry["mb"] = round(os.path.getsize(out_path) / 1e6, 1)
        manifest[name] = entry
        json.dump(manifest, open(man_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
        print(f"[ok] {name}: {res.get('tris_in', '-')} -> {res.get('tris_out', '-')} tris, {entry['mb']} MB, {time.time() - t:.0f}s", flush=True)


if __name__ == "__main__":
    main()
