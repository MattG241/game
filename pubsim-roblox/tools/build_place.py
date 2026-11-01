#!/usr/bin/env python3
"""Builds the Roblox place file (IrishPubSimulator.rbxlx) from the Luau sources.

No Roblox tools are needed: the place is written straight in Roblox's XML place format, which
Roblox Studio opens and the Open Cloud place-publishing API accepts.

  src/shared/*.luau  -> ReplicatedStorage.Shared  (ModuleScripts)
  src/server/*.luau  -> ServerScriptService.Server (*.server.luau are Scripts, the rest ModuleScripts)
  src/client/*.luau  -> StarterPlayer.StarterPlayerScripts.Client (*.client.luau are LocalScripts)

The game's data (drinks, upgrades, staff, events...) comes from ../pubsim/data/*.json, so the
phone game and the Roblox game share one set of numbers. Audio asset ids come from
assets.lock.json and build/audio_map.json when they exist (the game runs silent without them).

Usage: build_place.py [out.rbxlx]
"""
import json
import os
import sys
import uuid
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, "..", "pubsim", "data")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "IrishPubSimulator.rbxlx")


def ref():
    return "RBX" + uuid.uuid4().hex.upper()


def luau_value(v, indent=0):
    """A JSON value as a Luau literal."""
    pad = "\t" * (indent + 1)
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "") + '"'
    if isinstance(v, list):
        if not v:
            return "{}"
        return "{\n" + "".join(pad + luau_value(x, indent + 1) + ",\n" for x in v) + "\t" * indent + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n" + "".join(pad + "[" + luau_value(str(k)) + "] = " + luau_value(x, indent + 1) + ",\n"
                               for k, x in v.items()) + "\t" * indent + "}"
    raise TypeError(type(v))


class Item:
    def __init__(self, cls, name, props=None, path=None):
        self.cls = cls
        self.name = name
        self.props = props or []      # [(xml type, name, value)]
        self.children = []
        self.path = path              # the source file, for the sourcemap

    def sourcemap(self):
        d = {"name": self.name, "className": self.cls}
        if self.path:
            d["filePaths"] = [os.path.relpath(self.path, ROOT)]
        if self.children:
            d["children"] = [c.sourcemap() for c in self.children]
        return d

    def add(self, item):
        self.children.append(item)
        return item

    def xml(self, depth=1):
        ind = "  " * depth
        out = [f'{ind}<Item class="{self.cls}" referent="{ref()}">', f"{ind}  <Properties>",
               f'{ind}    <string name="Name">{escape(self.name)}</string>']
        for t, n, v in self.props:
            if t == "ProtectedString":
                body = v.replace("]]>", "]]]]><![CDATA[>")
                out.append(f'{ind}    <ProtectedString name="{n}"><![CDATA[{body}]]></ProtectedString>')
            elif t == "Color3":
                out.append(f'{ind}    <Color3 name="{n}"><R>{v[0]}</R><G>{v[1]}</G><B>{v[2]}</B></Color3>')
            elif t == "Vector3":
                out.append(f'{ind}    <Vector3 name="{n}"><X>{v[0]}</X><Y>{v[1]}</Y><Z>{v[2]}</Z></Vector3>')
            elif t == "CoordinateFrame":
                x, y, z = v
                out.append(f'{ind}    <CoordinateFrame name="{n}"><X>{x}</X><Y>{y}</Y><Z>{z}</Z>'
                           "<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12>"
                           "<R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>")
            elif t == "bool":
                out.append(f'{ind}    <bool name="{n}">{"true" if v else "false"}</bool>')
            else:
                out.append(f'{ind}    <{t} name="{n}">{escape(str(v))}</{t}>')
        out.append(f"{ind}  </Properties>")
        for c in self.children:
            out.append(c.xml(depth + 1))
        out.append(f"{ind}</Item>")
        return "\n".join(out)


def script_item(path, kind):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    base = os.path.basename(path)
    for suffix in (".server.luau", ".client.luau", ".luau"):
        if base.endswith(suffix):
            base = base[: -len(suffix)]
            break
    return Item(kind, base, [("ProtectedString", "Source", src)], path)


