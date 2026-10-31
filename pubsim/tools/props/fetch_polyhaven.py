#!/usr/bin/env python3
"""Downloads the CC0 Poly Haven models listed in props.json (glTF, 1k textures) into
tools/props/src/<id>/ (ignored by git). blender_props.py then turns them into game assets."""
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")


def get(url, dst=None):
    req = urllib.request.Request(url, headers={"User-Agent": "pubsim-asset-fetch"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    if dst:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(data)
    return data


def main():
    with open(os.path.join(HERE, "props.json")) as f:
        props = json.load(f)["props"]
    for p in props:
        pid = p["polyhaven"]
        d = os.path.join(SRC, pid)
        if os.path.exists(os.path.join(d, pid + ".gltf")):
            continue
        info = json.loads(get("https://api.polyhaven.com/files/" + pid))["gltf"]["1k"]["gltf"]
        get(info["url"], os.path.join(d, pid + ".gltf"))
        for rel, inc in info.get("include", {}).items():
            get(inc["url"], os.path.join(d, rel))
        print("fetched", pid)


if __name__ == "__main__":
    main()
