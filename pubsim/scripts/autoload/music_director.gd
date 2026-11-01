extends Node
## Chooses and plays background music from the 20-track soundtrack.
##
## Priorities (highest first):
##   1. an override: a mini-game theme or a celebration feature (Split the G, Pub Gets Bigger, Champions...)
##   2. live musicians performing in the pub: background music fades right out, the band is heard in 3D
##   3. the player's own jukebox choice (manual mode)
##   4. automatic selection from the situation: menu, opening, daytime, rain, busy, last orders, summary
## Songs inside one situation are allowed to finish before the next is chosen, so changing
## weather or crowd size never chops a song in half. Situation changes crossfade.

signal track_changed(id: String)

const FADE := 3.0
const SLOW_FADE := 5.0

var tracks: Dictionary = {}
var track_list: Array = []
var categories: Dictionary = {}

## Context the game updates every frame (see World._update_music_context()).
var context := {
	"screen": "menu", "phase": "prep", "hour": 15.5, "weekday": 3, "weather": "clear",
	"customers": 0, "capacity_frac": 0.0, "atmosphere": 20.0, "satisfaction": 60.0,
	"live": false, "menu_open": false, "milestone": false,
}
var mode := "auto"               # auto or manual (jukebox)
var playlist := "all"            # category filter for manual mode
var manual_id := ""
var paused := false

var current_id := ""
var situation := ""
var _players: Array[AudioStreamPlayer] = []
var _levels: Array[float] = [0.0, 0.0]
var _targets: Array[float] = [0.0, 0.0]
var _fade_speed: Array[float] = [1.0, 1.0]
var _active := 0
var _ids: Array[String] = ["", ""]
var _override := ""
var _override_kind := ""
var _override_left := -1.0
var _stinger: AudioStreamPlayer
var _stinger_left := 0.0
var _stinger_len := 0.0
var _stinger_cooldown := 0.0
var _last_ids: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _stream_cache: Dictionary = {}
var _duck := 1.0
var _speech_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/music.json"))
	if typeof(data) == TYPE_DICTIONARY:
		categories = data.get("categories", {})
		track_list = data.get("tracks", [])
		for t in track_list:
			tracks[t["id"]] = t
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = "Music"
	add_child(_stinger)
	mode = str(GameState.settings.get("music_mode", "auto"))
	playlist = str(GameState.settings.get("music_playlist", "all"))
	manual_id = str(GameState.settings.get("music_manual_id", ""))


func title_of(id: String) -> String:
	var t: Dictionary = tracks.get(id, {})
	return "%02d. %s" % [int(t.get("number", 0)), t.get("title", id)] if not t.is_empty() else ""


## Loads a track. MP3s stay compressed in memory and are decoded while playing,
## and only the tracks actually in use are kept referenced.
func stream(id: String) -> AudioStream:
	if _stream_cache.has(id):
		return _stream_cache[id]
	var t: Dictionary = tracks.get(id, {})
	if t.is_empty() or not ResourceLoader.exists(t["file"]):
		push_warning("Missing music track %s" % id)
		return null
	var s: AudioStream = load(t["file"])
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = false
	_stream_cache[id] = s
	return s


func _release_unused() -> void:
	for id in _stream_cache.keys():
		if id != current_id and id != _override and _stinger.stream != _stream_cache[id]:
			var used := false
			for p in _players:
				if p.stream == _stream_cache[id] and p.playing:
					used = true
			if not used:
				_stream_cache.erase(id)


# ------------------------------------------------------------------ public API
## Called by the voice director while a character speaks.
func duck_for_speech(seconds: float) -> void:
	_speech_left = maxf(_speech_left, seconds)


func set_screen(screen: String) -> void:
	context["screen"] = screen


## Mini-game themes and celebrations take over the music until cleared or finished.
func start_override(id: String, kind := "minigame", max_seconds := -1.0) -> void:
	_override = id
	_override_kind = kind
	var ex: Dictionary = tracks.get(id, {}).get("excerpt", {})
	if max_seconds < 0.0 and not ex.is_empty() and kind != "minigame":
		max_seconds = float(ex.get("length", 40.0))
	_override_left = max_seconds


func clear_override(id := "") -> void:
	if id == "" or id == _override:
		_override = ""
		_override_kind = ""
		_override_left = -1.0


func override_id() -> String:
	return _override


