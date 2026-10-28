class_name Ending
extends Node
## The finale, once every speck of the Moon is clean. A one-minute film with its own
## score (assets/audio/ending_theme.wav, timed to the shots below):
##   0-8 s    the spotless Moon: a slow aerial orbit of the base, fireworks
##   8-14 s   the countdown beside the lander, the Supervisor waving you off
##   14-22 s  lift-off: flames, shaking ground, a ring of exhaust
##   22-34 s  the climb: the camera pulls back until the whole Moon is a globe below,
##            every hexagon glowing green, while your stats appear
##   34-46 s  heading home: behind the lander as Earth grows ahead
##   46 s+    flash to white, then the end titles and credits
## The save is then complete: the game returns to the main menu and the slot can't be
## continued (see SaveManager / main menu).

const T_COUNT := 8.0
const T_LIFT := 14.0
const T_CLIMB := 22.0
const T_HOME := 34.0
const T_TITLES := 46.0
const T_MENU := 66.0
# Kept for tests / older callers
const LIFT_AT := T_LIFT
const FADE_AT := T_TITLES

var world: Node
var _lander: Node3D
var _start: Transform3D
var _up := Vector3.UP
var _cam: Camera3D
var _flame: CPUParticles3D
var _smoke: CPUParticles3D
var _glow: OmniLight3D
var _fireworks: Array[CPUParticles3D] = []
var _globe: MeshInstance3D
var _t := 0.0
var _ui: CanvasLayer
var _bars: Array[ColorRect] = []
var _fade: ColorRect
var _title: Label
var _subtitle: Label
var _count: Label
var _stats: Label
var _skip: Button
var _screen: Control
var _credits: VBoxContainer
var _shown_stats := 0
var _beeps := 0
var _engine_on := false
var _fw_t := 0.0
var _earth_scale := 1.0
var _done := false
var _shot := -1
var _earth_e := Vector3.UP     # Earth's direction, fixed for the whole film


func start(w: Node) -> void:
	world = w
	_lander = w.base.lander
	_start = _lander.global_transform
	_up = _start.origin.normalized()
	process_mode = Node.PROCESS_MODE_ALWAYS
	Diagnostics.event("ending start")
	GameState.flags["went_home"] = true
	GameState.check_missions()
	SaveManager.save_game(-1, false)
	if w.current_vehicle:
		w.exit_vehicle()
	w.release_input()
	w.player.set_active(false)
	w.hud.visible = false
	w.controls.visible = false
	w.controls.enabled = false
	Audio.stop_all_loops()
	Audio.play_track("ending_theme", -2.0)
	# The sky normally follows the camera round the Moon; for the film Earth and the
	# sun stay put so every shot agrees on where home is.
	_earth_e = world.env.earth_dir()
	world.env.set_process(false)
	# Brighter, warmer light for the film
	world.env.sun.light_energy = 2.3
	world.env.env.ambient_light_energy = 0.75
	world.env.env.glow_intensity = 0.9
	_build_effects()
	_build_globe()
	_cam = Camera3D.new()
	_cam.far = 6000.0
	_cam.fov = 58.0
	world.add_child(_cam)
	_cam.current = true
	_build_ui()
	_place_camera(0.0, 0.0)


# ------------------------------------------------------------------ building

