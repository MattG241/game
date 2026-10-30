class_name SessionGame
extends Node
## Sit in on the bodhrán: while a live act plays, keep the beat with the band. Notes are the real
## beats of the song playing (tempo and first beat measured offline by tools/beat_track.py into
## data/beats.json), with a double stroke at the end of every other bar. Tap as each note reaches
## the ring. A good set lifts the room and fills the tip jar.

signal finished(result: Dictionary)

const NOTES := 32
const LEAD := 1.7          # seconds a note takes to cross the lane
const PERFECT := 0.075
const GOOD := 0.17

var world: Node
var active := false
var notes: Array = []      # [time, judged: "" / "perfect" / "good" / "miss"]
var perfect := 0
var good := 0
var missed := 0
var combo := 0
var best_combo := 0
var last_judgement := ""
var _judge_t := 0.0
var _clock := 0.0          # used when the song position can't be read (tests, a silent player)
var _use_clock := false
var _track := ""
var _ui: CanvasLayer
var _lane: Control
var _label: Label
var _tap: TouchButton
var _done_t := -1.0


func can_play() -> bool:
	var live: Node = world.live
	return GameState.has_upgrade("house_bodhran") and live != null and live.playing and live.now_playing != "" \
		and GameData.beats.has(live.now_playing) and not world.in_minigame() and not active


## Where the song is now, in seconds (corrected for output latency).
func song_time() -> float:
	if _use_clock:
		return _clock
	var p: AudioStreamPlayer3D = world.live.player3d
	if p == null or not p.playing:
		return _clock
	return p.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


func begin(use_clock := false) -> bool:
	if not can_play() and not use_clock:
		return false
	_use_clock = use_clock
	_track = world.live.now_playing if world.live and world.live.now_playing != "" else "t08"
	var b: Dictionary = GameData.beats.get(_track, {"bpm": 120.0, "offset": 0.0})
	var period := 60.0 / float(b["bpm"])
	var now := song_time() if not use_clock else 0.0
	_clock = now
	# start on the next bar line a little ahead, so there's time to settle in
	var k := ceili((now + LEAD + 0.8 - float(b["offset"])) / period)
	k = int(ceil(k / 4.0)) * 4
	notes.clear()
	var i := 0
	while notes.size() < NOTES:
		var t := float(b["offset"]) + (k + i) * period
		notes.append([t, ""])
		if i % 8 == 7:
			notes.append([t + period * 0.5, ""])    # the double stroke ending every other bar
		i += 1
	notes.resize(NOTES)
	perfect = 0
	good = 0
	missed = 0
	combo = 0
	best_combo = 0
	last_judgement = ""
	active = true
	_done_t = -1.0
	_build_ui()
	world.hud._hide_gameplay(true)
	world.set_fast_forward(false)
	world.notify("You pull up a stool and take the bodhrán. Keep time with the band!", "good")
	return true


func _process(delta: float) -> void:
	if not active:
		return
	_clock += delta
	var now := song_time()
	for n in notes:
		if n[1] == "" and now - float(n[0]) > GOOD:
			n[1] = "miss"
			missed += 1
			combo = 0
			_show("Miss")
	_judge_t = maxf(0.0, _judge_t - delta)
	if _lane:
		_lane.queue_redraw()
	if _label:
		_label.text = "%s   ·   streak %d   ·   %d / %d" % [last_judgement if _judge_t > 0.0 else "Keep the beat", combo, perfect + good, NOTES]
	var remaining := notes.filter(func(x): return x[1] == "").size()
	if remaining == 0 and _done_t < 0.0:
		_done_t = 1.2
	if _done_t > 0.0:
		_done_t -= delta
		if _done_t <= 0.0:
			_finish()


func _input(event: InputEvent) -> void:
	if active and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_SPACE:
		tap()