## A short excerpt over the top of the music (Perfect Pint). The background dips while it plays.
func play_stinger(id: String) -> bool:
	if _stinger_cooldown > 0.0 or _stinger_left > 0.0:
		return false
	var t: Dictionary = tracks.get(id, {})
	var s := stream(id)
	if s == null:
		return false
	var ex: Dictionary = t.get("excerpt", {"start": 0.0, "length": 8.0})
	_stinger.stream = s
	_stinger.volume_db = float(t.get("gain_db", 0.0)) - 40.0
	_stinger.play(float(ex["start"]))
	_stinger_len = float(ex["length"])
	_stinger_left = _stinger_len
	_stinger_cooldown = 75.0
	return true


func stinger_playing() -> bool:
	return _stinger_left > 0.0


func set_mode(m: String) -> void:
	mode = m
	GameState.settings["music_mode"] = m
	GameState.save_settings()
	if m == "auto":
		paused = false
		_players[_active].stream_paused = false


func set_playlist(cat: String) -> void:
	playlist = cat
	GameState.settings["music_playlist"] = cat
	GameState.save_settings()


func play_track(id: String) -> void:
	if not tracks.has(id):
		return
	mode = "manual"
	manual_id = id
	paused = false
	GameState.settings["music_mode"] = "manual"
	GameState.settings["music_manual_id"] = id
	GameState.save_settings()
	_switch_to(id, 1.2)
	situation = "manual:" + id


func toggle_pause() -> void:
	paused = not paused
	_players[_active].stream_paused = paused


func skip() -> void:
	if mode == "manual":
		var ids := playlist_ids()
		var i := ids.find(manual_id)
		play_track(ids[(i + 1) % ids.size()])
	else:
		_switch_to(_pick_for(situation, true), 1.5)


func playlist_ids() -> Array:
	var out := []
	for t in track_list:
		if playlist == "all" or t["category"] == playlist:
			out.append(t["id"])
	return out


func position() -> float:
	return _players[_active].get_playback_position() if _players[_active].playing else 0.0


func is_playing() -> bool:
	return _players[_active].playing and not paused and _targets[_active] > 0.0


# ------------------------------------------------------------------ selection
## The situation key: changing it crossfades; within one situation songs finish naturally.
func current_situation() -> String:
	if _override != "":
		return "override:" + _override
	if context["screen"] == "world" and context["live"]:
		return "live"
	if mode == "manual" and context["screen"] == "world":
		return "manual:" + manual_id
	match context["screen"]:
		"menu":
			return "menu"
		"summary":
			return "summary_ballad" if context["milestone"] else "summary"
	if context["phase"] in ["last_orders", "closing"]:
		return "closing"
	return "pub"


## Picks a track for a situation (pure apart from the random choice between equal options).
func _pick_for(sit: String, avoid_current := false) -> String:
	if sit.begins_with("override:"):
		return sit.substr(9)
	if sit.begins_with("manual:"):
		return sit.substr(7)
	match sit:
		"live":
			return ""
		"menu":
			return "t01"
		"closing", "summary":
			return "t06"
		"summary_ballad":
			return "t19"
	return _weighted(pub_pool(), avoid_current)


## Weighted candidates for ordinary trading, from time, day, weather and how busy it is.
func pub_pool() -> Dictionary:
	var h := float(context["hour"])
	var wd := int(context["weekday"])
	var rain: bool = context["weather"] in ["rain", "storm"]
	var n := int(context["customers"])
	var frac := float(context["capacity_frac"])
	var busy := n >= 8 or frac >= 0.55 or (wd in [4, 5] and h >= 18.0 and n >= 4)
	var pool := {}
	if context["phase"] == "prep" or (h < 17.0 and n <= 1):
		pool["t02"] = 3.0          # First Pint of the Day: opening up, quiet
		pool["t03"] = 1.0
		if rain:
			pool["t04"] = 1.5
		return pool
	if busy:
		pool["t05"] = 3.0          # The Friday Crowd
		pool["t03"] = 0.6
		if rain and h >= 19.0:
			pool["t04"] = 0.8
		return pool
	pool["t03"] = 3.0              # A Quiet Tuesday
	if rain:
		pool["t04"] = 3.5 if h >= 18.0 else 2.0   # Rain on the Windows, cosiest after dark
	if h < 17.5:
		pool["t02"] = 0.8
	if float(context["atmosphere"]) >= 45.0 and n >= 4:
		pool["t05"] = 1.0
	return pool


