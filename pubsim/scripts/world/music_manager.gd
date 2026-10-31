class_name LiveMusic
extends Node
## Live performances booked from the Events menu.
##
## The band's music comes from a positional 3D player at the musicians, so it gets louder as you
## walk up to them, quieter as you walk away, and muffled from the cellar or the street. While they
## play, the MusicDirector fades the background music right out, so there is never a second copy.
## A great night ends with the house anthem, One More Round, with the crowd gathered at the stage.

const EVENT_START := 20.0
const EVENT_END := 23.0
const FINALE := "t17"

var world: Node
var event_id := ""
var playing := false
var musicians: Array[Customer] = []
var player3d: AudioStreamPlayer3D
var set_list: Array[String] = []
var song_index := -1
var now_playing := ""
var crowd_mood := 0.0
var finale_played := false
var championship_open := false
var championship_done := false
var _between := 0.0
var _announced := false
var _audience: Array[Customer] = []
var _laugh_t := 6.0
var _centre := Vector3.ZERO
var _source_room := "main"
var _ending := false
var _reserved_seats: Array[int] = []
var _songs_played := 0
var finished_tonight := false


func _ready() -> void:
	player3d = AudioStreamPlayer3D.new()
	player3d.bus = "Music"
	player3d.unit_size = 6.0
	player3d.max_distance = 45.0
	player3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player3d.attenuation_filter_db = -6.0
	player3d.finished.connect(_on_song_finished)
	world.add_child(player3d)
	event_id = str(GameState.bookings.get(str(GameState.day), ""))


func event_today() -> Dictionary:
	return GameData.events_by_id.get(event_id, {})


## 1.0 on the event's best nights, less when it's booked on an odd night for it.
static func effectiveness(ev: Dictionary, weekday: int) -> float:
	var best: Array = ev.get("best_days", [])
	if best.is_empty():
		return 1.0
	for d in best:
		if int(d) == weekday:
			return 1.0
	return 0.75


func _eff() -> float:
	return effectiveness(event_today(), GameState.weekday())


## Multiplier on arrivals: word gets round from half seven onwards.
func arrival_mult() -> float:
	var ev := event_today()
	if ev.is_empty() or GameState.hour < EVENT_START - 0.5 or GameState.hour > EVENT_END:
		return 1.0
	return 1.0 + (float(ev["draw"]) - 1.0) * _eff() * (1.0 + GameState.get_mod("event_draw"))


func _process(delta: float) -> void:
	var ev := event_today()
	var h := GameState.hour
	var open := GameState.phase in ["open", "last_orders"]
	if not ev.is_empty():
		if not _announced and h >= EVENT_START - 0.5 and open:
			_announced = true
			world.notify("Tonight at 8: %s!" % ev["name"], "info")
		if open and h >= EVENT_START and h < EVENT_END and not playing and not _ending and not finished_tonight \
				and not GameState.today.get("live_finished", false):
			_start(ev)
		elif playing and not _ending and (h >= EVENT_END or GameState.phase == "closing"):
			# let the current song finish naturally, then stop
			_ending = true
	if playing:
		_update_spatial()
		if _between > 0.0:
			_between -= delta
			if _between <= 0.0:
				_next_song()
		var ev2 := event_today()
		var eff := _eff()
		GameState.live_atmosphere = float(ev2.get("atmosphere", 0)) * eff * (1.0 + crowd_mood * 0.3)
		GameState.live_stay = float(ev2.get("stay", 0.0)) * eff
		GameState.live_tips = float(ev2.get("tips", 0.0)) * eff
		var style := "sing" if now_playing == FINALE else str(ev2.get("style", "sway"))
		for c in world.customers:
			if c.state in ["drinking", "stand_drink", "audience"]:
				c.apply_music(1.0 + crowd_mood, style)
		if style == "laugh" and now_playing != "" and _between <= 0.0:
			_laugh_t -= delta
			if _laugh_t <= 0.0:
				_laugh_t = randf_range(7.0, 14.0)
				Sfx.play_at("laugh", _centre + Vector3(-2.5, 1.2, -1.0), world, -6.0)
				for c in world.customers:
					if c.state in ["drinking", "stand_drink", "audience"] and randf() < 0.6:
						c.laugh()
	else:
		GameState.live_atmosphere = 0.0
		GameState.live_stay = 0.0
		GameState.live_tips = 0.0
	MusicDirector.context["live"] = playing


