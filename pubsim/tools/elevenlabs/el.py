#!/usr/bin/env python3
"""ElevenLabs asset pipeline for The Irish Pub Simulator (runs in GitHub Actions only).

The API key is read from $ELEVENLABS_API_KEY and is never written anywhere.
Modes (from request.json "phase"):
  check   - read-only: subscription/credit balance, tier, models, Irish voices. Costs nothing.
  sample  - generate only the lines/effects marked "sample": true (small representative set).
  full    - generate everything in voice_lines.json / sfx.json that isn't generated yet.
  batch   - re-record the lines with the given tags, one take per character, cut by timestamps.
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
    lines = load_json(os.path.join(ROOT, "data", "voice_lines.json"), {"cast": {}, "lines": []})
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


# ------------------------------------------------------------------ batch (re-)recording
# eleven_v3 is uneven on very short prompts, which made one-line clips sound flat and synthetic.
# A "batch" run records all of a character's chosen lines in one take (a short monologue, so the
# model has context), then cuts the take into lines using the character timestamps the API returns.
# A cut only replaces the existing clip when speech-to-text confirms the words.

def decode_wav(path, rate=44100):
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(rate), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def write_ogg(samples, rate, dst, quality=5):
    """Trims edge silence, sets an even loudness with plain gain (no compression), encodes Vorbis."""
    import numpy as np
    x = samples.astype(np.float32)
    env = np.abs(x)
    thr = 10 ** (-45 / 20)
    idx = np.nonzero(env > thr)[0]
    if idx.size:
        a = max(0, idx[0] - int(0.03 * rate))
        b = min(len(x), idx[-1] + int(0.12 * rate))
        x = x[a:b]
    # loudness: RMS over the voiced part to about -19 dBFS, peaks kept under -1.5 dBFS
    voiced = x[np.abs(x) > thr * 10]
    rms = float(np.sqrt(np.mean(voiced ** 2))) if voiced.size else 0.05
    gain = min(10 ** (-19 / 20) / max(rms, 1e-4), 10 ** (-1.5 / 20) / max(float(np.max(np.abs(x))), 1e-4))
    x = x * gain
    fade = min(len(x) // 4, int(0.012 * rate))
    if fade > 0:
        x[:fade] *= np.linspace(0, 1, fade)
        x[-fade:] *= np.linspace(1, 0, fade)
    p = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "f32le", "-ar", str(rate), "-ac", "1", "-i", "-",
                        "-c:a", "libvorbis", "-q:a", str(quality), dst], input=x.astype(np.float32).tobytes(), check=True)
    return p


def cut_by_alignment(alignment, script, spans):
    """Times (start, end) per line from character timestamps. `spans` are (start, end) indices of each
    line in `script`. The aligned characters may differ slightly from the script (tags, normalising),
    so lines are found again in the aligned text."""
    chars = alignment.get("characters") or []
    st = alignment.get("character_start_times_seconds") or []
    en = alignment.get("character_end_times_seconds") or []
    if not chars or len(chars) != len(st) or len(st) != len(en):
        return None
    text = "".join(chars)
    out = []
    pos = 0
    for a, b in spans:
        line = script[a:b]
        i = text.find(line, pos)
        if i < 0:
            # fall back to the first and last few words of the line
            head, tail = line[:12], line[-10:]
            i = text.find(head, pos)
            j = text.find(tail, max(i, 0))
            if i < 0 or j < 0:
                return None
            k = j + len(tail) - 1
        else:
            k = i + len(line) - 1
        out.append((float(st[i]), float(en[k])))
        pos = k + 1
    return out


def cut_by_silence(x, rate, n):
    """Splits a take into n lines at the n-1 longest pauses (used if timestamps are unavailable)."""
    import numpy as np
    hop = int(0.01 * rate)
    frames = len(x) // hop
    rms = np.array([np.sqrt(np.mean(x[i * hop:(i + 1) * hop] ** 2)) for i in range(frames)])
    quiet = rms < max(10 ** (-40 / 20), float(np.percentile(rms, 95)) * 0.02)
    runs = []
    i = 0
    while i < frames:
        if quiet[i]:
            j = i
            while j < frames and quiet[j]:
                j += 1
            if i > 0 and j < frames:
                runs.append((j - i, i, j))
            i = j
        else:
            i += 1
    if len(runs) < n - 1:
        return None
    cuts = sorted(sorted(runs, reverse=True)[:n - 1], key=lambda r: r[1])
    bounds = [0.0] + [((r[1] + r[2]) / 2) * hop / rate for r in cuts] + [len(x) / rate]
    return [(bounds[k], bounds[k + 1]) for k in range(n)]


def transcribe(path):
    body, boundary = multipart({"model_id": "scribe_v1", "language_code": "en"}, "file", path)
    r = urllib.request.Request(API + "/v1/speech-to-text", data=body, method="POST")
    r.add_header("xi-api-key", KEY)
    r.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    with urllib.request.urlopen(r, timeout=120) as resp:
        return json.loads(resp.read()).get("text", "")


def batch(reqf):
    import base64
    lines = load_json(os.path.join(ROOT, "data", "voice_lines.json"), {"cast": {}, "lines": []})
    manifest = load_json(MANIFEST, {"clips": {}, "credits_spent": 0})
    tags = reqf.get("tags", [])
    reserve = float(reqf.get("reserve", 1500))
    _, used0, limit = subscription()
    remaining = limit - used0
    cap = min(float(reqf.get("max_credits", 0)), remaining - reserve)
    log(f"Credits before: used {used0} / {limit} (remaining {remaining}); keeping {reserve:.0f} in reserve, so this run may spend at most {cap:.0f}")
    if cap <= 0:
        log("Nothing to do within the reserve.")
        return
    model = reqf.get("model", lines.get("model", "eleven_v3"))
    rate = 44100
    groups = {}
    for ln in lines["lines"]:
        if ln["tag"] in tags and (not reqf.get("voices") or ln["voice"] in reqf["voices"]):
            groups.setdefault(ln["voice"], []).append(ln)
    order = sorted(groups, key=lambda v: min(tags.index(l["tag"]) for l in groups[v]))
    spent = 0.0
    replaced = []
    tmpdir = os.path.join(HERE, "tmp_batch")
    os.makedirs(tmpdir, exist_ok=True)
    for vkey in order:
        cast = lines["cast"][vkey]
        group = sorted(groups[vkey], key=lambda l: tags.index(l["tag"]))
        settings = cast.get("settings", {"stability": 0.5, "similarity_boost": 0.75})
        script = " ".join(t for t in [cast.get("batch_accent", cast.get("accent_tag", "")), cast.get("batch_direction", "")] if t)
        spans = []
        for ln in group:
            script += ("\n\n" if spans else (" " if script else ""))
            a = len(script)
            script += ln["text"]
            spans.append((a, len(script)))
        if spent + len(script) > cap:
            log(f"STOP before {vkey}: {len(script)} more credits would pass this run's cap")
            break
        log(f"{vkey}: {len(group)} lines in one take ({len(script)} characters)")
        body = {"text": script, "model_id": model, "voice_settings": settings}
        times = None
        try:
            payload, hdr = req("POST", f"/v1/text-to-speech/{cast['voice_id']}/with-timestamps", body, raw=True,
                               params={"output_format": "mp3_44100_128"})
            data = json.loads(payload)
            audio = base64.b64decode(data["audio_base64"])
            times = cut_by_alignment(data.get("alignment") or {}, script, spans) or \
                cut_by_alignment(data.get("normalized_alignment") or {}, script, spans)
        except RuntimeError as e:
            log("  timestamps unavailable, recording without:", str(e)[:200])
            if "quota" in str(e).lower() or "401" in str(e):
                break
            try:
                audio, hdr = req("POST", f"/v1/text-to-speech/{cast['voice_id']}", body, raw=True,
                                 params={"output_format": "mp3_44100_128"})
            except RuntimeError as e2:
                log("  ERROR", str(e2)[:200])
                continue
        cost = hdr.get("character-cost") or hdr.get("Character-Cost")
        cost = float(cost) if cost else float(len(script))
        spent += cost
        manifest["credits_spent"] = manifest.get("credits_spent", 0) + cost
        log(f"  {cost:.0f} credits")
        take = os.path.join(tmpdir, vkey + ".mp3")
        with open(take, "wb") as f:
            f.write(audio)
        x = decode_wav(take, rate)
        if times is None:
            log("  cutting at pauses")
            times = cut_by_silence(x, rate, len(group))
        if times is None:
            log("  could not cut this take; existing clips kept")
            continue
        for i, ln in enumerate(group):
            a, b = times[i]
            # pad, without running into the neighbouring lines
            lo = a - 0.08 if i == 0 else max(a - 0.08, (times[i - 1][1] + a) / 2)
            hi = b + 0.25 if i == len(group) - 1 else min(b + 0.25, (b + times[i + 1][0]) / 2)
            seg = x[max(0, int(lo * rate)):min(len(x), int(hi * rate))]
            if len(seg) < int(0.3 * rate):
                log(f"  {ln['id']}: cut too short, kept the old clip")
                continue
            cand = os.path.join(tmpdir, ln["id"] + ".ogg")
            write_ogg(seg, rate, cand)
            try:
                heard = transcribe(cand)
            except Exception as e:
                log(f"  {ln['id']}: could not check ({str(e)[:100]}), kept the old clip")
                continue
            sim = similarity(ln["text"], heard)
            if sim < 0.75:
                log(f"  CHECK {ln['id']} match {sim:.2f}: \"{heard}\" - kept the old clip")
                continue
            dst = os.path.join(OUT_VOICE, ln["id"] + ".ogg")
            os.replace(cand, dst)
            k = clip_key("tts-batch", cast_identity(cast), model, script, settings, ln["id"])
            for vv in manifest["clips"].values():
                if vv.get("id") == ln["id"] and vv.get("take") != "batch":
                    vv["superseded_by"] = k   # kept so a "full" run never records the line again
            manifest["clips"][k] = {"id": ln["id"], "kind": "tts", "file": os.path.relpath(dst, ROOT),
                                    "credits": round(cost * (spans[i][1] - spans[i][0]) / len(script), 1),
                                    "text": ln["text"], "voice": vkey, "take": "batch", "transcript": heard, "match": round(sim, 2)}
            replaced.append(ln["id"])
            log(f"  OK {ln['id']} match {sim:.2f}: \"{heard}\"")
        save_manifest(manifest)
        time.sleep(0.3)
    for f in os.listdir(tmpdir):
        os.remove(os.path.join(tmpdir, f))
    os.rmdir(tmpdir)
    _, used1, limit = subscription()
    log(f"Replaced {len(replaced)} clips. Credits after: used {used1} / {limit} (remaining {limit - used1}). This run used {used1 - used0}.")
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
    elif phase == "batch":
        batch(reqf)
    else:
        generate(phase, float(reqf.get("max_credits", 0)), bool(reqf.get("all_sfx", False)))


if __name__ == "__main__":
    main()
