"""Packs the phone game's people (pubsim/assets/people_mh/*.gltf with their .bin and textures)
into single .glb files for Roblox, which takes one file per model.

The mesh, the rig and the textures are copied as they are; nothing is re-encoded, so the same
person looks the same in both games. The normal maps are left out: Roblox's importer only takes
the colour textures from a model upload.

pack_people.py  -> assets/people/<name>.glb
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "..", "pubsim", "assets", "people_mh")
OUT = os.path.join(ROOT, "assets", "people")


def pad4(b, fill=b"\0"):
    return b + fill * ((4 - len(b) % 4) % 4)


def pack(name):
    with open(os.path.join(SRC, name + ".gltf")) as f:
        g = json.load(f)
    with open(os.path.join(SRC, g["buffers"][0]["uri"]), "rb") as f:
        blob = bytearray(f.read())
    # drop normal maps (and anything that points at them)
    for mat in g.get("materials", []):
        mat.pop("normalTexture", None)
    used = set()
    for mat in g.get("materials", []):
        t = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if t:
            used.add(g["textures"][t["index"]]["source"])
    # images into the binary buffer
    for i, img in enumerate(g.get("images", [])):
        uri = img.pop("uri", None)
        if uri is None:
            continue
        if i not in used:
            data = b""
        else:
            with open(os.path.join(SRC, uri), "rb") as f:
                data = f.read()
        while len(blob) % 4:
            blob.append(0)
        g.setdefault("bufferViews", []).append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)})
        img["bufferView"] = len(g["bufferViews"]) - 1
        blob += data
    while len(blob) % 4:
        blob.append(0)
    g["buffers"] = [{"byteLength": len(blob)}]
    js = pad4(json.dumps(g, separators=(",", ":")).encode(), b" ")
    total = 12 + 8 + len(js) + 8 + len(blob)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(blob), b"BIN\0") + blob
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".glb")
    with open(path, "wb") as f:
        f.write(out)
    return path, len(out)


if __name__ == "__main__":
    names = sorted(f[:-5] for f in os.listdir(SRC) if f.endswith(".gltf"))
    for n in names:
        p, size = pack(n)
        print(f"{os.path.basename(p)}: {size // 1024} KB")
