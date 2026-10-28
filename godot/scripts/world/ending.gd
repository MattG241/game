class_name Ending
extends Node
## The finale: once every speck of the Moon is clean, the lander flies the player home.
## Countdown, lift-off with engine flames, a camera that follows the lander up towards
## Earth, then a "your work here is done" screen. The player can keep cleaning after.

const LIFT_AT := 3.0        # seconds of countdown before lift-off
const FADE_AT := 12.5       # start fading to the end screen
const ACCEL := 3.2          # m/s^2 upwards

var world: Node
var _lander: Node3D
var _start: Transform3D
var _cam: Camera3D
var _flame: CPUParticles3D
var _glow: OmniLight3D
var _t := 0.0
var _ui: CanvasLayer
var _fade: ColorRect
var _caption: Label
var _screen: Control
var _engine_on := false


func start(w: Node) -> void:
	world = w
	_lander = w.base.lander
	_start = _lander.global_transform
	process_mode = Node.PROCESS_MODE_ALWAYS
	Diagnostics.event("ending start")
	if w.current_vehicle:
		w.exit_vehicle()
	w.release_input()
	w.player.set_active(false)
	w.hud.visible = false
	w.controls.visible = false
	# Engine flames under the lander
	_flame = CPUParticles3D.new()
	_flame.amount = 90
	_flame.lifetime = 0.7
	_flame.emitting = false
	_flame.local_coords = false
	_flame.direction = Vector3.DOWN
	_flame.spread = 14.0
	_flame.initial_velocity_min = 14.0
	_flame.initial_velocity_max = 22.0
	_flame.gravity = Vector3.ZERO
	_flame.scale_amount_min = 0.6
	_flame.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := StandardMaterial3D.new()
	m.albedo_texture = UIKit.soft_dot()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	q.material = m
	_flame.mesh = q
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.6, 1.0))
	grad.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	_flame.color_ramp = grad
	_flame.position = Vector3(0, 1.2, 0)
	_lander.add_child(_flame)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.6, 0.25)
	_glow.light_energy = 0.0
	_glow.omni_range = 26.0
	_glow.position = Vector3(0, 0.5, 0)
	_lander.add_child(_glow)
	# Cinematic camera: starts low beside the pad, looking up at the lander.
	_cam = Camera3D.new()
	_cam.far = 4000.0
	_cam.fov = 62.0
	world.add_child(_cam)
	_cam.global_position = _start.origin + Vector3(16, 2.2, 15)
	_cam.look_at(_start.origin + Vector3(0, 4, 0))
	_cam.current = true
	# Overlay: captions and fade
	_ui = CanvasLayer.new()
	_ui.layer = 20
	world.add_child(_ui)
	_caption = UIKit.title("", 54, UIKit.ACCENT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_caption.position = Vector2(-400, 80)
	_caption.size = Vector2(800, 80)
	_ui.add_child(_caption)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)
	UIKit.fill_viewport(_fade)
	Audio.play_music(false)


