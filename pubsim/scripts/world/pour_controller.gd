class_name PourController
extends Node
## Close-up pouring mode: the player tilts the glass and works the tap handle themselves.

var world: Node
var active := false
var glass: PintGlass
var drink_id := ""
var serve := ""
var tap: Dictionary = {}
var tilt := 0.0            # degrees, smoothed
var tilt_input := 0.0      # 0..1 from the tilt slider
var lever := 0.0           # 0..1 from the tap handle
var _stream: MeshInstance3D
var _stream_mat: ShaderMaterial
var _prev_spilled := 0.0
var _was_flowing := false
var _empty_warned := false
var _cam_tween: Tween
var _spill_acc := 0.0
var _flow_vis := 0.0


func _ready() -> void:
	_stream = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.006
	cm.bottom_radius = 0.007
	cm.height = 1.0
	cm.radial_segments = 8
	cm.rings = 1
	_stream.mesh = cm
	_stream_mat = MeshKit.shader_mat("res://assets/shaders/stream.gdshader")
	_stream.material_override = _stream_mat
	_stream.visible = false
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_stream)


func begin(id: String, tap_info: Dictionary) -> void:
	var player: Player = world.player
	if player.held == null or active:
		return
	active = true
	drink_id = id
	serve = GameData.drink(id).get("serve", "stout")
	tap = tap_info
	glass = player.held
	var gp := glass.global_transform
	player.hand.remove_child(glass)
	world.add_child(glass)
	glass.global_transform = gp
	tilt = 0.0
	tilt_input = 0.0
	lever = 0.0
	_prev_spilled = glass.contents.spilled
	_empty_warned = false
	glass.contents.freshness = GameState.freshness(id)
	player.input_enabled = false
	var cam: Camera3D = world.close_cam
	cam.global_transform = player.camera.global_transform
	cam.current = true
	var g0: Vector3 = tap["glass"]
	# from the bartender's side and a little to the left: the glass fills the frame with the nozzle
	# and the falling stream above it, the brass font behind
	var target := Transform3D(Basis(), g0 + Vector3(0.15, 0.19, -0.48))
	target = target.looking_at(g0 + Vector3(0.06, 0.15, 0.0), Vector3.UP)
	_cam_tween = world.new_cam_tween()
	_cam_tween.tween_property(cam, "global_transform", target, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	world.hud.enter_pour_mode(self)
	Sfx.play("tap_clunk", -10.0)


func ideal_tilt() -> float:
	var c := glass.contents
	if serve == "stout" and c.stage >= 2:
		return 0.0
	var lvl := c.total()
	if lvl < 0.45:
		return 45.0
	return lerpf(45.0, 4.0, clampf((lvl - 0.45) / 0.35, 0.0, 1.0))


func _process(delta: float) -> void:
	if not active:
		return
	var assist := bool(GameState.settings.get("pour_assist", false))
	var want := ideal_tilt() if assist else tilt_input * 90.0
	tilt = move_toward(tilt, want, delta * 140.0)
	_place_glass()
	var flow := lever
	if flow > 0.01 and GameState.serves_left(drink_id) <= 0.005:
		flow = 0.0
		if not _empty_warned:
			_empty_warned = true
			world.notify("The %s has run dry! Change it in the cellar." % GameData.drink(drink_id).get("stock_unit", "keg"), "bad")
			Sfx.play("keg", -8.0)
	var c := glass.contents
	if flow > 0.01:
		var dv := c.pour(delta, flow, tilt, drink_id, serve)
		if not GameState.draw_units(drink_id, dv):
			GameState.draw_units(drink_id, GameState.serves_left(drink_id))
		_was_flowing = true
	elif _was_flowing:
		_was_flowing = false
		c.stop_pour()
		_report_stop()
	# spills land on the drip tray / bar
	var sp := c.spilled - _prev_spilled
	if sp > 0.0:
		_spill_acc += sp
		_prev_spilled = c.spilled
		GameState.waste_units(drink_id, sp)
		if _spill_acc > 0.025:
			_spill_acc = 0.0
			Sfx.play("spill", -8.0)
			GameState.vibrate(15)
			var p: Vector3 = tap["glass"] + Vector3(randf_range(-0.12, 0.12), 0.0, randf_range(-0.12, 0.05))
			p.y = PubLayout.BAR_TOP
			world.add_spill(p, randf_range(0.05, 0.09))
	_update_tap_visual(flow, delta)
	Sfx.set_loop("pour", "pour_loop", flow * 0.9, "Effects")
	Sfx.set_loop("bubbles", "bubbles_loop", clampf(c.cascade * 2.0, 0.0, 0.7) if serve == "stout" else 0.0, "Effects")


func _place_glass() -> void:
	var nozzle: Vector3 = tap["nozzle"]
	var th := deg_to_rad(tilt)
	var h := glass.height
	# rotate about the view axis so the tilt reads clearly on screen
	var basis := Basis(Vector3(0, 0, 1), th)
	var side := Vector3(-1, 0, 0)  # direction the top of the glass leans
	var base := nozzle - Vector3(0, 0.035 + h * cos(th), 0) - side * h * sin(th) * 0.82
	glass.global_transform = Transform3D(basis, base)


func _update_tap_visual(flow: float, delta: float) -> void:
	var handle: Node3D = tap.get("handle")
	if handle:
		handle.rotation.x = lerpf(handle.rotation.x, -flow * 0.85, minf(1.0, delta * 14.0))
	_flow_vis = move_toward(_flow_vis, flow, delta * 6.0)
	_stream.visible = _flow_vis > 0.03
	if _stream.visible:
		var nozzle: Vector3 = tap["nozzle"]
		var c := glass.contents
		var lvl := clampf(c.total(), 0.0, 1.0)
		var surface := glass.to_global(Vector3(0, PintGlass.BASE + lvl * glass.inner_height, 0))
		var bottom_y := minf(surface.y, nozzle.y - 0.01)
		# the stream hits the glass wall when tilted
		if tilt > 15.0:
			bottom_y = maxf(bottom_y, nozzle.y - 0.08)
		var len := maxf(0.005, nozzle.y - bottom_y)
		_stream.global_position = Vector3(nozzle.x, nozzle.y - len / 2.0, nozzle.z)
		_stream.scale = Vector3(0.6 + _flow_vis * 0.6, len, 0.6 + _flow_vis * 0.6)
		var d := GameData.drink(drink_id)
		var col: Array = d.get("color", [0.4, 0.25, 0.1])
		_stream_mat.set_shader_parameter("color", Color(0.62, 0.44, 0.28) if serve == "stout" else Color(col[0], col[1], col[2]).lightened(0.2))


func _report_stop() -> void:
	var c := glass.contents
	if serve != "stout":
		return
	if c.stage == 2 and c.topup_cascade < 0.0:
		var lvl := c.first_pour_level
		var msg := ""
		if lvl < 0.6:
			msg = "First pour stopped at %d%%. A bit low, aim for about three-quarters." % int(lvl * 100)
		elif lvl > 0.86:
			msg = "First pour at %d%%. That's high, you'll struggle to get a good head." % int(lvl * 100)
		else:
			msg = "First pour: %d%%. Lovely! Let it settle, then top it up." % int(lvl * 100)
		world.hud.set_pour_feedback(msg)


func status_text() -> String:
	var c := glass.contents
	if serve == "stout":
		match c.stage:
			0:
				return "1. Tilt the glass to 45°   2. Pull the tap handle"
			1:
				return "Keep pouring to about three-quarters, straightening as it fills"
			2:
				var s := c.settled_fraction()
				if s < 0.97:
					return "Settling... %d%%  (leave it on the drip tray and do something else)" % int(s * 100)
				return "Settled! Hold the glass upright and top it up gently"
			3:
				return "Top up until the head domes just over the rim"
	return "Tilt the glass, pull the handle, straighten near the top"


func end(to_settle: bool) -> void:
	if not active:
		return
	if _was_flowing:
		glass.contents.stop_pour()
		_was_flowing = false
	active = false
	lever = 0.0
	_stream.visible = false
	Sfx.set_loop("pour", "pour_loop", 0.0, "Effects")
	Sfx.set_loop("bubbles", "bubbles_loop", 0.0, "Effects")
	var handle: Node3D = tap.get("handle")
	if handle:
		handle.rotation.x = 0.0
	var player: Player = world.player
	var g := glass
	glass = null
	world.remove_child(g)
	player.held = null
	var slot: int = world.free_settle_slot() if to_settle else -1
	if to_settle and slot >= 0:
		world.place_on_settle(slot, g)
	else:
		player.take_glass(g)
	var cam: Camera3D = world.close_cam
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = world.new_cam_tween()
	_cam_tween.tween_property(cam, "global_transform", player.camera.global_transform, 0.35).set_trans(Tween.TRANS_SINE)
	_cam_tween.tween_callback(world.back_to_player_camera)
	world.hud.exit_pour_mode()
