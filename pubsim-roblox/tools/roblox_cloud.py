#!/usr/bin/env python3
"""Roblox Open Cloud helpers for CI: upload the packed audio and publish the place.

Everything is driven by two GitHub secrets:
  ROBLOX_API_KEY   an Open Cloud key with "universe-places: Write" and "assets: Read + Write"
  ROBLOX_PLACE_ID  the number in your game's URL (roblox.com/games/<PLACE_ID>/...)
The universe (experience) id and the owner are looked up from the place id.

  roblox_cloud.py upload    upload any audio file not yet uploaded; records ids in assets.lock.json
  roblox_cloud.py publish <file.rbxlx>   publish the place as the live version
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
KEY = os.environ.get("ROBLOX_API_KEY", "").strip()
PLACE = os.environ.get("ROBLOX_PLACE_ID", "").strip()
LOCK = os.path.join(ROOT, "assets.lock.json")


def http(method, url, body=None, headers=None, auth=True):
    h = dict(headers or {})
    if auth:
        h["x-api-key"] = KEY
    req = urllib.request.Request(url, data=body, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw[:1] in (b"{", b"[") else raw.decode(errors="replace"))
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw.decode(errors="replace")


def universe_id():
    code, body = http("GET", f"https://apis.roblox.com/universes/v1/places/{PLACE}/universe", auth=False)
    if code != 200 or not isinstance(body, dict) or not body.get("universeId"):
        sys.exit(f"Couldn't find the game for place {PLACE} ({code}: {body}). Check ROBLOX_PLACE_ID.")
    return int(body["universeId"])


def creator(universe):
    """Who owns the game (the audio is uploaded to the same owner)."""
    code, d = http("GET", f"https://develop.roblox.com/v1/universes/{universe}", auth=False)
    if code == 200 and isinstance(d, dict) and int(d.get("creatorTargetId") or 0) > 0:
        print(f"Game: {d.get('name')!r} (start place {d.get('rootPlaceId')}), owned by "
              f"{d.get('creatorType')} {d.get('creatorName')!r}")
        if str(d.get("rootPlaceId")) != PLACE:
            print(f"::warning::ROBLOX_PLACE_ID ({PLACE}) isn't this game's start place ({d.get('rootPlaceId')}).")
        return ("groupId" if d.get("creatorType") == "Group" else "userId"), str(d["creatorTargetId"])
    code, body = http("GET", f"https://games.roblox.com/v1/games?universeIds={universe}", auth=False)
    c = (body.get("data") or [{}])[0].get("creator", {}) if isinstance(body, dict) else {}
    if int(c.get("id") or 0) <= 0:
        sys.exit(f"Couldn't look up who owns game {universe} ({code}: {d}). Check ROBLOX_PLACE_ID is the "
                 "start place of your published game.")
    return ("groupId" if c["type"] == "Group" else "userId"), str(c["id"])


def multipart(req, filename, data, ctype="audio/ogg"):
    boundary = "----pubsim" + uuid.uuid4().hex
    head = (f"--{boundary}\r\n"
            f"Content-Disposition: form-data; name=\"request\"\r\n\r\n"
            f"{json.dumps(req)}\r\n"
            f"--{boundary}\r\n"
            f"Content-Disposition: form-data; name=\"fileContent\"; filename=\"{filename}\"\r\n"
            f"Content-Type: {ctype}\r\n\r\n").encode()
    body = head + data + f"\r\n--{boundary}--\r\n".encode()
    return body, {"Content-Type": f"multipart/form-data; boundary={boundary}"}


def wait_op(op, tries=100):
    for _ in range(tries):
        time.sleep(3)
        code, st = http("GET", f"https://apis.roblox.com/assets/v1/{op}")
        if isinstance(st, dict) and st.get("done"):
            return st
    return None


def upload_models():
    """The APK's pub and people (assets/world, assets/people: .glb), each uploaded once (by
    content hash) as a Model."""
    import hashlib
    lock = json.load(open(LOCK)) if os.path.exists(LOCK) else {}
    models = lock.setdefault("models", {})
    todo = []
    for sub in ("world",):  # never the people: their skin textures broke Roblox rules
        folder = os.path.join(ROOT, "assets", sub)
        if not os.path.isdir(folder):
            continue
        for f in sorted(x for x in os.listdir(folder) if x.endswith(".glb")):
            data = open(os.path.join(folder, f), "rb").read()
            sha = hashlib.sha256(data).hexdigest()
            if not models.get(sha, {}).get("assetId"):
                todo.append((f, sha, data))
    if not todo:
        print("All models already uploaded.")
        return
    kind, owner = creator(universe_id())
    for f, sha, data in todo:
        req = {"assetType": "Model", "displayName": f"Irish Pub Simulator {f[:-4]}",
               "description": "The pub from The Irish Pub Simulator.",
               "creationContext": {"creator": {kind: owner}, "expectedPrice": 0}}
        code, res = http("POST", "https://apis.roblox.com/assets/v1/assets", *multipart(req, f, data, "model/gltf-binary"))
        if code not in (200, 201) or not isinstance(res, dict) or "path" not in res:
            print(f"::warning::Model upload stopped at {f} ({code}): {res}")
            break
        st = wait_op(res["path"])
        asset = ((st or {}).get("response") or {}).get("assetId")
        if not asset:
            print(f"::warning::{f} was not accepted: {st}")
            continue
        models[sha] = {"assetId": int(asset), "file": f}
        print(f"uploaded {f} ({len(data) // 1024} KB) -> {asset}")
        json.dump(lock, open(LOCK, "w"), indent=1)
    json.dump(lock, open(LOCK, "w"), indent=1)


def upload():
    upload_models()
    amap = json.load(open(os.path.join(ROOT, "build", "audio_map.json")))
    lock = json.load(open(LOCK)) if os.path.exists(LOCK) else {}
    audio = lock.setdefault("audio", {})
    todo = [s for s in amap["sprites"] if not audio.get(s["sha256"], {}).get("assetId")]
    if not todo:
        print("All audio already uploaded.")
        return
    # voices and effects first (they're what the game misses most), then the songs
    def importance(s):
        idx = amap["sprites"].index(s)
        clips = [k for k, c in amap["clips"].items() if c["sprite"] == idx]
        return -sum(1 for k in clips if not k.startswith("music/"))
    todo.sort(key=importance)
    kind, owner = creator(universe_id())
    print(f"Uploading as {kind} {owner}")
    for s in todo:
        path = os.path.join(ROOT, "build", "audio", s["file"])
        data = open(path, "rb").read()
        name = f"Irish Pub Simulator audio {s['file'][7:9]}"
        code, res = 0, None
        # the creator id as a string (what the docs show), then as a number
        for who in (owner, int(owner)):
            req = {"assetType": "Audio", "displayName": name,
                   "description": "Music, voices and sound effects for The Irish Pub Simulator.",
                   "creationContext": {"creator": {kind: who}, "expectedPrice": 0}}
            code, res = http("POST", "https://apis.roblox.com/assets/v1/assets", *multipart(req, s["file"], data))
            if not (code == 400 and "CreatorType" in str(res)):
                break
        if code not in (200, 201) or not isinstance(res, dict) or "path" not in res:
            print(f"::warning::Audio upload stopped at {s['file']} ({code}): {res}. "
                  "Roblox limits audio uploads per month; the rest will go up on a later build.")
            break
        op = res["path"]
        asset = None
        for _ in range(60):
            time.sleep(3)
            code, st = http("GET", f"https://apis.roblox.com/assets/v1/{op}")
            if isinstance(st, dict) and st.get("done"):
                asset = (st.get("response") or {}).get("assetId")
                if not asset:
                    print(f"::warning::{s['file']} was not accepted: {st}")
                break
        if asset:
            audio[s["sha256"]] = {"assetId": int(asset), "file": s["file"]}
            print(f"uploaded {s['file']} -> rbxassetid://{asset}")
            json.dump(lock, open(LOCK, "w"), indent=1)
    json.dump(lock, open(LOCK, "w"), indent=1)


def publish(path):
    uni = universe_id()
    print(f"Publishing {os.path.basename(path)} ({os.path.getsize(path) // 1024} KB) to place {PLACE} in game {uni}")
    data = open(path, "rb").read()
    url = f"https://apis.roblox.com/universes/v1/{uni}/places/{PLACE}/versions?versionType=Published"
    code, res = 0, None
    for ctype in (["application/octet-stream"] if path.endswith(".rbxl") else ["application/xml", "application/octet-stream"]):
        code, res = http("POST", url, data, {"Content-Type": ctype})
        if code == 200:
            break
        print(f"Publishing as {ctype} failed ({code}): {res}")
    if code != 200:
        sys.exit(f"Publishing failed ({code}): {res}")
    print(f"Published place {PLACE} (game {uni}), version {res.get('versionNumber') if isinstance(res, dict) else res}")
    devices(uni)


def devices(uni):
    """Let the game be played on computers, phones, tablets and consoles (Xbox and PlayStation)."""
    want = {"desktopEnabled": True, "mobileEnabled": True, "tabletEnabled": True, "consoleEnabled": True}
    mask = ",".join(want)
    code, res = http("PATCH", f"https://apis.roblox.com/cloud/v2/universes/{uni}?updateMask={mask}",
                     json.dumps(want).encode(), {"Content-Type": "application/json"})
    if code == 200:
        print("Devices on: computer, phone, tablet, console")
    else:
        print(f"::warning::Couldn't switch on all devices ({code}): {res}. Give the API key the "
              "'universe' Write permission, or tick Computer, Phone, Tablet and Console under "
              "Creator Dashboard > the game > Places > Settings.")


if __name__ == "__main__":
    if not KEY or not PLACE:
        sys.exit("ROBLOX_API_KEY and ROBLOX_PLACE_ID are needed.")
    if sys.argv[1] == "upload":
        upload()
    elif sys.argv[1] == "publish":
        publish(sys.argv[2])