func _process(delta: float) -> void:
	if _cam == null or _screen != null:
		return
	_t += delta
	# Countdown captions
	if _t < LIFT_AT:
		_caption.text = "LIFT-OFF IN %d" % ceili(LIFT_AT - _t)
		_shake(0.02 * _t)
		_flame.emitting = _t > LIFT_AT - 1.0
		_glow.light_energy = maxf(0.0, _t - (LIFT_AT - 1.0)) * 3.0
	else:
		if not _engine_on:
			_engine_on = true
			_flame.emitting = true
			Audio.play("rocket")
			Settings.vibrate(400, 1.0)
		_caption.text = "HEADING HOME" if _t < 7.0 else ""
		var h := _t - LIFT_AT
		var up := 0.5 * ACCEL * h * h
		var xf := _start
		xf.origin += Vector3(0, up, 0)
		# A gentle tilt towards Earth as it climbs
		var earth_dir := LunarEnv.EARTH_DIR.normalized()
		var tilt := clampf(h / 8.0, 0.0, 1.0) * 0.35
		var axis := Vector3.UP.cross(earth_dir).normalized()
		xf.basis = Basis(axis, tilt) * _start.basis
		xf.origin += Vector3(earth_dir.x, 0, earth_dir.z).normalized() * up * 0.25
		_lander.global_transform = xf
		_glow.light_energy = 3.0
		_shake(maxf(0.0, 0.25 - h * 0.03))
		# Camera: watch from the pad, then follow up and look towards Earth.
		var target := xf.origin + Vector3(0, 3, 0)
		if h > 3.0:
			var k := clampf((h - 3.0) / 3.0, 0.0, 1.0)
			# Above, behind and to the side: the lander climbs towards Earth with the
			# curved Moon falling away below.
			var flat := Vector3(earth_dir.x, 0, earth_dir.z).normalized()
			var side := flat.cross(Vector3.UP)
			var follow := target - flat * (24.0 + h * 1.5) + side * 9.0 + Vector3(0, 7.0 + h * 0.8, 0)
			_cam.global_position = _cam.global_position.lerp(follow, minf(1.0, delta * (0.6 + k * 2.0)))
			var look := target.lerp(target + earth_dir * 400.0, k * 0.06)
			_cam.look_at(look)
		else:
			_cam.look_at(target)
	# Fade out, then the end screen
	if _t > FADE_AT:
		_fade.color.a = clampf((_t - FADE_AT) / 1.5, 0.0, 1.0)
		if _t > FADE_AT + 1.6:
			_show_screen()


func _shake(amount: float) -> void:
	if amount > 0.0:
		_cam.h_offset = randf_range(-amount, amount)
		_cam.v_offset = randf_range(-amount, amount)


func _show_screen() -> void:
	_flame.emitting = false
	GameState.flags["went_home"] = true
	GameState.check_missions()
	SaveManager.save_game()
	Diagnostics.event("ending screen")
	Audio.play("mission")
	_screen = Control.new()
	_screen.theme = UIKit.theme()
	_ui.add_child(_screen)
	UIKit.fill_viewport(_screen)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.03, 1.0)
	_screen.add_child(bg)
	UIKit.fill_viewport(bg)
	var center := CenterContainer.new()
	_screen.add_child(center)
	UIKit.fill_viewport(center)
	var v := UIKit.vbox(14)
	center.add_child(v)
	var t := UIKit.title("YOUR WORK HERE IS DONE", 64, UIKit.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := UIKit.label("You arrived with a toothbrush. You leave the Moon spotless.\nEarth is waiting - and somewhere, the Moon is already gathering dust.", 22, UIKit.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var played := int(GameState.stat("play_time"))
	var stats := "Time on the Moon  %dh %02dm\nArea cleaned  %s m2\nCredits earned  %s CR\nMachines built  %d     Missions  %d" % [
		played / 3600, (played / 60) % 60, GameState.fmt(GameState.stat("m2_cleaned")),
		GameState.fmt(GameState.stat("credits_earned")), GameState.machines.size(), GameState.missions_done.size()]
	var sl := UIKit.label(stats, 22, UIKit.MUTED)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sl)
	var row := UIKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(UIKit.accent_button("KEEP CLEANING", finish, Vector2(320, 76), 24))
	row.add_child(UIKit.button("MAIN MENU", func():
		finish()
		world.quit_to_menu(), Vector2(260, 76), 24))


## Back to the game: lander on its pad, player beside it.
func finish() -> void:
	if world == null:
		return
	_lander.global_transform = _start
	_flame.queue_free()
	_glow.queue_free()
	_cam.queue_free()
	_ui.queue_free()
	world.hud.visible = true
	world.controls.visible = true
	world.player.set_active(true)
	world.player.global_position = _start.origin + Vector3(0, 0.5, -11)
	world.player.camera.current = true
	Audio.play_music(true)
	world.ending = null
	queue_free()
