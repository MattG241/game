class_name DartsGame
extends Node
## Darts: drag to aim (the aim sways, so release timing matters), release to throw.
## A friendly game of 301 against a regular, straight out (no double needed).

const ORDER := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
const BOARD := PubLayout.DARTBOARD          # centre of the board, on the right wall facing -x
const START_SCORE := 301

var world: Node
var active := false
var opponent := "packie"
var opponent_name := "Packie"
var opponent_skill := 0.032                  # spread of their throws in metres
var scores := [START_SCORE, START_SCORE]
var turn := 0                                # 0 player, 1 opponent
var darts_left := 3
var turn_start := START_SCORE
var aim := Vector2.ZERO                      # board-plane offset in metres (x right, y up)
var aiming := false
var _sway_t := 0.0
var _darts: Array[Node3D] = []
var _busy := false
var _cam_tween: Tween
var _last_throw := ""
var _rng := RandomNumberGenerator.new()
var _reticle: MeshInstance3D
var winner := -1


## Score for a hit at board-plane offset (metres). Returns [points, label].
static func score_at(off: Vector2) -> Array:
	var r := off.length() * 1000.0
	if r < 6.35:
		return [50, "Bullseye!"]
	if r < 15.9:
		return [25, "Outer bull"]
	if r > 170.0:
		return [0, "Missed the board"]
	var a := atan2(off.x, off.y)  # 0 at top, clockwise
	if a < 0.0:
		a += TAU
	var seg := int(floor(fmod(a / (TAU / 20.0) + 0.5, 20.0)))
	var n: int = ORDER[seg]
	if r >= 99.0 and r < 107.0:
		return [n * 3, "Treble %d" % n]
	if r >= 162.0:
		return [n * 2, "Double %d" % n]
	return [n, str(n)]


func begin(opp := "packie") -> void:
	if active:
		return
	active = true
	_rng.randomize()
	opponent = opp
	var r: Dictionary = GameData.regulars_by_id.get(opp, {})
	opponent_name = str(r.get("name", "Packie Walsh")).split(" ")[0]
	opponent_skill = 0.028 if opp == "packie" else 0.04
	scores = [START_SCORE, START_SCORE]
	turn = 0
	darts_left = 3
	turn_start = START_SCORE
	winner = -1
	aim = Vector2.ZERO
	var player: Player = world.player
	player.input_enabled = false
	var cam: Camera3D = world.close_cam
	cam.global_transform = player.camera.global_transform
	cam.current = true
	var eye := Vector3(PubLayout.OCHE_X, 1.62, BOARD.z)
	var target := Transform3D(Basis(), eye).looking_at(BOARD, Vector3.UP)
	_cam_tween = world.new_cam_tween()
	_cam_tween.tween_property(cam, "global_transform", target, 0.6).set_trans(Tween.TRANS_SINE)
	cam.fov = 21.0
	_reticle = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.008
	tm.outer_radius = 0.011
	_reticle.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0.95, 0.4, 0.9)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	_reticle.material_override = m
	world.add_child(_reticle)
	_reticle.rotation = Vector3(0, 0, PI / 2)
	world.hud.enter_darts_mode(self)
	_status("Your throw. Drag to aim, let go to throw. The aim drifts, so time your release.")


func board_point(off: Vector2) -> Vector3:
	# the board faces -x; screen right is -z from the oche
	return BOARD + Vector3(-0.01, off.y, off.x)


func sway() -> Vector2:
	var k := 0.012 + 0.006 * sin(_sway_t * 0.3)
	return Vector2(sin(_sway_t * 1.7) + 0.5 * sin(_sway_t * 4.1), cos(_sway_t * 1.3) + 0.4 * sin(_sway_t * 3.3)) * k


func _process(delta: float) -> void:
	if not active:
		return
	_sway_t += delta
	_reticle.visible = turn == 0 and not _busy and winner < 0
	if _reticle.visible:
		_reticle.global_position = board_point(aim + sway())


func drag(rel: Vector2) -> void:
	if turn != 0 or _busy or winner >= 0:
		return
	aiming = true
	aim += Vector2(rel.x, -rel.y) * 0.00045
	aim = aim.limit_length(0.24)


func release_throw() -> void:
	if turn != 0 or _busy or not aiming or winner >= 0:
		return
	aiming = false
	_throw(aim + sway())


func _throw(off: Vector2) -> void:
	_busy = true
	Sfx.play("dart_throw", -6.0)
	var dart := _make_dart()
	var from: Vector3 = world.close_cam.global_position + Vector3(0.2, -0.25, 0.1 if turn == 0 else -0.3)
	var to := board_point(off)
	dart.global_position = from
	dart.look_at(to, Vector3.UP)
	var tw := world.create_tween()
	tw.tween_method(func(t: float):
		var p: Vector3 = from.lerp(to, t)
		p.y += sin(t * PI) * 0.12
		dart.global_position = p, 0.0, 1.0, 0.32)
	tw.tween_callback(func(): _landed(off))


