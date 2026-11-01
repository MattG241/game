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
    code, body = http("GET", f"https://games.roblox.com/v1/games?universeIds={universe}", auth=False)
    if code != 200 or not body.get("data"):
        sys.exit(f"Couldn't look up the game's owner ({code}: {body}).")
    c = body["data"][0]["creator"]
    return ("groupId" if c["type"] == "Group" else "userId"), str(c["id"])


def multipart(req, filename, data):
    boundary = "----pubsim" + uuid.uuid4().hex
    head = (f"--{boundary}\r\n"
            f"Content-Disposition: form-data; name=\"request\"\r\n\r\n"
            f"{json.dumps(req)}\r\n"
            f"--{boundary}\r\n"
            f"Content-Disposition: form-data; name=\"fileContent\"; filename=\"{filename}\"\r\n"
            f"Content-Type: audio/ogg\r\n\r\n").encode()
    body = head + data + f"\r\n--{boundary}--\r\n".encode()
    return body, {"Content-Type": f"multipart/form-data; boundary={boundary}"}


def upload():
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
    data = open(path, "rb").read()
    url = f"https://apis.roblox.com/universes/v1/{uni}/places/{PLACE}/versions?versionType=Published"
    code, res = 0, None
    for ctype in ("application/octet-stream", "application/xml"):
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