func _particles(amount: int, life: float, size: float, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.albedo_texture = UIKit.soft_dot()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	return p


func _build_effects() -> void:
	_flame = _particles(120, 0.7, 1.0, true)
	_flame.direction = Vector3.DOWN
	_flame.spread = 12.0
	_flame.initial_velocity_min = 16.0
	_flame.initial_velocity_max = 26.0
	_flame.gravity = Vector3.ZERO
	_flame.scale_amount_min = 0.7
	_flame.scale_amount_max = 1.8
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
	g.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	_flame.color_ramp = g
	_flame.position = Vector3(0, 1.2, 0)
	_lander.add_child(_flame)
	# Exhaust ring rolling out across the pad
	_smoke = _particles(160, 2.6, 2.4, false)
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_smoke.emission_ring_axis = Vector3.UP
	_smoke.emission_ring_radius = 2.0
	_smoke.emission_ring_inner_radius = 1.0
	_smoke.emission_ring_height = 0.2
	_smoke.direction = Vector3(1, 0.1, 0)
	_smoke.spread = 180.0
	_smoke.flatness = 0.9
	_smoke.initial_velocity_min = 6.0
	_smoke.initial_velocity_max = 12.0
	_smoke.damping_min = 2.0
	_smoke.damping_max = 4.0
	_smoke.gravity = Vector3.ZERO
	_smoke.scale_amount_min = 1.0
	_smoke.scale_amount_max = 3.0
	var gs := Gradient.new()
	gs.set_color(0, Color(0.85, 0.85, 0.9, 0.7))
	gs.set_color(1, Color(0.6, 0.6, 0.65, 0.0))
	_smoke.color_ramp = gs
	world.add_child(_smoke)
	_smoke.global_transform = Transform3D(TerrainGen.upright(_start.origin, Vector3.ZERO), _start.origin + _up * 0.4)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.6, 0.25)
	_glow.light_energy = 0.0
	_glow.omni_range = 30.0
	_glow.position = Vector3(0, 0.5, 0)
	_lander.add_child(_glow)
	# Fireworks over the base
	var cols := [Color(1.0, 0.75, 0.2), Color(0.3, 1.0, 0.6), Color(0.4, 0.8, 1.0), Color(1.0, 0.4, 0.7), Color(1.0, 1.0, 1.0), Color(0.7, 0.5, 1.0)]
	for i in 6:
		var f := _particles(70, 2.2, 0.7, true)
		f.one_shot = true
		f.explosiveness = 1.0
		f.direction = Vector3.UP
		f.spread = 180.0
		f.initial_velocity_min = 7.0
		f.initial_velocity_max = 11.0
		f.damping_min = 1.0
		f.damping_max = 2.0
		f.gravity = -_up * 1.6
		var gf := Gradient.new()
		gf.set_color(0, cols[i])
		gf.set_color(1, Color(cols[i], 0.0))
		f.color_ramp = gf
		world.add_child(f)
		_fireworks.append(f)


## The whole Moon as one globe for the far shots (the streamed terrain only covers
## the ground near the camera): relief map with every hexagon outlined in green.
func _build_globe() -> void:
	MapView.prepare()
	var img: Image = MapView._relief_img
	if img == null:
		return
	var tex_img: Image = img.duplicate()
	if MapView._edge.size() == MapView.SW * MapView.SH and tex_img.get_width() == MapView.SW:
		var glow := Color(0.35, 1.0, 0.6)
		for y in MapView.SH:
			for x in MapView.SW:
				if MapView._edge[y * MapView.SW + x] == 1:
					tex_img.set_pixel(x, y, tex_img.get_pixel(x, y).lerp(glow, 0.75))
	_globe = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = TerrainGen.RADIUS
	sm.height = TerrainGen.RADIUS * 2.0
	sm.radial_segments = 128
	sm.rings = 64
	_globe.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(tex_img)
	# The relief already has its shading: show it as it is, whichever side the sun is.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.1, 1.1, 1.1)
	_globe.material_override = m
	_globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_globe.visible = false
	world.add_child(_globe)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	world.add_child(_ui)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(bar)
		_bars.append(bar)
	_title = _caption(64, UIKit.ACCENT)
	_subtitle = _caption(28, UIKit.TEXT)
	_count = _caption(200, Color(1, 1, 1))
	_stats = _caption(30, Color(0.75, 1.0, 0.85))
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)
	UIKit.fill_viewport(_fade)
	_skip = UIKit.button("SKIP", func(): _t = maxf(_t, T_TITLES - 0.5), Vector2(150, 56), 18)
	_skip.modulate.a = 0.55
	_ui.add_child(_skip)
	_layout()


