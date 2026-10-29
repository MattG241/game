class_name DrinkScene
extends Node
## Two optional drinking activities (virtual only):
##  - "split": the Split-the-G precision challenge. One held gulp, then a measured replay.
##  - "relax": an after-shift pint by the fire; hold to sip, at your own pace.

signal finished(result: Dictionary)

const FALLBACK_TARGET_Y := 0.098  # used only if data/brand.json is missing
const REVEAL_TIME := 2.4          # slow-motion replay of the gulp, zoomed onto the G
const RELAX_HOLD := Vector3(0.11, -0.2, -0.42)   # the pint in your hand, low right of view
const SPLIT_POS := Vector3(0.9, PubLayout.BAR_TOP, -1.95)

var world: Node
var active := false
var mode := "split"
var drink_id := "stout"
var glass: PintGlass
var holding := false
var state := "ready"             # ready, drinking, settling, replay, done
var hold_t := 0.0
var _settle_t := 0.0
var _tilt := 0.0
var _line: MeshInstance3D
var _cam_tween: Tween
var _result := {}
var _anchor: Node3D
var _sips := 0
var _relax_cam_pos := Vector3.ZERO
var championship := false
var _gulp_start_body := 0.0
var _final_body := 0.0
var _reveal_t := -1.0


## Height of the exact centre of the capital G printed on the glass (metres from its base),
## measured from the rendered artwork by tools/gen_brand.py and stored in data/brand.json.
static func target_y() -> float:
	return float(GameData.brand.get("g_center_y", FALLBACK_TARGET_Y))


## Turn the glass so the G faces the camera (the print wraps around the glass).
static func g_yaw() -> float:
	return -float(GameData.brand.get("g_center_angle", 0.0))


func begin(m: String, drink := "stout") -> void:
	if active:
		return
	active = true
	mode = m
	drink_id = drink
	state = "ready"
	hold_t = 0.0
	_sips = 0
	var player: Player = world.player
	player.input_enabled = false
	_anchor = Node3D.new()
	world.add_child(_anchor)
	glass = PintGlass.new()
	_anchor.add_child(glass)
	glass.contents.drink_id = drink
	glass.contents.serve = "stout"
	glass.contents.body = 0.87
	glass.contents.foam = 0.145
	var cam: Camera3D = world.close_cam
	cam.global_transform = player.camera.global_transform
	cam.current = true
	var target: Transform3D
	if mode == "split":
		_anchor.global_position = SPLIT_POS
		_pose_split_glass()
		target = _split_cam()
		_build_line()
	else:
		# sunk into the left armchair, the fire ahead and your pint in your hand
		var seat := Vector3(-5.95, 1.08, 0.82)
		var look_at := Vector3(-6.55, 0.62, 2.2)
		target = Transform3D(Basis(), seat).looking_at(look_at, Vector3.UP)
		_anchor.global_transform = target
		_relax_cam_pos = seat
		glass.position = RELAX_HOLD
		var hand := Player.build_hand()
		glass.add_child(hand)
	_cam_tween = world.new_cam_tween()
	_cam_tween.tween_property(cam, "global_transform", target, 0.6).set_trans(Tween.TRANS_SINE)
	if mode == "split":
		# the Split the G instrumental takes over the music for the challenge
		MusicDirector.start_override("t13", "minigame")
	world.hud.enter_drink_mode(self)


func _split_cam() -> Transform3D:
	var ty := target_y()
	return Transform3D(Basis(), SPLIT_POS + Vector3(0.0, ty + 0.012, 0.36)).looking_at(SPLIT_POS + Vector3(0, ty + 0.004, 0), Vector3.UP)