func _make_dart() -> Node3D:
	var d := Node3D.new()
	world.add_child(d)
	MeshKit.cyl(d, 0.004, 0.0015, 0.05, Vector3(0, 0, -0.025), MeshKit.mat("chrome"), 6, Vector3(PI / 2, 0, 0))
	MeshKit.cyl(d, 0.006, 0.006, 0.05, Vector3(0, 0, 0.02), MeshKit.mat("brass"), 8, Vector3(PI / 2, 0, 0))
	var flight := MeshKit.box(d, Vector3(0.03, 0.002, 0.03), Vector3(0, 0, 0.055), MeshKit.color_mat(Color(0.1, 0.5, 0.2), 0.5))
	MeshKit.box(d, Vector3(0.002, 0.03, 0.03), Vector3(0, 0, 0.055), MeshKit.color_mat(Color(0.1, 0.5, 0.2), 0.5))
	_darts.append(d)
	return d


func _landed(off: Vector2) -> void:
	Sfx.play("dart_hit", -4.0)
	var res := score_at(off)
	var pts: int = res[0]
	var label: String = res[1]
	var who := "You" if turn == 0 else opponent_name
	var new_score: int = scores[turn] - pts
	if new_score < 0:
		_last_throw = "%s: %s, bust!" % [who, label]
		scores[turn] = turn_start
		darts_left = 0
	elif new_score == 0:
		scores[turn] = 0
		_last_throw = "%s: %s, and that's the game!" % [who, label]
		_finish(turn)
		_busy = false
		return
	else:
		scores[turn] = new_score
		_last_throw = "%s: %s" % [who, label]
		darts_left -= 1
	world.hud.update_darts_ui(self, _last_throw)
	await world.get_tree().create_timer(0.6).timeout
	_busy = false
	if darts_left <= 0:
		_next_turn()
	elif turn == 1:
		_ai_throw()


func _next_turn() -> void:
	for d in _darts:
		d.queue_free()
	_darts.clear()
	turn = 1 - turn
	darts_left = 3
	turn_start = scores[turn]
	if turn == 1:
		_status("%s steps up to the oche..." % opponent_name)
		await world.get_tree().create_timer(0.9).timeout
		_ai_throw()
	else:
		_status("Your throw. %d to go." % scores[0])


func _ai_throw() -> void:
	if not active or winner >= 0:
		return
	_busy = true
	await world.get_tree().create_timer(0.7).timeout
	if not active:
		return
	var need: int = scores[1]
	var target := _target_for(need)
	var off := target + Vector2(_rng.randfn(0.0, opponent_skill), _rng.randfn(0.0, opponent_skill))
	_busy = false
	_throw(off)


## Where the AI aims: treble 20 when far away, otherwise a segment that finishes or sets up.
func _target_for(need: int) -> Vector2:
	if need > 60:
		return _seg_point(20, 0.103)
	if need == 50:
		return Vector2.ZERO
	if need <= 20:
		return _seg_point(need, 0.13)
	if need <= 40 and need % 2 == 0:
		return _seg_point(need / 2, 0.166)
	if need <= 60 and need % 3 == 0:
		return _seg_point(need / 3, 0.103)
	return _seg_point(clampi(need - 20, 1, 20), 0.13)


func _seg_point(n: int, radius: float) -> Vector2:
	var idx := ORDER.find(n)
	var a := idx * TAU / 20.0
	return Vector2(sin(a), cos(a)) * radius


func _finish(w: int) -> void:
	winner = w
	GameState.stats["darts_games"] = int(GameState.stats["darts_games"]) + 1
	if w == 0:
		GameState.stats["darts_wins"] = int(GameState.stats["darts_wins"]) + 1
		GameState.relationships[opponent] = int(GameState.relationships.get(opponent, 0)) + 2
		GameState.reputation = minf(100.0, GameState.reputation + 0.5)
		Sfx.play("cheer", -4.0)
		_status("You win! %s buys the next round of crisps." % opponent_name)
	else:
		Sfx.play("groan", -6.0)
		_status("%s wins this one. Fancy a rematch?" % opponent_name)
	world.hud.update_darts_ui(self, _last_throw)


func _status(t: String) -> void:
	world.hud.update_darts_ui(self, t)


func end() -> void:
	if not active:
		return
	active = false
	for d in _darts:
		d.queue_free()
	_darts.clear()
	if _reticle:
		_reticle.queue_free()
	var player: Player = world.player
	var cam: Camera3D = world.close_cam
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = world.new_cam_tween()
	_cam_tween.tween_property(cam, "global_transform", player.camera.global_transform, 0.4)
	_cam_tween.tween_callback(func():
		cam.fov = 50.0
		world.back_to_player_camera())
	world.hud.exit_darts_mode()
