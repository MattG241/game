class_name MatchDay
extends Node
## The match on the big screen: the place fills, the room watches, and a score brings the house down.
## Ballyfinn (the town's own club) play on Sunday afternoons and Wednesday evenings, and in the
## county final on festival day 13. Scores come in hurling style: goals (3) and points (1).

const HOME := "Ballyfinn"
const RIVALS := ["Carrickmore", "Kilbrack", "Glenmoy", "Rathcool", "Dunmara", "Ardnagh"]

var world: Node
var on := false
var finished_today := false
var rival := ""
var score := {"home": [0, 0], "away": [0, 0]}   # [goals, points]
var _next_t := 0.0
var _fade := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(GameState.day * 31 + 5)
	rival = RIVALS[_rng.randi() % RIVALS.size()]


## A match draws a crowd while it's on.
func arrival_mult() -> float:
	return 1.4 if on else 1.0


func total(side: String) -> int:
	return int(score[side][0]) * 3 + int(score[side][1])


func score_text() -> String:
	return "%s %d-%02d   %d-%02d %s" % [HOME, score["home"][0], score["home"][1], score["away"][0], score["away"][1], rival]


func _process(delta: float) -> void:
	var m := GameState.match_today()
	var live := not m.is_empty() and not finished_today and GameState.phase in ["open", "last_orders"] \
		and GameState.hour >= float(m[0]) and GameState.hour < float(m[1])
	if live and not on:
		_throw_in()
	elif on and not live:
		_full_time()
	_fade = move_toward(_fade, 1.0 if on else 0.0, delta * 0.8)
	var mat: ShaderMaterial = world.info.get("tv_mat")
	if mat:
		mat.set_shader_parameter("on", _fade)
	var light: OmniLight3D = world.info.get("tv_light")
	if light:
		light.light_energy = 0.35 * _fade
	var lbl: Label3D = world.info.get("tv_label")
	if lbl:
		lbl.text = ""
		if on and not m.is_empty():
			var minute := int(clampf((GameState.hour - float(m[0])) / (float(m[1]) - float(m[0])), 0.0, 1.0) * 70.0)
			lbl.text = "%s   %d'" % [score_text(), minute]
	if not on:
		return
	_next_t -= delta
	if _next_t <= 0.0:
		_next_t = _rng.randf_range(10.0, 22.0)
		_score()


func _throw_in() -> void:
	on = true
	score = {"home": [0, 0], "away": [0, 0]}
	_next_t = _rng.randf_range(6.0, 12.0)
	world.notify("Throw-in! %s v %s is on the big screen." % [HOME, rival], "good")
	MusicDirector.context["menu_open"] = false


func _score() -> void:
	var home := _rng.randf() < 0.53
	var goal := _rng.randf() < 0.14
	var side := "home" if home else "away"
	score[side][0 if goal else 1] += 1
	if home:
		Sfx.play("cheer", -2.0 if goal else -6.0)
		for c in world.customers:
			if c.state in ["mingle", "drinking", "stand_drink"] and _rng.randf() < (0.9 if goal else 0.6):
				c.cheer()
		GameState.live_tips = minf(GameState.live_tips + (0.04 if goal else 0.015), 0.15)
		world.notify("%s for %s!  %s" % ["GOAL" if goal else "Point", HOME, score_text()], "good")
	else:
		Sfx.play("groan", -6.0)
		if goal:
			world.notify("Goal for %s. The room groans.  %s" % [rival, score_text()], "warn")


func _full_time() -> void:
	on = false
	finished_today = true
	var h := total("home")
	var a := total("away")
	if h > a:
		Sfx.play("cheer", 0.0)
		for c in world.customers:
			c.cheer()
		GameState.reputation = minf(100.0, GameState.reputation + 0.5)
		world.notify("Full time: %s win! %s. The town will be celebrating here all night." % [HOME, score_text()], "good")
	elif h == a:
		world.notify("Full time: a draw. %s. A replay, and another full house." % score_text(), "info")
	else:
		Sfx.play("groan", -3.0)
		world.notify("Full time: %s lose. %s. They'll drown their sorrows." % [HOME, score_text()], "warn")
	GameState.today["match"] = score_text()
