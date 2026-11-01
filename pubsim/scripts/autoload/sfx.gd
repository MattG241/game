extends Node
## Audio buses, one-shot sounds and looping ambience.
## Sounds are synthesised by tools/gen_audio.py; where a recorded ElevenLabs effect exists
## (assets/sfx_el, made once offline by tools/elevenlabs/el.py) it is used instead.

const BUSES := ["Music", "Ambience", "Speech", "Effects", "Weather"]
## How far the room and the weather dip while someone is speaking (dB), so words come through.
## (The music director ducks the music itself.)
const SPEECH_DUCK_DB := {"Ambience": -9.0, "Weather": -9.0}
const SETTING_FOR_BUS := {
	"Master": "vol_master", "Music": "vol_music", "Ambience": "vol_ambience",
	"Speech": "vol_speech", "Effects": "vol_effects", "Weather": "vol_weather",
}

## Game sound name -> recorded effect that replaces it when present.
const RECORDED := {
	"tap_clunk": "tap_lever", "glass_place": "glass_on_bar", "clink": "glass_clink", "till": "till_drawer",
	"door_bell": "door_bell", "dart_hit": "dart_hit", "cheer": "cheer_crowd", "laugh": "laugh_group",
	"crowd_loop": "pub_busy_loop", "quiet_crowd_loop": "pub_quiet_loop", "rain_loop": "rain_window_loop",
	"fire_loop": "fire_loop", "applause": "applause", "bottle_open": "bottle_open", "stool": "stool_scrape",
	"foam_settle": "foam_settle", "wash": "wash_glass", "success": "success_sting", "split_tension": "split_tension",
	"pour_loop": "stout_pour",
}

var streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Ambience" if b == "Weather" else "Master")
	# weather is heard from indoors, through the glass: muffled and well below the room
	var weather := AudioServer.get_bus_index("Weather")
	if AudioServer.get_bus_effect_count(weather) == 0:
		var glass := AudioEffectLowPassFilter.new()
		glass.cutoff_hz = 1400.0
		glass.resonance = 0.4
		AudioServer.add_bus_effect(weather, glass)
	# a gentle limiter on the whole mix, so a cheer or a slammed glass never clips over the speech
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(master, lim)
	# a touch of room on voices, so they sound like people in the pub rather than a dry recording
	var speech := AudioServer.get_bus_index("Speech")
	if speech >= 0 and AudioServer.get_bus_effect_count(speech) == 0:
		var room := AudioEffectReverb.new()
		room.room_size = 0.32
		room.damping = 0.6
		room.spread = 0.7
		room.hipass = 0.3
		room.predelay_msec = 18.0
		room.dry = 1.0
		room.wet = 0.11
		AudioServer.add_bus_effect(speech, room)
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_pool.append(p)
	apply_volumes()
	GameState.settings_changed.connect(apply_volumes)


var _base_db := {}
var _duck_left := 0.0
var _duck := 0.0     # 0..1, eased in and out


## Someone is speaking for `seconds`: the room, the weather and the music step back.
func duck_for_speech(seconds: float) -> void:
	_duck_left = maxf(_duck_left, seconds)


func apply_volumes() -> void:
	for bus in SETTING_FOR_BUS.keys():
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			var v := float(GameState.settings.get(SETTING_FOR_BUS[bus], 0.8))
			_base_db[bus] = linear_to_db(maxf(v, 0.0001))
			AudioServer.set_bus_volume_db(idx, _base_db[bus])
			AudioServer.set_bus_mute(idx, v <= 0.001)
	_apply_duck()


func _apply_duck() -> void:
	for bus in SPEECH_DUCK_DB.keys():
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0 and _base_db.has(bus):
			AudioServer.set_bus_volume_db(idx, float(_base_db[bus]) + float(SPEECH_DUCK_DB[bus]) * _duck)


func get_stream(sound: String) -> AudioStream:
	if streams.has(sound):
		return streams[sound]
	var path := "res://assets/audio/%s.ogg" % sound
	if RECORDED.has(sound) and ResourceLoader.exists("res://assets/sfx_el/%s.ogg" % RECORDED[sound]):
		path = "res://assets/sfx_el/%s.ogg" % RECORDED[sound]
	if not ResourceLoader.exists(path):
		push_warning("Missing sound %s" % sound)
		streams[sound] = null
		return null
	var s: AudioStream = load(path)
	if sound.ends_with("_loop") or sound.begins_with("music_"):
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
	streams[sound] = s
	return s


func play(sound: String, volume_db := 0.0, pitch_jitter := 0.05, bus := "Effects") -> void:
	var s := get_stream(sound)
	if s == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.bus = bus
			p.play()
			return


## Plays a positional one-shot at a world position (used for doors, glasses, darts...).
func play_at(sound: String, pos: Vector3, parent: Node, volume_db := 0.0) -> void:
	var s := get_stream(sound)
	if s == null or parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.bus = "Effects"
	p.unit_size = 4.0
	p.pitch_scale = 1.0 + randf_range(-0.05, 0.05)
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Starts or retargets a named looping sound; volume 0 fades it out.
func set_loop(key: String, sound: String, volume_linear: float, bus := "Ambience") -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p == null:
		if volume_linear <= 0.001:
			return
		p = AudioStreamPlayer.new()
		p.stream = get_stream(sound)
		p.bus = bus
		p.volume_db = -60.0
		add_child(p)
		_loops[key] = p
		p.play()
	elif p.stream != get_stream(sound):
		p.stream = get_stream(sound)
		p.play()
	p.bus = bus
	p.set_meta("target", volume_linear)


func stop_all_loops() -> void:
	for k in _loops.keys():
		var p: AudioStreamPlayer = _loops[k]
		p.queue_free()
	_loops.clear()


func _process(delta: float) -> void:
	_duck_left = maxf(0.0, _duck_left - delta)
	var want := 1.0 if _duck_left > 0.0 else 0.0
	if not is_equal_approx(_duck, want):
		_duck = move_toward(_duck, want, delta * (4.0 if want > _duck else 1.2))
		_apply_duck()
	for k in _loops.keys():
		var p: AudioStreamPlayer = _loops[k]
		var target := float(p.get_meta("target", 0.0))
		var cur := db_to_linear(p.volume_db)
		cur = move_toward(cur, target, delta * 1.5)
		p.volume_db = linear_to_db(maxf(cur, 0.0001))
		if not p.playing and target > 0.001:
			p.play()