## A stroke on the drum.
func tap() -> void:
	if not active:
		return
	Sfx.play("bodhran", -2.0, 0.08)
	var now := song_time()
	var best: Array = []
	var best_dt := 99.0
	for n in notes:
		if n[1] != "":
			continue
		var dt := absf(now - float(n[0]))
		if dt < best_dt:
			best_dt = dt
			best = n
	if best.is_empty() or best_dt > GOOD:
		combo = 0
		_show("Off the beat")
		return
	if best_dt <= PERFECT:
		best[1] = "perfect"
		perfect += 1
		_show("Perfect!")
	else:
		best[1] = "good"
		good += 1
		_show("Good")
	combo += 1
	best_combo = maxi(best_combo, combo)
	if combo in [8, 16, 24]:
		for c in world.customers:
			if c.state == "audience" or randf() < 0.3:
				c.cheer()


func _show(t: String) -> void:
	last_judgement = t
	_judge_t = 0.6


func accuracy() -> float:
	return (perfect + good * 0.6) / float(NOTES)


func _finish() -> void:
	active = false
	var acc := accuracy()
	var tips := snappedf(acc * acc * 25.0, 0.5)
	GameState.earn(tips, "tips")
	GameState.live_atmosphere = minf(GameState.live_atmosphere + 10.0 * acc, 40.0)
	GameState.stats["sessions"] = int(GameState.stats.get("sessions", 0)) + 1
	GameState.stats["rhythm_best"] = maxi(int(GameState.stats.get("rhythm_best", 0)), int(acc * 100.0))
	var verdict := "The band nod you in for the next one." if acc >= 0.8 else ("Not bad at all." if acc >= 0.55 else "Declan takes the drum back, gently.")
	if acc >= 0.8:
		Sfx.play("cheer", -3.0)
		for c in world.customers:
			c.cheer()
	world.notify("Set over: %d%% in time, best streak %d. %s Tip jar +€%.2f" % [int(acc * 100.0), best_combo, verdict, tips], "good" if acc >= 0.55 else "info")
	if _ui:
		_ui.queue_free()
		_ui = null
	world.hud._hide_gameplay(false)
	finished.emit({"accuracy": acc, "perfect": perfect, "good": good, "missed": missed, "tips": tips})


func stop() -> void:
	if active:
		_finish()


# ------------------------------------------------------------------ the lane
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 11
	world.hud.add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme()
	_ui.add_child(root)
	_lane = Control.new()
	_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lane.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_lane.offset_left = -440
	_lane.offset_right = 300
	_lane.offset_top = -190
	_lane.offset_bottom = -110
	_lane.draw.connect(_draw_lane)
	root.add_child(_lane)
	_label = UITheme.hud_label("", 20)
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -440
	_label.offset_right = 300
	_label.offset_top = -236
	_label.offset_bottom = -200
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_label)
	_tap = TouchButton.new("Strike", Color(0.62, 0.4, 0.16, 0.95))
	_tap.style = "accent"
	_tap.round_btn = true
	_tap.font_size = 24
	_tap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_tap.offset_left = -200
	_tap.offset_right = -20
	_tap.offset_top = -200
	_tap.offset_bottom = -20
	_tap.pressed.connect(tap)
	root.add_child(_tap)


func _draw_lane() -> void:
	var sz := _lane.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.045, 0.04, 0.6)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(sz.y / 2.0))
	_lane.draw_style_box(sb, Rect2(Vector2.ZERO, sz))
	var hit_x := sz.y * 0.6
	var cy := sz.y / 2.0
	_lane.draw_arc(Vector2(hit_x, cy), sz.y * 0.36, 0, TAU, 32, UITheme.GOLD, 3.0)
	var now := song_time()
	for n in notes:
		var dt := float(n[0]) - now
		if dt > LEAD or dt < -0.3:
			continue
		var x := hit_x + (sz.x - hit_x - 20.0) * (dt / LEAD)
		var col := Color(1, 0.97, 0.9)
		match str(n[1]):
			"perfect":
				col = Color(0.5, 1.0, 0.6, 0.0 if dt < -0.15 else 0.9)
			"good":
				col = Color(0.95, 0.85, 0.4, 0.0 if dt < -0.15 else 0.9)
			"miss":
				col = Color(1, 0.4, 0.3, 0.5)
		_lane.draw_circle(Vector2(x, cy), sz.y * 0.26, col)