func _start(ev: Dictionary) -> void:
	playing = true
	_ending = false
	crowd_mood = 0.0
	finale_played = false
	championship_open = bool(ev.get("championship", false))
	set_list = build_set_list(ev)
	song_index = -1
	_songs_played = 0
	_spawn_musicians(ev)
	# a game continued mid-gig picks the night back up rather than counting it twice
	var resumed := str(GameState.today.get("live_event", "")) == str(ev["id"])
	if not resumed:
		GameState.stats["events_hosted"] = int(GameState.stats["events_hosted"]) + 1
	GameState.today["live_event"] = ev["id"]
	world.notify(("%s are back on. Walk over to hear them." if resumed else "%s has started! Walk over to hear them.") % ev["name"], "good")
	Sfx.play_at("cheer", _centre + Vector3(-2.0, 1.2, 0), world, -6.0)
	_between = 1.5
	if _band_says("music_intro"):
		_between = 4.5


## The band opens with the booked tune; longer nights add other tunes they know.
func build_set_list(ev: Dictionary) -> Array[String]:
	var out: Array[String] = [str(ev["track"])]
	var fee := float(ev["fee"])
	for other in GameData.events:
		if other["id"] == ev["id"]:
			continue
		var t: String = other["track"]
		var vocal: bool = MusicDirector.tracks.get(t, {}).get("vocal", false)
		# the band knows tunes from acts of a similar standing
		if vocal or float(other["fee"]) > maxf(fee * 1.5, fee + 20.0) or t in out:
			continue
		var req: String = other.get("requires", "")
		if req != "" and not GameState.has_upgrade(req):
			continue
		out.append(t)
	return out


func _next_song() -> void:
	if _ending:
		_finish()
		return
	song_index += 1
	var t := ""
	if song_index < set_list.size():
		t = set_list[song_index]
	else:
		song_index = 0
		t = set_list[0]
	# a brilliant night earns the house anthem
	if not finale_played and _songs_played > 0 and finale_due():
		t = FINALE
		finale_played = true
		_gather_audience("sing", 7)
	elif str(event_today().get("style", "")) == "dance" and song_index == 0:
		_gather_audience("dance", 6)
	now_playing = t
	_songs_played += 1
	# the band moves to the song's real tempo (measured by tools/beat_track.py)
	var b: Dictionary = GameData.beats.get(t, {})
	if not b.is_empty():
		for m in musicians:
			if is_instance_valid(m):
				m.beat = 60.0 / float(b["bpm"])
	var s := MusicDirector.stream(t)
	if s == null:
		_between = 2.0
		return
	player3d.stream = s
	player3d.volume_db = float(MusicDirector.tracks.get(t, {}).get("gain_db", 0.0)) + 3.0
	player3d.play()


## The band's front player says something between tunes (recorded lines only).
func _band_says(tag: String) -> bool:
	if musicians.is_empty() or not is_instance_valid(musicians[0]) or world.voices == null:
		return false
	var m: Customer = musicians[0]
	var said: String = world.voices.speak(m, "musician", tag, true)
	if said != "":
		m.say(said, 4.0)
	return said != ""


## One More Round is played on especially good nights.
func finale_due() -> bool:
	var served := int(GameState.today.get("served", 0))
	var sat := float(GameState.today.get("satisfaction_sum", 0.0)) / maxf(1.0, served)
	return GameState.atmosphere() >= 45.0 and world.customers.size() >= 6 and sat >= 60.0


func _on_song_finished() -> void:
	if not playing:
		return
	var was := now_playing
	now_playing = ""
	Sfx.play_at("cheer", _centre + Vector3(-2.0, 1.2, 0), world, -4.0)
	for c in world.customers:
		if c.state in ["drinking", "stand_drink", "audience"] and randf() < 0.7:
			c.cheer()
	_release_audience()
	if randf() < 0.5:
		world.voices.crowd("cheer")
	if was != FINALE and not finale_played and finale_due():
		if _band_says("music_finale"):
			_between = 5.0
	elif randf() < 0.5:
		_band_says("music_thanks")
	if was == FINALE:
		crowd_mood += 0.5
		GameState.reputation = minf(100.0, GameState.reputation + 1.5)
		GameState.today["singalong"] = true
		world.notify("The whole pub sang One More Round! Reputation up.", "good")
	_between = maxf(_between, 3.0)


