"""Leitura/escrita mínima de arquivos GLB (glTF 2.0 binário) usando numpy.

Usado pelo pipeline de assets do KelwinSouls. Sem dependências além de numpy.
"""
from __future__ import annotations

import json
import struct

import numpy as np

COMP_DTYPE = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
TYPE_N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class GLB:
    def __init__(self, path: str):
        with open(path, "rb") as f:
            data = f.read()
        magic, _ver, _length = struct.unpack_from("<III", data, 0)
        if magic != 0x46546C67:
            raise ValueError(f"{path} não é GLB")
        off = 12
        self.json: dict = {}
        self.bin = b""
        while off < len(data):
            clen, ctype = struct.unpack_from("<II", data, off)
            chunk = data[off + 8: off + 8 + clen]
            if ctype == 0x4E4F534A:
                self.json = json.loads(chunk)
            elif ctype == 0x004E4942:
                self.bin = chunk
            off += 8 + clen

    # ---- leitura -------------------------------------------------------
    def buffer_view_bytes(self, idx: int) -> bytes:
        bv = self.json["bufferViews"][idx]
        o = bv.get("byteOffset", 0)
        return self.bin[o: o + bv["byteLength"]]

    def accessor(self, idx: int) -> np.ndarray:
        acc = self.json["accessors"][idx]
        n = TYPE_N[acc["type"]]
        dt = np.dtype(COMP_DTYPE[acc["componentType"]])
        count = acc["count"]
        if "bufferView" not in acc:
            return np.zeros((count, n), dtype=dt)
        bv = self.json["bufferViews"][acc["bufferView"]]
        base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = bv.get("byteStride", 0) or dt.itemsize * n
        if stride == dt.itemsize * n:
            arr = np.frombuffer(self.bin, dtype=dt, count=count * n, offset=base).reshape(count, n)
        else:
            raw = np.frombuffer(self.bin, dtype=np.uint8, count=stride * (count - 1) + dt.itemsize * n, offset=base)
            arr = np.lib.stride_tricks.as_strided(raw, shape=(count, dt.itemsize * n), strides=(stride, 1))
            arr = np.ascontiguousarray(arr).view(dt).reshape(count, n)
        if acc.get("normalized") and dt.kind in "iu":
            arr = arr.astype(np.float32) / np.iinfo(dt).max
        return arr

    def image_bytes(self, idx: int) -> tuple[bytes, str]:
        img = self.json["images"][idx]
        return self.buffer_view_bytes(img["bufferView"]), img.get("mimeType", "image/png")

    def world_matrices(self) -> dict[int, np.ndarray]:
        nodes = self.json.get("nodes", [])
        out: dict[int, np.ndarray] = {}

        def local(n: dict) -> np.ndarray:
            if "matrix" in n:
                return np.array(n["matrix"], dtype=np.float64).reshape(4, 4).T
            t = np.array(n.get("translation", [0, 0, 0]), dtype=np.float64)
            x, y, z, w = n.get("rotation", [0, 0, 0, 1])
            s = np.array(n.get("scale", [1, 1, 1]), dtype=np.float64)
            r = np.array([
                [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
            ])
            m = np.eye(4)
            m[:3, :3] = r * s
            m[:3, 3] = t
            return m

        def walk(i: int, parent: np.ndarray):
            m = parent @ local(nodes[i])
            out[i] = m
            for c in nodes[i].get("children", []):
                walk(c, m)

        scene = self.json.get("scenes", [{}])[self.json.get("scene", 0)]
        for r in scene.get("nodes", range(len(nodes))):
            walk(r, np.eye(4))
        return out


class GLBWriter:
    """Monta um GLB simples: meshes estáticas + materiais PBR + imagens embutidas."""

    def __init__(self):
        self.j = {"asset": {"version": "2.0", "generator": "KelwinSouls asset pipeline"},
                  "buffers": [{"byteLength": 0}], "bufferViews": [], "accessors": [],
                  "images": [], "textures": [], "samplers": [{"magFilter": 9729, "minFilter": 9987}],
                  "materials": [], "meshes": [], "nodes": [], "scenes": [{"nodes": []}], "scene": 0}
        self.blob = bytearray()

    def _view(self, data: bytes, target: int | None = None) -> int:
        while len(self.blob) % 4:
            self.blob += b"\0"
        bv = {"buffer": 0, "byteOffset": len(self.blob), "byteLength": len(data)}
        if target:
            bv["target"] = target
        self.blob += data
        self.j["bufferViews"].append(bv)
        return len(self.j["bufferViews"]) - 1

    def add_accessor(self, arr: np.ndarray, kind: str, target: int | None = None, minmax=False) -> int:
        comp = {np.dtype(np.float32): 5126, np.dtype(np.uint32): 5125, np.dtype(np.uint16): 5123}[arr.dtype]
        acc = {"bufferView": self._view(np.ascontiguousarray(arr).tobytes(), target),
               "componentType": comp, "count": int(arr.shape[0]), "type": kind}
        if minmax:
            acc["min"] = arr.min(axis=0).tolist()
            acc["max"] = arr.max(axis=0).tolist()
        self.j["accessors"].append(acc)
        return len(self.j["accessors"]) - 1

    def add_image(self, data: bytes, mime: str) -> int:
        self.j["images"].append({"bufferView": self._view(data), "mimeType": mime})
        self.j["textures"].append({"source": len(self.j["images"]) - 1, "sampler": 0})
        return len(self.j["textures"]) - 1

    def add_material(self, mat: dict) -> int:
        self.j["materials"].append(mat)
        return len(self.j["materials"]) - 1

    def add_mesh(self, name: str, prims: list[dict]) -> int:
        self.j["meshes"].append({"name": name, "primitives": prims})
        return len(self.j["meshes"]) - 1

    def add_node(self, name: str, mesh: int) -> int:
        self.j["nodes"].append({"name": name, "mesh": mesh})
        idx = len(self.j["nodes"]) - 1
        self.j["scenes"][0]["nodes"].append(idx)
        return idx

    def save(self, path: str):
        while len(self.blob) % 4:
            self.blob += b"\0"
        self.j["buffers"][0]["byteLength"] = len(self.blob)
        for k in ("images", "textures", "materials"):
            if not self.j[k]:
                del self.j[k]
        if "textures" not in self.j:
            self.j.pop("samplers", None)
        js = json.dumps(self.j, separators=(",", ":")).encode()
        js += b" " * ((4 - len(js) % 4) % 4)
        total = 12 + 8 + len(js) + 8 + len(self.blob)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack("<II", len(self.blob), 0x004E4942))
            f.write(self.blob)
