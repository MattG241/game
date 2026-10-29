class_name VoiceDirector
extends Node
## Spoken lines for customers, regulars, the musicians and the landlord.
##
## The recordings are bundled offline (assets/voice, made once with ElevenLabs by
## tools/elevenlabs/el.py); nothing is fetched at runtime. The script of every line, with the
## character ("voice") and situation ("tag") it belongs to, is data/voice_lines.json. A line only
## plays if its recording exists, so the game works with any subset of them; otherwise the
## speech bubble alone is shown, as before.
##
## Rules that keep a busy pub from turning into a wall of noise: at most MAX_VOICES at once,
## a short gap between any two lines, a per-speaker and per-situation cooldown, no repeats of
## the last few lines, and distant speakers are skipped. Music dips slightly under speech.

const MAX_VOICES := 2
const GLOBAL_GAP := 1.4
const SPEAKER_COOLDOWN := 9.0
const TAG_COOLDOWN := {"chatter": 25.0, "wait": 20.0, "cheer": 6.0, "crowd": 30.0}
const HEAR_DISTANCE := 13.0
const FEMALE_VOICES := ["cheerful_local", "jordan", "colleen"]
const MALE_VOICES := ["dubliner", "cillian", "andrew", "old_regular"]

var world: Node
var lines := {}          # voice -> tag -> Array of {id, text, path}
var cast := {}
var _recent: Array[String] = []
var _speaker_t := {}     # instance id -> time of their last line
var _tag_t := {}
var _gap := 0.0
var _clock := 0.0
var _active: Array[Node] = []
var played: Array[String] = []   # ids of lines played (for tests and the debug overlay)
var last_text := ""


func _ready() -> void:
	load_lines()


func load_lines() -> void:
	lines.clear()
	var f := FileAccess.open("res://data/voice_lines.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return
	cast = d.get("cast", {})
	for ln in d.get("lines", []):
		var path := "res://assets/voice/%s.ogg" % ln["id"]
		if not ResourceLoader.exists(path):
			continue
		var v := str(ln["voice"])
		var t := str(ln["tag"])
		if not lines.has(v):
			lines[v] = {}
		if not lines[v].has(t):
			lines[v][t] = []
		lines[v][t].append({"id": ln["id"], "text": ln["text"], "path": path, "drink": str(ln.get("drink", ""))})


func recorded_count() -> int:
	var n := 0
	for v in lines:
		for t in lines[v]:
			n += lines[v][t].size()
	return n


func has_line(voice: String, tag: String, drink := "") -> bool:
	return lines.has(voice) and lines[voice].has(tag) and not _options(voice, tag, drink).is_empty()


## Order lines name a drink, so only lines for the drink actually ordered (or "any") qualify.
func _options(voice: String, tag: String, drink: String) -> Array:
	var opts: Array = lines[voice][tag]
	if drink == "":
		return opts
	return opts.filter(func(o): return o["drink"] == "" or o["drink"] == drink or o["drink"] == "any")


## The voice a customer speaks with: regulars have their own, others are matched to how they look.
static func voice_for(regular_voice: String, gender: String, visitor: String, seed_v: int) -> String:
	if regular_voice != "":
		return regular_voice
	if visitor == "tourist":
		return "tourist_uk" if gender == "f" else "tourist_us"
	var pool: Array = FEMALE_VOICES if gender == "f" else MALE_VOICES
	return pool[absi(seed_v) % pool.size()]


func _process(delta: float) -> void:
	_clock += delta
	_gap = maxf(0.0, _gap - delta)
	_active = _active.filter(func(p): return is_instance_valid(p))


func _can_start(speaker: Node, tag: String, important: bool) -> bool:
	if not bool(GameState.settings.get("voices", true)):
		return false
	_active = _active.filter(func(p): return is_instance_valid(p))
	if _active.size() >= MAX_VOICES:
		if not important:
			return false
		# what you're dealing with (an order, an announcement) wins over background chatter
		var oldest: Variant = _active.pop_front()
		if is_instance_valid(oldest):
			(oldest as Node).queue_free()
	if _gap > 0.0 and not important:
		return false
	if speaker:
		var last := float(_speaker_t.get(speaker.get_instance_id(), -100.0))
		if _clock - last < SPEAKER_COOLDOWN and not important:
			return false
	if TAG_COOLDOWN.has(tag) and _clock - float(_tag_t.get(tag, -100.0)) < float(TAG_COOLDOWN[tag]):
		return false
	return true


func _pick(voice: String, tag: String, drink := "") -> Dictionary:
	var opts: Array = _options(voice, tag, drink)
	var fresh := opts.filter(func(o): return not _recent.has(o["id"]))
	if fresh.is_empty():
		fresh = opts
	return fresh[randi() % fresh.size()]


## A character says a line for a situation. Returns the spoken text ("" if nothing played), so
## callers can show the matching subtitle.
func speak(speaker: Node3D, voice: String, tag: String, important := false, drink := "") -> String:
	if not has_line(voice, tag, drink):
		return ""
	if speaker and world and world.player and speaker.global_position.distance_to(world.player.global_position) > HEAR_DISTANCE:
		return ""
	if not _can_start(speaker, tag, important):
		return ""
	var ln := _pick(voice, tag, drink)
	var stream: AudioStream = load(ln["path"])
	if stream == null:
		return ""
	var p: Node
	if speaker:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.bus = "Speech"
		p3.unit_size = 3.5
		p3.max_distance = 22.0
		p3.volume_db = 2.0
		p3.attenuation_filter_cutoff_hz = 9000.0
		speaker.add_child(p3)
		p3.position = Vector3(0, 1.6, 0)
		p3.finished.connect(p3.queue_free)
		p3.play()
		p = p3
		if speaker.has_method("talk_for"):
			speaker.talk_for(stream.get_length())
		_speaker_t[speaker.get_instance_id()] = _clock
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = stream
		p2.bus = "Speech"
		add_child(p2)
		p2.finished.connect(p2.queue_free)
		p2.play()
		p = p2
	_active.append(p)
	_gap = GLOBAL_GAP
	_tag_t[tag] = _clock
	_recent.append(ln["id"])
	if _recent.size() > 12:
		_recent.pop_front()
	played.append(ln["id"])
	last_text = str(ln["text"])
	MusicDirector.duck_for_speech(stream.get_length() + 0.3)
	return str(ln["text"])


## Someone in the room reacts (Split the G, a song ending...). Picks a nearby customer whose
## voice has a line for it; falls back to any recorded voice, heard from the room.
func crowd(tag: String) -> String:
	var best: Node3D = null
	var best_d := 1e9
	if world:
		for c in world.customers:
			if not is_instance_valid(c) or c.state in ["enter", "leave", "walk"]:
				continue
			if not has_line(c.voice, tag):
				continue
			var d: float = c.global_position.distance_to(world.player.global_position)
			if d < best_d:
				best_d = d
				best = c
	if best:
		var said := speak(best, best.voice, tag, true)
		if said != "":
			best.say(said, 3.0)
		return said
	for v in lines:
		if lines[v].has(tag):
			return speak(null, v, tag, true)
	return ""
