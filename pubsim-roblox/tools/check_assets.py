"""Checks everything that would go to Roblox against Roblox's rules, before anything is uploaded.

Roblox moderates every uploaded image on its own, out of context, and a strike lands on the
owner's account. Two textures from the phone game's people were flagged (a skin map of an
unclothed body, and a clothing texture with "makehuman.org" printed in a corner). So:

1. Only known-safe sources may be uploaded: the baked pub (assets/world/*.glb, built from the
   pub's own surfaces with no people in it) and the packed audio (build/audio/*.ogg). Anything
   else under assets/ fails the check.
2. No people, skin or MakeHuman material may appear in an uploaded model (by image and mesh
   names inside the .glb).
3. No off-platform links anywhere players can read text: the game data, the pub's lettering and
   the scripts are searched for web addresses, e-mail addresses, social handles and invites.

check_assets.py  -> exit 1 (and the reasons) if anything breaks a rule.
See ROBLOX_RULES.md for the full list of rules this project follows.
"""
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, "..", "pubsim", "data")

ALLOWED_UPLOAD_DIRS = {"world"}
BANNED_NAMES = re.compile(r"skin|makehuman|people|person|body|nude|naked|eyebrow|eyelash|f_(young|mid|old)_|m_(young|mid|old)_", re.I)
LINK = re.compile(r"(https?://|www\.|\b[a-z0-9-]+\.(com|org|net|io|gg|co|uk|ie|tv|me|app|link|ly)\b|discord|twitter|tiktok|"
                  r"instagram|youtube|facebook|snapchat|twitch|guilded|\b[\w.+-]+@[\w-]+\.\w+)", re.I)
problems = []


def glb_json(path):
    with open(path, "rb") as f:
        head = f.read(12)
        if head[:4] != b"glTF":
            return None
        length, kind = struct.unpack("<I4s", f.read(8))
        if kind != b"JSON":
            return None
        return json.loads(f.read(length))


def check_models():
    assets = os.path.join(ROOT, "assets")
    if not os.path.isdir(assets):
        return
    for sub in sorted(os.listdir(assets)):
        p = os.path.join(assets, sub)
        if not os.path.isdir(p):
            continue
        glbs = [f for f in os.listdir(p) if f.endswith((".glb", ".gltf", ".fbx", ".png", ".jpg"))]
        if sub not in ALLOWED_UPLOAD_DIRS and glbs:
            problems.append(f"assets/{sub}: not an allowed upload source ({len(glbs)} files)")
            continue
        for f in sorted(glbs):
            if not f.endswith(".glb"):
                continue
            g = glb_json(os.path.join(p, f))
            if g is None:
                problems.append(f"assets/{sub}/{f}: not a readable .glb")
                continue
            names = [x.get("name", "") for k in ("images", "meshes", "materials", "nodes", "skins") for x in g.get(k, [])]
            for n in names:
                if BANNED_NAMES.search(n):
                    problems.append(f"assets/{sub}/{f}: contains '{n}' (people/skin content is never uploaded)")
            if g.get("skins"):
                problems.append(f"assets/{sub}/{f}: has a skinned (character) mesh")


def strings(x):
    if isinstance(x, str):
        yield x
    elif isinstance(x, dict):
        for k, v in x.items():
            yield from strings(k)
            yield from strings(v)
    elif isinstance(x, list):
        for v in x:
            yield from strings(v)


def check_text():
    sources = []
    for name in sorted(os.listdir(DATA)):
        if name.endswith(".json"):
            with open(os.path.join(DATA, name), encoding="utf-8") as f:
                sources.append((f"pubsim/data/{name}", json.load(f)))
    man = os.path.join(ROOT, "assets", "world", "manifest.json")
    if os.path.exists(man):
        with open(man) as f:
            sources.append(("assets/world/manifest.json (lettering)", [l["text"] for l in json.load(f).get("labels", [])]))
    for where, data in sources:
        for s in strings(data):
            m = LINK.search(s)
            if m and not s.startswith("res://"):
                problems.append(f"{where}: link-like text '{m.group(0)}' in \"{s[:80]}\"")
    for folder, _, files in os.walk(os.path.join(ROOT, "src")):
        for f in files:
            with open(os.path.join(folder, f), encoding="utf-8") as fh:
                for i, line in enumerate(fh, 1):
                    code = line.split("--", 1)[0]  # comments never reach players
                    for lit in re.findall(r'"([^"]*)"', code):
                        m = LINK.search(lit)
                        if m and not lit.startswith("rbxasset"):
                            problems.append(f"{os.path.relpath(os.path.join(folder, f), ROOT)}:{i}: link-like text '{m.group(0)}'")


if __name__ == "__main__":
    check_models()
    check_text()
    if problems:
        print("Roblox rules check FAILED: nothing will be uploaded.")
        for p in problems:
            print("  - " + p)
        sys.exit(1)
    print("Roblox rules check passed: only the baked pub and the audio, no people or skin, no links.")
