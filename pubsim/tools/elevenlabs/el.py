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


PREVIEW_TEXT = ("Ah, you're very welcome in. Pull up a stool there by the fire and I'll have a pint of Galagers "
                "poured for you in a minute. Mind, it takes its time, a good pint does, but it's worth the wait.")


def cast_identity(cast_entry):
    """What a clip's voice is keyed on: the premade voice id, or the design description."""
    if cast_entry.get("design"):
        return "design:" + cast_entry["design"]["description"]
    return cast_entry["voice_id"]


def design_voice(cast_key, cast_entry):
    """Voice Design: describe the voice, take the first preview and save it to the account.
    Free accounts may use their own designed voices over the API (but not library voices)."""
    desc = cast_entry["design"]["description"]
    body = {"voice_description": desc, "text": PREVIEW_TEXT, "model_id": "eleven_ttv_v3", "seed": 1887}
    try:
        r = req("POST", "/v1/text-to-voice/design", body)
    except RuntimeError as e:
        log("  ttv v3 design unavailable, trying v2:", str(e)[:200])
        body["model_id"] = "eleven_multilingual_ttv_v2"
        r = req("POST", "/v1/text-to-voice/design", body)
    previews = r.get("previews", [])
    if not previews:
        raise RuntimeError("voice design returned no previews")
    gid = previews[0]["generated_voice_id"]
    v = req("POST", "/v1/text-to-voice", {"voice_name": "PubSim " + cast_entry["name"], "voice_description": desc,
                                          "generated_voice_id": gid})
    log(f"  designed voice for {cast_key} ({body['model_id']}): {len(previews)} previews, kept the first")
    return v["voice_id"]


def ensure_voice(cast_key, cast_entry, manifest):
    """Returns a usable voice id: premade voices directly, designed voices created on first use."""
    if not cast_entry.get("design"):
        return cast_entry["voice_id"]
    designed = manifest.setdefault("designed_voices", {})
    ident = cast_identity(cast_entry)
    if cast_key in designed and designed[cast_key]["identity"] == ident:
        return designed[cast_key]["voice_id"]
    _, before, _ = subscription()
    vid = design_voice(cast_key, cast_entry)
    _, after, _ = subscription()
    log(f"  voice design cost: {after - before} credits")
    manifest["design_credits"] = manifest.get("design_credits", 0) + (after - before)
    designed[cast_key] = {"voice_id": vid, "identity": ident}
    save_manifest(manifest)
    return vid


def release_voice(cast_key, cast_entry, manifest):
    """Deletes a designed voice once all of its lines exist, freeing the slot (the free plan has three)."""
    designed = manifest.get("designed_voices", {})
    if cast_key not in designed:
        return
    try:
        req("DELETE", f"/v1/voices/{designed[cast_key]['voice_id']}")
        log(f"  released voice slot: {cast_entry['name']}")
    except RuntimeError as e:
        log("  could not release voice", cast_entry["name"], e)
    del designed[cast_key]
    save_manifest(manifest)


def multipart(fields, file_field, file_path):
    boundary = "----pubsim" + hashlib.md5(file_path.encode()).hexdigest()
    out = b""
    for k, v in fields.items():
        out += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode()
    with open(file_path, "rb") as f:
        data = f.read()
    out += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{file_field}\"; filename=\"clip.ogg\"\r\nContent-Type: audio/ogg\r\n\r\n".encode() + data + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return out, boundary


def words(t):
    import re
    return re.findall(r"[a-z']+", t.lower())


def similarity(a, b):
    import difflib
    return difflib.SequenceMatcher(None, words(a), words(b)).ratio()


def verify(generated, manifest):
    """Transcribes new voice clips and compares them with the script (a pronunciation check)."""
    for kind, item, dst, k in generated:
        if kind != "tts":
            continue
        try:
            body, boundary = multipart({"model_id": "scribe_v1", "language_code": "en"}, "file", dst)
            r = urllib.request.Request(API + "/v1/speech-to-text", data=body, method="POST")
            r.add_header("xi-api-key", KEY)
            r.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
            with urllib.request.urlopen(r, timeout=120) as resp:
                text = json.loads(resp.read()).get("text", "")
        except Exception as e:
            log(f"  verify {item['id']}: transcription unavailable ({str(e)[:120]})")
            continue
        sim = similarity(item["text"], text)
        manifest["clips"][k]["transcript"] = text
        manifest["clips"][k]["match"] = round(sim, 2)
        flag = "OK " if sim >= 0.8 else "CHECK"
        log(f"  {flag} {item['id']} match {sim:.2f}: \"{text}\"")
    save_manifest(manifest)


def spoken(cast, text):
    """eleven_v3 takes audio tags; free plans only get premade voices (none are Irish), so the
    accent is asked for with a tag such as [Irish accent]."""
    tag = cast.get("accent_tag", "")
    return f"{tag} {text}" if tag else text