func _caption(size: int, col: Color) -> Label:
	var l := UIKit.title("", size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	_ui.add_child(l)
	return l


func _layout() -> void:
	var vs := _ui.get_viewport().get_visible_rect().size
	var bh := vs.y * 0.11
	_bars[0].position = Vector2(0, 0)
	_bars[0].size = Vector2(vs.x, bh)
	_bars[1].position = Vector2(0, vs.y - bh)
	_bars[1].size = Vector2(vs.x, bh)
	_title.position = Vector2(0, vs.y * 0.16)
	_title.size = Vector2(vs.x, 90)
	_subtitle.position = Vector2(0, vs.y * 0.16 + 88)
	_subtitle.size = Vector2(vs.x, 50)
	_count.position = Vector2(0, vs.y * 0.3)
	_count.size = Vector2(vs.x, 260)
	_stats.position = Vector2(0, vs.y * 0.62)
	_stats.size = Vector2(vs.x, 160)
	_skip.position = Vector2(vs.x - 180, vs.y - bh - 70)


# ------------------------------------------------------------------ playing

func _process(delta: float) -> void:
	if _cam == null or _done:
		return
	_t += delta
	_layout()
	var t := _t
	# Fade in from black, letterbox bars slide in
	_fade.color.a = clampf(1.0 - t / 1.5, 0.0, 1.0)
	if t >= T_TITLES:
		_fade.color = Color(1, 1, 1, clampf(1.0 - (t - T_TITLES) / 1.2, 0.0, 1.0)) if t < T_TITLES + 1.2 else Color(0, 0, 0, 0)
	elif t > T_TITLES - 0.6:
		_fade.color = Color(1, 1, 1, clampf((t - (T_TITLES - 0.6)) / 0.6, 0.0, 1.0))
	var h := 0.0
	if t >= T_LIFT:
		var k := t - T_LIFT
		h = 0.5 * 1.4 * k * k + 0.08 * k * k * k   # gentle start, then really going
	_fly_lander(t, h)
	_place_camera(t, h)
	_effects(t, delta, h)
	_captions(t)
	if t >= T_TITLES and _screen == null:
		_show_titles()
	if _credits:
		_credits.position.y -= delta * 42.0


func _fly_lander(t: float, h: float) -> void:
	var earth: Vector3 = _earth_e
	var flat := earth - _up * earth.dot(_up)
	flat = flat.normalized() if flat.length() > 0.01 else TerrainGen.frame(_up).x
	var xf := _start
	# Climb, then turn towards Earth as it gains height
	var turn := smoothstep(30.0, 300.0, h)
	var dir := _up.slerp(earth.normalized(), turn * 0.85).normalized()
	xf.origin = _start.origin + _up * minf(h, 40.0) + dir * maxf(h - 40.0, 0.0)
	var tilt := smoothstep(5.0, 200.0, h) * 0.5
	xf.basis = Basis(_up.cross(flat).normalized(), tilt) * _start.basis
	_lander.global_transform = xf
	var near := h < 260.0
	world.terrain.visible = near
	for n in [world.base, world.landmarks, world.automation, world.hex_lines]:
		if n:
			(n as Node3D).visible = near
	if _globe:
		_globe.visible = h >= 200.0


func _place_camera(t: float, h: float) -> void:
	var b := TerrainGen.frame(_up)
	var base := _start.origin
	var lp := _lander.global_position
	var pos: Vector3
	var look: Vector3
	var upv := _up
	if t < T_COUNT:
		# Slow aerial orbit over the spotless base
		var a := t * 0.16 + 0.6
		pos = base + (b.x * cos(a) + b.z * sin(a)) * 46.0 + _up * (26.0 - t * 1.2)
		look = base + _up * 3.0
	elif t < T_LIFT:
		# Beside the lander, the Supervisor in shot
		var k := (t - T_COUNT) / (T_LIFT - T_COUNT)
		pos = base + b * Vector3(9.0 + k * 3.0, 1.6, 12.0 - k * 2.0)
		look = base + _up * (3.0 + k * 2.0)
	elif t < T_LIFT + 3.5:
		# Low on the ground, looking up into the flames
		pos = base + b * Vector3(14.0, 0.9, 11.0)
		look = lp + _up * 2.0
	elif t < T_CLIMB:
		# Chase from above: looking down past the lander at the base falling away
		var k := (t - T_LIFT - 3.5) / (T_CLIMB - T_LIFT - 3.5)
		pos = lp + _up * (7.0 + 6.0 * k) + b.x * 15.0 + b.z * 9.0
		look = lp - _up * (0.5 + 3.0 * k)
	elif t < T_HOME:
		# Pull back and away: the lander high in the frame, the Moon growing into a
		# whole globe below it
		var k := smoothstep(T_CLIMB, T_HOME, t)
		var d := 40.0 + 950.0 * k
		pos = lp + b.x * d + _up * (10.0 + d * 0.12)
		look = lp.lerp(Vector3.ZERO, 0.22 + 0.28 * k)
	else:
		# Right behind the lander, Earth filling the view ahead
		var earth: Vector3 = _earth_e
		var k := smoothstep(T_HOME, T_TITLES, t)
		var side := earth.cross(_up).normalized()
		pos = lp - earth * (34.0 - 8.0 * k) + _up * 5.0 + side * 6.0
		_cam.global_position = pos
		_cam.look_at(pos + earth, _up)
		_cam.fov = lerpf(58.0, 46.0, k)
		_shot = 4
		return
	# Hard cuts between shots, smooth camera moves within one.
	var shot := 0 if t < T_COUNT else (1 if t < T_LIFT else (2 if t < T_LIFT + 3.5 else (5 if t < T_CLIMB else (3 if t < T_HOME else 4))))
	if shot != _shot:
		_shot = shot
		_cam.global_position = pos
	else:
		_cam.global_position = (pos if shot == 5 else _cam.global_position.lerp(pos, 0.5 if shot == 3 else 0.2))
	if _cam.global_position.distance_to(look) > 0.5:
		_cam.look_at(look, upv)
	_cam.fov = 58.0


func _effects(t: float, delta: float, h: float) -> void:
	# Fireworks over the base for the first two shots and at lift-off
	_fw_t -= delta
	if (t < T_LIFT + 4.0) and _fw_t <= 0.0:
		_fw_t = 0.55
		var f: CPUParticles3D = _fireworks[randi() % _fireworks.size()]
		var b := TerrainGen.frame(_up)
		var off := b.x * randf_range(-30.0, 30.0) + b.z * randf_range(-30.0, 30.0)
		f.global_position = _start.origin + off + _up * randf_range(22.0, 38.0)
		f.restart()
		f.emitting = true
		if t > 1.0:
			Audio.play("place", -14.0, randf_range(1.4, 1.8))
	# Countdown beeps
	if t >= T_COUNT + 1.0 and t < T_LIFT and _beeps < int(t - T_COUNT):
		_beeps = int(t - T_COUNT)
		Audio.play("ui_click", -2.0, 1.4)
		Settings.vibrate(40, 0.4)
	_flame.emitting = t > T_LIFT - 1.0 and t < T_TITLES
	_glow.light_energy = clampf((t - (T_LIFT - 1.0)) * 3.0, 0.0, 4.0) if t < T_HOME else 0.0
	if t >= T_LIFT and not _engine_on:
		_engine_on = true
		Audio.play("rocket", 0.0, 0.8)
		Audio.play("rocket", -4.0, 0.6)
		Settings.vibrate(700, 1.0)
		_smoke.emitting = true
	if t > T_LIFT + 3.0:
		_smoke.emitting = false
	var shake := 0.0
	if t > T_LIFT - 1.0 and t < T_CLIMB:
		shake = 0.35 * (1.0 - clampf((t - T_LIFT) / 8.0, 0.0, 1.0)) + (0.05 if t < T_LIFT else 0.0)
	world.env.earth.global_position = _cam.global_position + _earth_e * LunarEnv.EARTH_DIST
	_cam.h_offset = randf_range(-shake, shake)
	_cam.v_offset = randf_range(-shake, shake)
	# Earth grows as you head home
	var es := 1.0 + 2.6 * smoothstep(T_HOME, T_TITLES, t)
	if not is_equal_approx(es, _earth_scale):
		_earth_scale = es
		world.env.earth.scale = Vector3.ONE * es
	# The Supervisor waves you off
	var npc: Node3D = world.base.get("_npc")
	if npc and npc.has_node("ArmR"):
		(npc.get_node("ArmR") as Node3D).rotation.z = 1.2 + sin(t * 8.0) * 0.6


func _captions(t: float) -> void:
	var played := int(GameState.stat("play_time"))
	_show(_title, "THE MOON IS SPOTLESS", t, 1.5, T_COUNT - 0.5)
	_show(_subtitle, "%d / %d hexagons clean  -  not a speck left" % [GameState.hexes_done.size(), HexGrid.count()], t, 2.5, T_COUNT - 0.5)
	if t >= T_COUNT and t < T_LIFT:
		var n := int(ceil(T_LIFT - t))
		_count.text = str(n) if n > 0 else ""
		_count.modulate.a = 1.0 - fmod(t - T_COUNT, 1.0) * 0.6
		_count.scale = Vector2.ONE
	else:
		_count.modulate.a = maxf(_count.modulate.a - 0.05, 0.0)
	_show(_subtitle, "Supervisor Gleam: \"Not one speck left. Go home, cleaner.\"", t, T_COUNT + 0.3, T_LIFT - 0.3, true)
	_show(_title, "LIFT-OFF", t, T_LIFT, T_LIFT + 3.5, true)
	# Stats appear one by one during the climb
	var lines := [
		"Time on the Moon   %dh %02dm" % [played / 3600, (played / 60) % 60],
		"Ground cleaned   %s m2" % GameState.fmt(GameState.stat("m2_cleaned")),
		"Credits earned   %s CR" % GameState.fmt(GameState.stat("credits_earned")),
		"Hexagons   %d / %d" % [GameState.hexes_done.size(), HexGrid.count()],
	]
	if t >= T_CLIMB + 1.0 and t < T_HOME:
		var n := clampi(int((t - T_CLIMB - 1.0) / 2.2) + 1, 0, lines.size())
		if n != _shown_stats:
			_shown_stats = n
			Audio.play("coin", -8.0, 1.0 + n * 0.1)
		_stats.text = "\n".join(lines.slice(0, n))
		_stats.modulate.a = minf(_stats.modulate.a + 0.04, 1.0)
	else:
		_stats.modulate.a = maxf(_stats.modulate.a - 0.03, 0.0)
	_show(_title, "HEADING HOME", t, T_HOME + 0.5, T_TITLES - 1.0, true)
	_show(_subtitle, "You arrived with a toothbrush. You leave the Moon spotless.", t, T_HOME + 2.0, T_TITLES - 1.0, true)


## Fades a caption in over 0.6 s from `a` and out before `b`, setting its text while
## that window is on (later windows on the same label take over).
func _show(l: Label, text: String, t: float, a: float, b: float, _later := false) -> void:
	if t < a - 0.01 or t > b + 0.7:
		return
	l.text = text
	var alpha := clampf((t - a) / 0.6, 0.0, 1.0) * clampf((b + 0.6 - t) / 0.6, 0.0, 1.0)
	l.modulate.a = alpha


func _show_titles() -> void:
	Diagnostics.event("ending screen")
	_skip.visible = false
	for l in [_title, _subtitle, _count, _stats]:
		l.visible = false
	for bar in _bars:
		bar.visible = false
	world.terrain.visible = false
	if _globe:
		_globe.visible = false
	world.env.earth.scale = Vector3.ONE * 3.6
	_screen = Control.new()
	_screen.theme = UIKit.theme()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_screen)
	_ui.move_child(_fade, -1)
	UIKit.fill_viewport(_screen)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.02, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(shade)
	UIKit.fill_viewport(shade)
	var vs := _ui.get_viewport().get_visible_rect().size
	var t := UIKit.title("YOUR WORK HERE IS DONE", 76, UIKit.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 14)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	t.position = Vector2(0, vs.y * 0.1)
	t.size = Vector2(vs.x, 100)
	_screen.add_child(t)
	# Rolling credits
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(vs.x * 0.15, vs.y * 0.26)
	clip.size = Vector2(vs.x * 0.7, vs.y * 0.52)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(clip)
	_credits = UIKit.vbox(16)
	_credits.position = Vector2(0, clip.size.y)
	_credits.size = Vector2(clip.size.x, 10)
	clip.add_child(_credits)
	var played := int(GameState.stat("play_time"))
	var rows := [
		["LUNAR CLEANUP", 46, UIKit.ACCENT],
		["The Moon, cleaned by hand, by wheel, by saucer and by machine.", 22, UIKit.TEXT],
		["", 10, UIKit.TEXT],
		["Time on the Moon   %dh %02dm" % [played / 3600, (played / 60) % 60], 26, Color(0.75, 1.0, 0.85)],
		["Ground cleaned   %s m2" % GameState.fmt(GameState.stat("m2_cleaned")), 26, Color(0.75, 1.0, 0.85)],
		["Dust sold   %s" % GameState.fmt(GameState.stat("dust_sold")), 26, Color(0.75, 1.0, 0.85)],
		["Credits earned   %s CR" % GameState.fmt(GameState.stat("credits_earned")), 26, Color(0.75, 1.0, 0.85)],
		["Hexagons cleared   %d / %d" % [GameState.hexes_done.size(), HexGrid.count()], 26, Color(0.75, 1.0, 0.85)],
		["Machines built   %d     Missions   %d / %d" % [GameState.machines.size(), GameState.missions_done.size(), GameData.missions.size()], 26, Color(0.75, 1.0, 0.85)],
		["", 10, UIKit.TEXT],
		["STARRING", 22, UIKit.MUTED],
		["You", 34, UIKit.TEXT],
		["and one (1) slightly used toothbrush", 22, UIKit.TEXT],
		["", 10, UIKit.TEXT],
		["SUPERVISOR", 22, UIKit.MUTED],
		["Gleam", 30, UIKit.TEXT],
		["", 10, UIKit.TEXT],
		["LUNAR CLEANUP CO. THANKS YOU FOR YOUR SERVICE", 24, UIKit.ACCENT],
		["Somewhere, the Moon is already gathering dust.", 22, UIKit.MUTED],
		["", 30, UIKit.TEXT],
		["THE END", 48, UIKit.TEXT],
	]
	for r in rows:
		var l := UIKit.label(r[0], r[1], r[2], true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(clip.size.x, 0)
		_credits.add_child(l)
	var row := UIKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.position = Vector2(0, vs.y * 0.82)
	row.size = Vector2(vs.x, 80)
	_screen.add_child(row)
	row.add_child(UIKit.accent_button("RETURN TO MAIN MENU", finish, Vector2(420, 76), 24))
	SaveManager.save_game(-1, false)


## The game is complete: back to the main menu (the save can't be continued).
func finish() -> void:
	if world == null or _done:
		return
	_done = true
	Diagnostics.event("ending finished")
	Audio.play_music(false)
	world.quit_to_menu()
