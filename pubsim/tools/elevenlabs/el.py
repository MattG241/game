#!/usr/bin/env python3
"""ElevenLabs asset pipeline for The Irish Pub Simulator (runs in GitHub Actions only).

The API key is read from $ELEVENLABS_API_KEY and is never written anywhere.
Modes (from request.json "phase"):
  check   - read-only: subscription/credit balance, tier, models, Irish voices. Costs nothing.
  sample  - generate only the lines/effects marked "sample": true (small representative set).
  full    - generate everything in voice_lines.json / sfx.json that isn't generated yet.
Generation is idempotent: every clip is keyed by a hash of (voice, model, text/prompt, settings)
and skipped if already present in manifest.json, so re-runs never pay twice.
A hard credit cap (request.json "max_credits") is enforced from the live balance before each call.
"""
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.elevenlabs.io"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_VOICE = os.path.join(ROOT, "assets", "voice")
OUT_SFX = os.path.join(ROOT, "assets", "sfx_el")
MANIFEST = os.path.join(HERE, "manifest.json")
KEY = os.environ.get("ELEVENLABS_API_KEY", "")


def log(*a):
    print(*a, flush=True)


def req(method, path, body=None, raw=False, params=None):
    url = API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("xi-api-key", KEY)
    if data is not None:
        r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=180) as resp:
            payload = resp.read()
            return (payload, dict(resp.headers)) if raw else json.loads(payload or b"{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:600]
        raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {detail}")


def subscription():
    s = req("GET", "/v1/user/subscription")
    used = int(s.get("character_count", 0))
    limit = int(s.get("character_limit", 0))
    return s, used, limit


def load_json(p, default):
    if os.path.exists(p):
        with open(p) as f:
            return json.load(f)
    return default


def save_manifest(m):
    with open(MANIFEST, "w") as f:
        json.dump(m, f, indent=1, ensure_ascii=False, sort_keys=True)


def check():
    s, used, limit = subscription()
    log("== Subscription ==")
    for k in ["tier", "status", "character_count", "character_limit", "can_extend_character_limit",
              "next_character_count_reset_unix", "voice_limit", "voice_slots_used", "can_use_instant_voice_cloning"]:
        if k in s:
            log(f"  {k}: {s[k]}")
    log(f"  remaining credits: {limit - used}")
    log("== Models ==")
    try:
        for m in req("GET", "/v1/models"):
            if m.get("can_do_text_to_speech"):
                extra = {k: m[k] for k in m if "cost" in k or "rate" in k}
                log(f"  {m['model_id']}: {m.get('name')} {extra}")
    except Exception as e:
        log("  models error:", e)
    log("== Shared Irish voices ==")
    try:
        r = req("GET", "/v1/shared-voices", params={"page_size": 100, "accent": "irish", "language": "en"})
        for v in r.get("voices", [])[:60]:
            log("  {voice_id} | {name} | {gender} | {age} | {accent} | {descriptive} | {use_case} | owner {public_owner_id} | free:{free_users_allowed}".format(
                **{k: v.get(k, "") for k in ["voice_id", "name", "gender", "age", "accent", "descriptive", "use_case", "public_owner_id", "free_users_allowed"]}))
    except Exception as e:
        log("  shared voices error:", e)
    log("== My voices ==")
    try:
        for v in req("GET", "/v1/voices").get("voices", []):
            log(f"  {v['voice_id']} | {v['name']} | {v.get('category')} | {v.get('labels')}")
    except Exception as e:
        log("  voices error:", e)


def clip_key(*parts):
    return hashlib.sha256(json.dumps(parts, sort_keys=True).encode()).hexdigest()[:16]


def to_ogg(src_mp3, dst_ogg, mono=True, rate=32000, quality=4):
    args = ["ffmpeg", "-y", "-loglevel", "error", "-i", src_mp3]
    if mono:
        args += ["-ac", "1"]
    # trim leading/trailing silence and normalise loudness so clips sit evenly in the mix
    args += ["-af", "silenceremove=start_periods=1:start_threshold=-50dB,areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse,loudnorm=I=-18:TP=-2:LRA=11",
             "-ar", str(rate), "-c:a", "libvorbis", "-q:a", str(quality), dst_ogg]
    subprocess.run(args, check=True)


def ensure_voice(cast_entry, manifest):
    """Adds a shared library voice to the account (free) and returns the usable voice id."""
    vid = cast_entry["voice_id"]
    owner = cast_entry.get("public_owner_id", "")
    added = manifest.setdefault("added_voices", {})
    if not owner:
        return vid
    if vid in added:
        return added[vid]
    r = req("POST", f"/v1/voices/add/{owner}/{vid}", {"new_name": "PubSim " + cast_entry["name"]})
    added[vid] = r.get("voice_id", vid)
    save_manifest(manifest)
    return added[vid]


def generate(phase, cap):
    lines = load_json(os.path.join(HERE, "voice_lines.json"), {"cast": {}, "lines": []})
    sfx = load_json(os.path.join(HERE, "sfx.json"), [])
    manifest = load_json(MANIFEST, {"clips": {}, "credits_spent": 0})
    _, used0, limit = subscription()
    log(f"Credits before: used {used0} / {limit} (remaining {limit - used0}); this run may spend at most {cap}")
    spent_run = 0
    os.makedirs(OUT_VOICE, exist_ok=True)
    os.makedirs(OUT_SFX, exist_ok=True)
    model = lines.get("model", "eleven_multilingual_v2")
    work = []
    for ln in lines["lines"]:
        if phase == "sample" and not ln.get("sample"):
            continue
        cast = lines["cast"][ln["voice"]]
        settings = cast.get("settings", {"stability": 0.45, "similarity_boost": 0.8, "style": 0.35, "use_speaker_boost": True})
        k = clip_key("tts", cast["voice_id"], model, ln["text"], settings)
        work.append(("tts", k, ln, cast, settings))
    for fx in sfx:
        if phase == "sample" and not fx.get("sample"):
            continue
        k = clip_key("sfx", fx["prompt"], fx.get("duration"), fx.get("influence", 0.45))
        work.append(("sfx", k, fx, None, None))
    todo = [w for w in work if w[1] not in manifest["clips"]]
    log(f"{len(work)} clips in scope, {len(todo)} still to generate")
    for kind, k, item, cast, settings in todo:
        est = len(item["text"]) * (1.0 if "multilingual" in model or "v3" in model else 0.5) if kind == "tts" else 40 * float(item.get("duration", 3.0)) + 20
        if spent_run + est > cap:
            log(f"STOP: next clip ({item['id']}, ~{est:.0f} credits) would exceed this run's cap")
            break
        tmp = os.path.join(HERE, "tmp.mp3")
        try:
            if kind == "tts":
                vid = ensure_voice(cast, manifest)
                audio, hdr = req("POST", f"/v1/text-to-speech/{vid}", {"text": item["text"], "model_id": model, "voice_settings": settings},
                                 raw=True, params={"output_format": "mp3_44100_128"})
                dst = os.path.join(OUT_VOICE, item["id"] + ".ogg")
            else:
                body = {"text": item["prompt"], "prompt_influence": item.get("influence", 0.45)}
                if item.get("duration"):
                    body["duration_seconds"] = float(item["duration"])
                audio, hdr = req("POST", "/v1/sound-generation", body, raw=True)
                dst = os.path.join(OUT_SFX, item["id"] + ".ogg")
        except RuntimeError as e:
            log("ERROR", item["id"], e)
            if "quota" in str(e).lower() or "401" in str(e):
                break
            continue
        with open(tmp, "wb") as f:
            f.write(audio)
        to_ogg(tmp, dst, mono=True, rate=32000 if kind == "tts" else 44100, quality=4 if kind == "tts" else 5)
        os.remove(tmp)
        cost = hdr.get("character-cost") or hdr.get("Character-Cost") or hdr.get("x-character-count")
        cost = float(cost) if cost else est
        spent_run += cost
        manifest["clips"][k] = {"id": item["id"], "kind": kind, "file": os.path.relpath(dst, ROOT), "credits": cost,
                                "text": item.get("text", item.get("prompt")), "voice": item.get("voice", "")}
        manifest["credits_spent"] = manifest.get("credits_spent", 0) + cost
        save_manifest(manifest)
        log(f"  {kind} {item['id']}: {cost:.0f} credits")
        time.sleep(0.3)
    _, used1, limit = subscription()
    log(f"Credits after: used {used1} / {limit} (remaining {limit - used1}). This run actually used {used1 - used0}.")
    manifest["last_balance"] = {"used": used1, "limit": limit, "remaining": limit - used1, "run_used": used1 - used0}
    save_manifest(manifest)


def main():
    if not KEY:
        log("::error::ELEVENLABS_API_KEY secret is not set for this repository. Add it under Settings > Secrets and variables > Actions.")
        sys.exit(2)
    reqf = load_json(os.path.join(HERE, "request.json"), {"phase": "check"})
    phase = reqf.get("phase", "check")
    log("Phase:", phase)
    if phase == "check":
        check()
    else:
        generate(phase, float(reqf.get("max_credits", 0)))


if __name__ == "__main__":
    main()
