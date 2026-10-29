extends Node
## Audio buses, one-shot sounds and looping ambience. All audio is synthesised by tools/gen_audio.py.

const BUSES := ["Music", "Ambience", "Speech", "Effects"]
const SETTING_FOR_BUS := {
	"Master": "vol_master", "Music": "vol_music", "Ambience": "vol_ambience",
	"Speech": "vol_speech", "Effects": "vol_effects",
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
			AudioServer.set_bus_send(idx, "Master")
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_pool.append(p)
	apply_volumes()
	GameState.settings_changed.connect(apply_volumes)


func apply_volumes() -> void:
	for bus in SETTING_FOR_BUS.keys():
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			var v := float(GameState.settings.get(SETTING_FOR_BUS[bus], 0.8))
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(idx, v <= 0.001)


func get_stream(sound: String) -> AudioStream:
	if streams.has(sound):
		return streams[sound]
	var path := "res://assets/audio/%s.ogg" % sound
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
	p.set_meta("target", volume_linear)


func stop_all_loops() -> void:
	for k in _loops.keys():
		var p: AudioStreamPlayer = _loops[k]
		p.queue_free()
	_loops.clear()


func _process(delta: float) -> void:
	for k in _loops.keys():
		var p: AudioStreamPlayer = _loops[k]
		var target := float(p.get_meta("target", 0.0))
		var cur := db_to_linear(p.volume_db)
		cur = move_toward(cur, target, delta * 1.5)
		p.volume_db = linear_to_db(maxf(cur, 0.0001))
		if not p.playing and target > 0.001:
			p.play()