func _finish() -> void:
	var spare: Node3D = world.info.get("stage_stools")
	if spare:
		spare.visible = true
	playing = false
	finished_tonight = true
	GameState.today["live_finished"] = true
	_ending = false
	player3d.stop()
	now_playing = ""
	_release_audience()
	for m in musicians:
		if is_instance_valid(m):
			m.queue_free()
	musicians.clear()
	for i in _reserved_seats:
		world.release_seat(i)
	_reserved_seats.clear()
	for c in world.customers:
		c.apply_music(0.0, "")
	championship_open = false
	Sfx.play_at("applause", _centre + Vector3(-2.0, 1.2, 0), world, -4.0)
	GameState.today["live_rating"] = live_rating()
	world.notify("The musicians take a bow. What a night!", "good")


## Rough quality of the night (0..1) used for the end-of-day reputation bonus.
func live_rating() -> float:
	var served := int(GameState.today.get("served", 0))
	var sat := float(GameState.today.get("satisfaction_sum", 0.0)) / maxf(1.0, served)
	return clampf(_eff() * (sat / 100.0) * (1.0 + crowd_mood * 0.2), 0.0, 1.0)


# ------------------------------------------------------------------ spatial audio
func room_of(p: Vector3) -> String:
	if p.z < PubLayout.ROOM_MIN.y - 0.05:
		return "cellar"
	if p.z > PubLayout.ROOM_MAX.y + 0.1:
		return "street"
	return "main"


func _update_spatial() -> void:
	var cam := world.get_viewport().get_camera_3d()
	if cam == null:
		return
	var listener_room := room_of(cam.global_position)
	var same := listener_room == _source_room
	# walls between rooms muffle the band
	player3d.attenuation_filter_cutoff_hz = 20000.0 if same else 900.0
	var base := float(MusicDirector.tracks.get(now_playing, {}).get("gain_db", 0.0)) + 3.0
	player3d.volume_db = base if same else base - 10.0


# ------------------------------------------------------------------ musicians & crowd
## Beside the hearth (not in front of it), so the fire still shows from the room.
const FIRESIDE_SPOT := Vector3(-4.6, 0, 2.2)    # at the front of the hearth rug: the armchairs face each other
# across the hearth, so the fiddler sits out beyond their sitters' feet and the sweep of his bow


func performance_centre(ev: Dictionary) -> Vector3:
	match str(ev.get("where", "stage")):
		"fireside":
			return FIRESIDE_SPOT
		"table":
			return Vector3(-4.4, 0, 0.9)
	return PubLayout.STAGE_POS


func _spawn_musicians(ev: Dictionary) -> void:
	_centre = performance_centre(ev)
	_source_room = "main"
	player3d.global_position = _centre + Vector3(0, 1.3, 0)
	var players: Array = ev.get("players", [])
	var where := str(ev.get("where", "stage"))
	var spots: Array = []
	if where == "table":
		# sit round table one if its seats are free, otherwise gather by the fire
		for i in world.info["seats"].size():
			var sd: Dictionary = world.info["seats"][i]
			if (sd["table"] as Vector3).distance_to(_centre + Vector3(0, 0.765, 0)) < 0.6 and not world.seats_taken.has(i):
				spots.append({"pos": sd["pos"], "yaw": sd["yaw"], "seat": i})
	if spots.size() < players.size():
		spots.clear()
		var n := players.size()
		for i in n:
			var spread := 0.0 if n == 1 else (float(i) / (n - 1) - 0.5) * 1.8
			var p: Vector3
			if where == "stage":
				p = _centre + Vector3(spread * 0.5, 0.22, spread)
			else:
				# a shallow arc on the hearth rug facing the room, clear of the armchairs and table one
				p = FIRESIDE_SPOT + Vector3(-absf(spread) * 0.25, 0, spread * 0.7)
			var to := Vector3(1.5, 0, 1.5) - p if where == "stage" else Vector3(-2.0, 0, 2.2) - p
			spots.append({"pos": p, "yaw": atan2(-to.x, -to.z), "seat": -1})
	for i in players.size():
		var m := Customer.new()
		var look := {}
		if i == 0 and ev["id"] in ["fiddles_fire", "fiddlers_table", "galway_reel"]:
			look = GameData.regulars_by_id.get("tomas", {}).get("look", {})
		if i == 0 and not look.has("gender"):
			look = look.duplicate()
			look["gender"] = "m"   # the band's talker, voiced by the musician cast
		m.setup(world, look, 900 + i * 31 + GameState.day)
		if i == 0:
			m.voice = "musician"
		m.display_name = "Musician"
		world.add_child(m)
		var sp: Dictionary = spots[i]
		m.global_position = sp["pos"]
		m.rotation.y = sp["yaw"]
		if int(sp["seat"]) >= 0:
			world.seats_taken[int(sp["seat"])] = m
			_reserved_seats.append(int(sp["seat"]))
		m.make_musician(str(players[i]), 0.5)
		if int(sp["seat"]) < 0:
			m.add_stool()
		musicians.append(m)
	# the band brings its own stools, so the stage's spare ones are put aside while they play
	var spare: Node3D = world.info.get("stage_stools")
	if spare:
		spare.visible = where != "stage"
	# the crowd faces where the band actually is (by the fire if their table was taken)
	if not spots.is_empty():
		var mid := Vector3.ZERO
		for sp2 in spots.slice(0, players.size()):
			mid += sp2["pos"]
		mid /= float(mini(spots.size(), players.size()))
		_centre = Vector3(mid.x, 0.0, mid.z)
		player3d.global_position = _centre + Vector3(0, 1.3, 0)