func _weighted(pool: Dictionary, avoid_current: bool) -> String:
	var opts := pool.duplicate()
	if opts.size() > 1:
		if avoid_current:
			opts.erase(current_id)
		elif _last_ids.size() >= 2 and _last_ids[-1] == _last_ids[-2] and opts.has(_last_ids[-1]):
			# never the same song three times running
			opts.erase(_last_ids[-1])
	var total := 0.0
	for k in opts.keys():
		total += float(opts[k])
	var r := _rng.randf() * total
	for k in opts.keys():
		r -= float(opts[k])
		if r <= 0.0:
			return k
	return opts.keys()[0] if not opts.is_empty() else ""


# ------------------------------------------------------------------ playback
func _switch_to(id: String, fade := FADE) -> void:
	if id == current_id and _players[_active].playing and _targets[_active] > 0.0:
		return
	var old := _active
	_targets[old] = 0.0
	_fade_speed[old] = 1.0 / maxf(fade, 0.05)
	current_id = id
	if id == "":
		track_changed.emit("")
		return
	var s := stream(id)
	if s == null:
		current_id = ""
		return
	_active = 1 - old
	var p := _players[_active]
	p.stream = s
	p.stream_paused = false
	var start := 0.0
	if _override == id and _override_kind != "minigame":
		start = float(tracks[id].get("excerpt", {}).get("start", 0.0))
	p.play(start)
	_ids[_active] = id
	_levels[_active] = 0.0
	_targets[_active] = 1.0
	_fade_speed[_active] = 1.0 / maxf(fade, 0.05)
	_last_ids.append(id)
	if _last_ids.size() > 6:
		_last_ids.pop_front()
	track_changed.emit(id)
	_release_unused()


func _process(delta: float) -> void:
	if _stinger_cooldown > 0.0:
		_stinger_cooldown -= delta
	if _override_left > 0.0:
		_override_left -= delta
		if _override_left <= 0.0:
			clear_override()
	var sit := current_situation()
	if sit != situation:
		var hard_fade := SLOW_FADE if sit in ["closing", "summary", "summary_ballad"] else FADE
		if sit == "live":
			hard_fade = 4.0
		situation = sit
		_switch_to(_pick_for(sit), hard_fade)
	else:
		var p := _players[_active]
		if current_id != "" and not paused:
			var len := p.stream.get_length() if p.stream else 0.0
			var near_end := len > 0.0 and p.playing and p.get_playback_position() > len - FADE
			if near_end or not p.playing:
				_on_track_finished()
	# fades and ducking
	var duck_target := 1.0
	if _stinger_left > 0.0:
		_stinger_left -= delta
		duck_target = 0.25
		var t := _stinger_len - _stinger_left
		var sl := minf(1.0, t / 0.4) * minf(1.0, _stinger_left / 1.8)
		_stinger.volume_db = float(tracks.get("t14", {}).get("gain_db", 0.0)) + linear_to_db(maxf(sl, 0.0001))
		if _stinger_left <= 0.0:
			_stinger.stop()
	if context["menu_open"]:
		duck_target = minf(duck_target, 0.55)
	if _speech_left > 0.0:
		# dip the music a little under spoken lines so they stay clear
		_speech_left -= delta
		duck_target = minf(duck_target, 0.45)
	_duck = move_toward(_duck, duck_target, delta * (3.0 if duck_target < _duck else 1.2))
	for i in 2:
		_levels[i] = move_toward(_levels[i], _targets[i], delta * _fade_speed[i])
		var p2 := _players[i]
		if _levels[i] <= 0.001 and _targets[i] == 0.0:
			if p2.playing:
				p2.stop()
			continue
		var gain := float(tracks.get(_ids[i], {}).get("gain_db", 0.0))
		# equal-power curve so crossfades don't dip
		var lvl := sin(_levels[i] * PI * 0.5)
		p2.volume_db = gain + linear_to_db(maxf(lvl * _duck, 0.0001))


func _on_track_finished() -> void:
	if situation.begins_with("override:"):
		# celebration or theme ran out: back to the pub
		clear_override()
		return
	if situation.begins_with("manual:"):
		var ids := playlist_ids()
		if ids.is_empty():
			return
		var i := ids.find(manual_id)
		play_track(ids[(i + 1) % ids.size()])
		return
	if situation in ["closing", "summary", "summary_ballad", "menu"]:
		# these themes simply start again
		var id := current_id
		current_id = ""
		_switch_to(id, FADE)
		return
	_switch_to(_pick_for(situation, true), FADE)


## Number of background players audible right now (tests use this to prove songs never stack).
func audible_players() -> int:
	var n := 0
	for i in 2:
		if _players[i].playing and _levels[i] > 0.9:
			n += 1
	return n