def generated(name, src):
    """A generated ModuleScript, also written to build/ (for the tests and the code checker)."""
    path = os.path.join(ROOT, "build", name + ".luau")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    return Item("ModuleScript", name, [("ProtectedString", "Source", src)], path)


def add_folder(parent, folder, script_suffix, script_class):
    for name in sorted(os.listdir(folder)):
        p = os.path.join(folder, name)
        if os.path.isdir(p):
            sub = parent.add(Item("Folder", name))
            add_folder(sub, p, script_suffix, script_class)
        elif name.endswith(script_suffix):
            parent.add(script_item(p, script_class))
        elif name.endswith(".luau"):
            parent.add(script_item(p, "ModuleScript"))


def data_module():
    tables = {}
    for name in sorted(os.listdir(DATA)):
        if name.endswith(".json"):
            with open(os.path.join(DATA, name), encoding="utf-8") as f:
                tables[name[:-5]] = json.load(f)
    src = ("--!nocheck\n-- Generated by tools/build_place.py from pubsim/data/*.json: the phone game's own numbers.\n"
           "return " + luau_value(tables) + "\n")
    return generated("Data", src)


def audio_module():
    """Clip name -> {asset, start, len}, joining the packed sprites with the uploaded asset ids."""
    clips = {}
    amap_path = os.path.join(ROOT, "build", "audio_map.json")
    lock_path = os.path.join(ROOT, "assets.lock.json")
    if os.path.exists(amap_path):
        with open(amap_path) as f:
            amap = json.load(f)
        lock = {}
        if os.path.exists(lock_path):
            with open(lock_path) as f:
                lock = json.load(f).get("audio", {})
        for key, c in amap["clips"].items():
            sprite = amap["sprites"][c["sprite"]]
            asset = lock.get(sprite["sha256"], {}).get("assetId", 0)
            if asset:
                clips[key] = {"asset": int(asset), "start": c["start"], "len": c["len"]}
    src = ("--!nocheck\n-- Generated by tools/build_place.py: where each sound lives in the uploaded audio.\n"
           "return " + luau_value(clips) + "\n")
    return generated("AudioMap", src)


def world_module():
    """The APK's pub, exported from the Godot project (assets/world): where each baked piece goes,
    the see-through pieces, the lights, the lettering and the floor plan, joined with the uploaded
    model ids. Empty until the export exists (the Roblox-built pub is used then)."""
    import hashlib
    folder = os.path.join(ROOT, "assets", "world")
    man_path = os.path.join(folder, "manifest.json")
    world = {}
    if os.path.exists(man_path):
        with open(man_path) as f:
            man = json.load(f)
        lock = {}
        lock_path = os.path.join(ROOT, "assets.lock.json")
        if os.path.exists(lock_path):
            with open(lock_path) as f:
                lock = json.load(f).get("models", {})
        files = []
        for entry in man["files"]:
            path = os.path.join(folder, entry["file"])
            sha = hashlib.sha256(open(path, "rb").read()).hexdigest() if os.path.exists(path) else ""
            files.append({"file": entry["file"], "asset": int(lock.get(sha, {}).get("assetId", 0)),
                          "chunks": entry["chunks"]})
        chunks = {c["name"]: {"min": c["min"], "max": c["max"], "tag": c["tag"]} for c in man["chunks"]}
        clear = {c["name"]: {"min": c["min"], "max": c["max"], "tag": c["tag"], "color": c["color"],
                             "transparency": c["transparency"]} for c in man.get("clear", [])}
        world = {"files": files, "chunks": chunks, "clear": clear, "lights": man.get("lights", []),
                 "labels": man.get("labels", []), "layout": man.get("layout", {})}
    src = ("--!nocheck\n-- Generated by tools/build_place.py from assets/world/manifest.json: the APK's pub.\n"
           "return " + luau_value(world) + "\n")
    return generated("ApkWorld", src)