func _pose_split_glass() -> void:
	# yaw first (G towards the camera), then tilt towards the drinker in the bar's frame
	# lifted a little and tipped towards the drinker, staying in frame so the line can be judged
	glass.transform.basis = Basis(Vector3.RIGHT, -_tilt * 0.35) * Basis(Vector3.BACK, _tilt * 0.25) * Basis(Vector3.UP, g_yaw())
	glass.position = Vector3(-_tilt * 0.01, _tilt * 0.035, _tilt * 0.04)


func _build_line() -> void:
	_line = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.11, 0.0012)
	_line.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.25, 0.2, 0.9)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	_line.material_override = m
	_line.visible = false
	world.add_child(_line)
	_line.global_position = SPLIT_POS + Vector3(0, target_y(), 0.048)


func press() -> void:
	if state == "ready" or (mode == "relax" and state == "between"):
		holding = true
		hold_t = 0.0
		_gulp_start_body = glass.contents.body
		state = "drinking"
		if mode == "split":
			Sfx.play("split_tension", -8.0, 0.0)
			if world.has_method("crowd_voice"):
				world.crowd_voice("split_anticipation")


func release() -> void:
	if not holding:
		return
	holding = false
	if state == "drinking":
		_sips += 1
		Sfx.play("sip", -4.0)
		if mode == "split":
			state = "settling"
			_settle_t = 1.6
		else:
			state = "between"
			if glass.contents.body <= 0.01:
				state = "done"
				world.hud.set_drink_text("That was a lovely pint. Time for home.")