func _gather_audience(style: String, n: int) -> void:
	# stand in rows in front of the band, wherever there's floor: never in a table, a chair or a musician
	var spots := []
	var on_stage := _centre.distance_to(Vector3(PubLayout.STAGE_POS.x, 0, PubLayout.STAGE_POS.z)) < 1.5
	var base := _centre + (Vector3(-2.4, 0, 0) if on_stage else Vector3(1.6, 0, 0))   # a clear metre off the stage
	var away := -1.0 if on_stage else 1.0
	for i in 24:
		var p := base + Vector3(away * (i / 5) * 0.9, 0, (i % 5 - 2) * 0.9)   # room to move without touching
		if _spot_clear(p):
			spots.append(p)
	var k := 0
	for c in world.customers:
		if k >= mini(n, spots.size()):
			break
		if c.state in ["drinking", "stand_drink"] and c.glass != null:
			c.join_audience(spots[k] + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)), style, _centre)
			_audience.append(c)
			k += 1


func _spot_clear(p: Vector3) -> bool:
	if world.has_method("on_navmesh") and not world.on_navmesh(p):
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.4    # a dancer's elbows and the swing of a step, clear of chairs and tables
	q.shape = sph
	q.transform = Transform3D(Basis(), p + Vector3(0, 0.6, 0))
	q.collision_mask = 1 | 4
	return world.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _release_audience() -> void:
	for c in _audience:
		if is_instance_valid(c) and c.state in ["audience", "walk"]:
			c.leave_audience()
	_audience.clear()


func audience_size() -> int:
	var n := 0
	for c in _audience:
		if is_instance_valid(c) and c.state == "audience":
			n += 1
	return n


# ------------------------------------------------------------------ booking
func can_book(day: int, id: String) -> String:
	var ev: Dictionary = GameData.events_by_id.get(id, {})
	if ev.is_empty():
		return "Unknown act"
	if day < GameState.day:
		return "That day has passed"
	var req: String = ev.get("requires", "")
	if req != "" and not GameState.has_upgrade(req):
		return "Needs: %s" % GameData.upgrade(req).get("name", req)
	if GameState.reputation < float(ev.get("min_rep", 0)):
		return "Needs reputation %d" % int(ev["min_rep"])
	if GameState.bookings.has(str(day)):
		return "Already booked"
	if day == GameState.day and GameState.hour >= EVENT_START - 0.5:
		return "Too late for tonight"
	if not GameState.can_afford(float(ev["fee"])):
		return "Can't afford the fee"
	return ""


func book(day: int, id: String) -> bool:
	if can_book(day, id) != "":
		return false
	var ev: Dictionary = GameData.events_by_id[id]
	GameState.spend(float(ev["fee"]), "event_fees")
	GameState.bookings[str(day)] = id
	if day == GameState.day:
		event_id = id
		_announced = false
	return true


func cancel(day: int) -> bool:
	var key := str(day)
	if not GameState.bookings.has(key) or (day == GameState.day and (playing or GameState.hour >= EVENT_START - 0.5)):
		return false
	var ev: Dictionary = GameData.events_by_id.get(GameState.bookings[key], {})
	GameState.bookings.erase(key)
	# cancelled in good time: the fee comes back, as today's income (it may have been paid another day)
	GameState.earn(float(ev.get("fee", 0)), "refunds")
	if day == GameState.day:
		event_id = ""
	return true


func stop_now() -> void:
	if playing:
		_finish()