def people_module():
    """The phone game's people (assets/people/*.glb) with their uploaded model ids."""
    import hashlib
    folder = os.path.join(ROOT, "assets", "people")
    lock = {}
    lock_path = os.path.join(ROOT, "assets.lock.json")
    if os.path.exists(lock_path):
        with open(lock_path) as f:
            lock = json.load(f).get("models", {})
    people = {}
    if os.path.isdir(folder):
        for f in sorted(x for x in os.listdir(folder) if x.endswith(".glb")):
            sha = hashlib.sha256(open(os.path.join(folder, f), "rb").read()).hexdigest()
            name = f[:-4]
            people[name] = {"asset": int(lock.get(sha, {}).get("assetId", 0)), "gender": name[:1],
                            "age": name.split("_")[1] if "_" in name else "mid"}
    src = ("--!nocheck\n-- Generated by tools/build_place.py: the phone game's people and their model ids.\n"
           "return " + luau_value(people) + "\n")
    return generated("ApkPeople", src)


def build():
    root = []
    rs = Item("ReplicatedStorage", "ReplicatedStorage")
    shared = rs.add(Item("Folder", "Shared"))
    add_folder(shared, os.path.join(ROOT, "src", "shared"), ".never", "ModuleScript")
    shared.add(data_module())
    shared.add(audio_module())
    shared.add(world_module())
    shared.add(people_module())
    root.append(rs)

    sss = Item("ServerScriptService", "ServerScriptService")
    server = sss.add(Item("Folder", "Server"))
    add_folder(server, os.path.join(ROOT, "src", "server"), ".server.luau", "Script")
    root.append(sss)

    sp = Item("StarterPlayer", "StarterPlayer", [
        ("token", "CameraMode", 1), ("float", "CameraMaxZoomDistance", 0.5), ("float", "CameraMinZoomDistance", 0.5),
        ("bool", "LoadCharacterAppearance", True)])
    sps = sp.add(Item("StarterPlayerScripts", "StarterPlayerScripts"))
    client = sps.add(Item("Folder", "Client"))
    add_folder(client, os.path.join(ROOT, "src", "client"), ".client.luau", "LocalScript")
    sp.add(Item("StarterCharacterScripts", "StarterCharacterScripts"))
    root.append(sp)

    # Future lighting: real shadows and light from every lamp (set here: scripts can't change it)
    root.append(Item("Lighting", "Lighting", [
        ("token", "Technology", 4), ("float", "ClockTime", 20.5), ("float", "Brightness", 1.2),
        ("Color3", "Ambient", (0.16, 0.13, 0.11)), ("Color3", "OutdoorAmbient", (0.22, 0.22, 0.27)),
        ("bool", "GlobalShadows", True), ("float", "EnvironmentDiffuseScale", 0.6),
        ("float", "EnvironmentSpecularScale", 0.8), ("float", "ExposureCompensation", 0.2)]))

    ws = Item("Workspace", "Workspace")
    # where people appear: just inside the front door (the floor is built by the server at start)
    ws.add(Item("SpawnLocation", "Spawn", [
        ("bool", "Anchored", True), ("bool", "CanCollide", False), ("float", "Transparency", 1),
        ("CoordinateFrame", "CFrame", (0, 1.5, 12)), ("Vector3", "size", (6, 1, 4)),
        ("bool", "Neutral", True), ("int", "Duration", 0)]))
    root.append(ws)

    body = "\n".join(i.xml() for i in root)
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
           "  <External>null</External>\n  <External>nil</External>\n" + body + "\n</roblox>\n")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(xml)
    # a Rojo-style sourcemap so luau-lsp can follow require(script.Parent.X) between modules
    smap = {"name": "IrishPubSimulator", "className": "DataModel", "children": [i.sourcemap() for i in root]}
    with open(os.path.join(ROOT, "build", "sourcemap.json"), "w") as f:
        json.dump(smap, f, indent=1)
    print(f"wrote {OUT} ({len(xml) // 1024} KB)")


if __name__ == "__main__":
    build()