def premade_ok(voice_id, cache):
    """Free check that a voice exists and is usable before paying for any line."""
    if voice_id not in cache:
        try:
            v = req("GET", f"/v1/voices/{voice_id}")
            cache[voice_id] = True
            log(f"  voice {voice_id}: {v.get('name')} ({v.get('category')}) {v.get('labels', {})}")
        except RuntimeError as e:
            cache[voice_id] = False
            log(f"  voice {voice_id} unavailable: {str(e)[:160]}")
    return cache[voice_id]


def generate(phase, cap, all_sfx=False):
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
    all_tts = {}   # every line per voice (any phase), to know when a designed voice is finished with
    for ln in lines["lines"]:
        cast = lines["cast"][ln["voice"]]
        if phase == "sample" and not ln.get("sample"):
            k = clip_key("tts", cast_identity(cast), lines.get("model", "eleven_multilingual_v2"), spoken(cast, ln["text"]),
                         cast.get("settings", {"stability": 0.45, "similarity_boost": 0.8, "style": 0.35, "use_speaker_boost": True}))
            all_tts.setdefault(ln["voice"], []).append(k)
            continue
        settings = cast.get("settings", {"stability": 0.45, "similarity_boost": 0.8, "style": 0.35, "use_speaker_boost": True})
        k = clip_key("tts", cast_identity(cast), model, spoken(cast, ln["text"]), settings)
        work.append(("tts", k, ln, cast, settings))
        all_tts.setdefault(ln["voice"], []).append(k)
    for fx in sfx:
        if phase == "sample" and not fx.get("sample") and not all_sfx:
            continue
        k = clip_key("sfx", fx["prompt"], fx.get("duration"), fx.get("influence", 0.45))
        work.append(("sfx", k, fx, None, None))
    todo = [w for w in work if w[1] not in manifest["clips"]]
    designed_now = manifest.get("designed_voices", {})
    todo.sort(key=lambda w: (w[0], 0 if w[0] == "tts" and w[2]["voice"] in designed_now else 1, w[2].get("voice", "")))

    def finished(vkey):
        return all(k in manifest["clips"] for k in all_tts.get(vkey, []))
    log(f"{len(work)} clips in scope, {len(todo)} still to generate")
    current_voice = None
    voice_cache = {}
    failed_voices = set()
    generated = []
    for kind, k, item, cast, settings in todo:
        if kind == "tts" and item["voice"] in failed_voices:
            continue
        if kind == "tts" and not cast.get("design") and not premade_ok(cast["voice_id"], voice_cache):
            failed_voices.add(item["voice"])
            continue
        if kind == "tts" and current_voice and current_voice != item["voice"]:
            if finished(current_voice):
                release_voice(current_voice, lines["cast"][current_voice], manifest)
            current_voice = None
        if kind == "tts" and cast.get("design") and item["voice"] not in manifest.get("designed_voices", {}) \
                and len(manifest.get("designed_voices", {})) >= int(lines.get("voice_slots", 3)):
            log(f"SKIP {item['id']}: all voice slots hold voices with unfinished lines")
            continue
        # measured: sound effects ~10 credits per second; v3 speech 1 credit per character; a design ~ preview text
        est = len(spoken(cast, item["text"]) if kind == "tts" else "") * (1.0 if "multilingual" in model or "v3" in model else 0.5) if kind == "tts" else 12 * float(item.get("duration", 3.0)) + 5
        if kind == "tts" and cast.get("design") and item["voice"] not in manifest.get("designed_voices", {}):
            est += len(PREVIEW_TEXT) * 1.5
        if spent_run + est > cap:
            log(f"STOP: next clip ({item['id']}, ~{est:.0f} credits) would exceed this run's cap")
            break
        tmp = os.path.join(HERE, "tmp.mp3")
        try:
            if kind == "tts":
                vid = ensure_voice(item["voice"], cast, manifest)
                current_voice = item["voice"]
                audio, hdr = req("POST", f"/v1/text-to-speech/{vid}", {"text": spoken(cast, item["text"]), "model_id": model, "voice_settings": settings},
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
            if kind == "tts":
                failed_voices.add(item["voice"])   # don't retry the same failing voice line after line
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
        generated.append((kind, item, dst, k))
        time.sleep(0.3)
    # free the slots of designed voices whose lines are all done (sample runs keep theirs for the full run)
    for vkey in list(manifest.get("designed_voices", {})):
        if finished(vkey):
            release_voice(vkey, lines["cast"][vkey], manifest)
    verify(generated, manifest)
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
        generate(phase, float(reqf.get("max_credits", 0)), bool(reqf.get("all_sfx", False)))


if __name__ == "__main__":
    main()