func _process(delta: float) -> void:
	if not active:
		return
	var c := glass.contents
	var want_tilt := 0.0
	if state == "drinking":
		hold_t += delta
		want_tilt = 1.0
		if _tilt > 0.7:
			# a gulp accelerates the longer you hold it
			var rate := (0.035 + 0.075 * clampf(hold_t / 1.6, 0.0, 1.0)) * (1.0 if mode == "split" else 0.6)
			var take := minf(c.body, rate * delta)
			c.body -= take
			c.foam = maxf(0.03, c.foam - take * 0.12)
			glass.lace_top = maxf(glass.lace_top, minf(1.0, c.total() + 0.02))
			if c.body <= 0.0:
				release()
	_tilt = move_toward(_tilt, want_tilt, delta * 2.5)
	if mode == "split":
		_pose_split_glass()
	else:
		glass.position = RELAX_HOLD.lerp(Vector3(0.07, -0.15, -0.4), _tilt)
		glass.rotation.x = _tilt * 0.45
	if state == "settling":
		_settle_t -= delta
		if _settle_t <= 0.0:
			_score()
	elif state == "reveal":
		# slow-motion replay: the line glides down to where you stopped, right in front of the G
		_reveal_t += delta
		var k := clampf((_reveal_t - 0.5) / (REVEAL_TIME - 0.5), 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		c.body = lerpf(_gulp_start_body, _final_body, k)
		if _reveal_t >= REVEAL_TIME:
			c.body = _final_body
			state = "replay"
			world.hud.show_split_result(_result)
	world.hud.update_drink_ui(self)


func boundary_y() -> float:
	return PintGlass.BASE + clampf(glass.contents.body, 0.0, 1.0) * glass.inner_height


func error_mm() -> float:
	return (boundary_y() - target_y()) * 1000.0


func _score() -> void:
	state = "reveal"
	_reveal_t = 0.0
	_final_body = glass.contents.body
	_gulp_start_body = maxf(_gulp_start_body, _final_body)
	var err := error_mm()
	var ae := absf(err)
	var score := clampi(int(round(100.0 - maxf(0.0, ae - 1.0) * 12.0)), 0, 100)
	var verdict := ""
	if ae <= 1.0:
		verdict = "Split the G!"
	elif ae <= 3.0:
		verdict = "So close!"
	elif err > 0.0:
		verdict = "Not enough. Above the line"
	else:
		verdict = "Too far! Below the line"
	var where := "%.1f mm %s the line" % [ae, "above" if err > 0.0 else "below"]
	if ae <= 0.3:
		where = "dead on the line"
	GameState.stats["split_attempts"] = int(GameState.stats["split_attempts"]) + 1
	var best := GameState.best_split_mm < 0.0 or ae < GameState.best_split_mm
	if best:
		GameState.best_split_mm = ae
	GameState.stats["split_best_score"] = maxi(int(GameState.stats.get("split_best_score", 0)), score)
	if ae <= 1.0:
		GameState.stats["split_perfects"] = int(GameState.stats.get("split_perfects", 0)) + 1
	var reactions_good := ["Packie: \"Textbook. I'd frame that.\"", "Nora: \"Well now. Somebody's been practising.\"", "The whole bar cheers!"]
	var reactions_bad := ["Eamon: \"Ah, the G wins again.\"", "Declan: \"Give it another go, chief.\"", "Aoife: \"Closer than I ever got!\""]
	var react: String = (reactions_good if ae <= 3.0 else reactions_bad)[randi() % 3]
	_result = {"error_mm": err, "score": score, "verdict": verdict, "where": where, "best": best, "reaction": react,
		"best_score": int(GameState.stats["split_best_score"])}
	_crowd_react(ae)
	if championship:
		championship = false
		world.live.championship_done = true
		if ae <= 2.0:
			GameState.earn(50.0, "prizes")
			GameState.reputation = minf(100.0, GameState.reputation + 2.0)
			_result["reaction"] = "Championship won! 50 euro prize and the whole pub on its feet."
		else:
			_result["reaction"] = "Not this year. The championship goes to Packie, again."
	# close-up slow-motion replay: the glass settles upright, the camera pushes in on the G, the
	# target line appears through its centre and the liquid line glides down to where you stopped
	_tilt = 0.0
	_pose_split_glass()
	glass.contents.body = _gulp_start_body
	_line.visible = true
	var cam: Camera3D = world.close_cam
	var ty := target_y()
	var zoom := Transform3D(Basis(), SPLIT_POS + Vector3(0.0, ty + 0.004, 0.15)).looking_at(SPLIT_POS + Vector3(0, ty, 0), Vector3.UP)
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = world.new_cam_tween()
	_cam_tween.tween_property(cam, "global_transform", zoom, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	world.hud.set_drink_text("Slow-motion replay...")
	finished.emit(_result)


func _crowd_react(ae: float) -> void:
	var tag := "split_success" if ae <= 1.0 else ("split_near" if ae <= 3.0 else "split_fail")
	# a beat of anticipation, then the bar reacts (cheer for a split, groans for a miss)
	var t := world.get_tree().create_timer(REVEAL_TIME * 0.85)
	t.timeout.connect(func():
		if not active:
			return
		Sfx.play("cheer" if ae <= 3.0 else "groan", -6.0)
		if world.has_method("crowd_voice"):
			world.crowd_voice(tag))


func retry() -> void:
	var c := glass.contents
	c.body = 0.87
	c.foam = 0.145
	glass.lace_top = 0.0
	_line.visible = false
	state = "ready"
	_tilt = 0.0
	var cam: Camera3D = world.close_cam
	_pose_split_glass()
	var target := _split_cam()
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = world.new_cam_tween()
	_cam_tween.tween_property(cam, "global_transform", target, 0.6)
	world.hud.enter_drink_mode(self)


func end() -> void:
	if not active:
		return
	active = false
	holding = false
	if mode == "relax":
		GameState.stats["own_pints"] = int(GameState.stats["own_pints"]) + 1
	MusicDirector.clear_override("t13")
	if _line:
		_line.queue_free()
		_line = null
	_anchor.queue_free()
	glass = null
	var player: Player = world.player
	var cam: Camera3D = world.close_cam
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = world.new_cam_tween()
	_cam_tween.tween_property(cam, "global_transform", player.camera.global_transform, 0.4)
	_cam_tween.tween_callback(world.back_to_player_camera)
	world.hud.exit_drink_mode()
