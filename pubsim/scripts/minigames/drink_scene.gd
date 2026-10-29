class_name DrinkScene
extends Node
## Two optional drinking activities (virtual only):
##  - "split": the Split-the-Knot precision challenge. One held gulp, then a measured replay.
##  - "relax": an after-shift pint by the fire; hold to sip, at your own pace.

signal finished(result: Dictionary)

const TARGET_Y := 0.098          # emblem centre on the glass (metres from its base)
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
		glass.rotation.y = 0.0
		target = Transform3D(Basis(), SPLIT_POS + Vector3(0.0, 0.1, 0.38)).looking_at(SPLIT_POS + Vector3(0, 0.095, 0), Vector3.UP)
		_build_line()
	else:
		# by the fire, in the left armchair
		var seat := Vector3(-5.5, 1.15, 0.45)
		var look_at := Vector3(-6.6, 0.55, 2.2)
		target = Transform3D(Basis(), seat).looking_at(look_at, Vector3.UP)
		_anchor.global_transform = target
		_relax_cam_pos = seat
		glass.position = Vector3(0.12, -0.32, -0.42)
	_cam_tween = world.create_tween()
	_cam_tween.tween_property(cam, "global_transform", target, 0.6).set_trans(Tween.TRANS_SINE)
	world.hud.enter_drink_mode(self)


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
	_line.global_position = SPLIT_POS + Vector3(0, TARGET_Y, 0.048)


func press() -> void:
	if state == "ready" or (mode == "relax" and state == "between"):
		holding = true
		hold_t = 0.0
		state = "drinking"


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
		glass.rotation.z = -_tilt * 0.9
		glass.position = Vector3(-_tilt * 0.06, _tilt * 0.12, _tilt * 0.12)
	else:
		glass.position = Vector3(0.12, -0.32, -0.42).lerp(Vector3(0.02, -0.2, -0.3), _tilt)
		glass.rotation.x = _tilt * 0.55
	if state == "settling":
		_settle_t -= delta
		if _settle_t <= 0.0:
			_score()
	world.hud.update_drink_ui(self)


func boundary_y() -> float:
	return PintGlass.BASE + clampf(glass.contents.body, 0.0, 1.0) * glass.inner_height


func error_mm() -> float:
	return (boundary_y() - TARGET_Y) * 1000.0


func _score() -> void:
	state = "replay"
	var err := error_mm()
	var ae := absf(err)
	var score := clampi(int(round(100.0 - maxf(0.0, ae - 1.0) * 12.0)), 0, 100)
	var verdict := ""
	if ae <= 1.0:
		verdict = "Split the Knot!"
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
	var reactions_good := ["Packie: \"Textbook. I'd frame that.\"", "Nora: \"Well now. Somebody's been practising.\"", "The whole bar cheers!"]
	var reactions_bad := ["Eamon: \"Ah, the knot wins again.\"", "Declan: \"Give it another go, chief.\"", "Aoife: \"Closer than I ever got!\""]
	var react: String = (reactions_good if ae <= 3.0 else reactions_bad)[randi() % 3]
	Sfx.play("cheer" if ae <= 3.0 else "groan", -6.0)
	_result = {"error_mm": err, "score": score, "verdict": verdict, "where": where, "best": best, "reaction": react}
	# close-up replay: zoom onto the line and show it
	_line.visible = true
	var cam: Camera3D = world.close_cam
	var zoom := Transform3D(Basis(), SPLIT_POS + Vector3(0.0, TARGET_Y, 0.16)).looking_at(SPLIT_POS + Vector3(0, TARGET_Y, 0), Vector3.UP)
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = world.create_tween()
	_cam_tween.tween_property(cam, "global_transform", zoom, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	world.hud.show_split_result(_result)
	finished.emit(_result)


func retry() -> void:
	var c := glass.contents
	c.body = 0.87
	c.foam = 0.145
	glass.lace_top = 0.0
	_line.visible = false
	state = "ready"
	_tilt = 0.0
	var cam: Camera3D = world.close_cam
	var target := Transform3D(Basis(), SPLIT_POS + Vector3(0.0, 0.1, 0.38)).looking_at(SPLIT_POS + Vector3(0, 0.095, 0), Vector3.UP)
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = world.create_tween()
	_cam_tween.tween_property(cam, "global_transform", target, 0.6)
	world.hud.enter_drink_mode(self)


func end() -> void:
	if not active:
		return
	active = false
	holding = false
	if mode == "relax":
		GameState.stats["own_pints"] = int(GameState.stats["own_pints"]) + 1
	if _line:
		_line.queue_free()
		_line = null
	_anchor.queue_free()
	glass = null
	var player: Player = world.player
	var cam: Camera3D = world.close_cam
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = world.create_tween()
	_cam_tween.tween_property(cam, "global_transform", player.camera.global_transform, 0.4)
	_cam_tween.tween_callback(func():
		player.camera.current = true
		player.input_enabled = true)
	world.hud.exit_drink_mode()
