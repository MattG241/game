class_name MapView
extends Control
## The Moon as a 3D globe you can spin (drag) and zoom (pinch / mouse wheel / buttons).
## Shaded relief is generated from the terrain functions on a worker thread (and cached
## on disk); a second texture shows cleaning progress per chunk and locked regions.
## Markers (base, player, machines, vehicles, landmarks) are drawn over the globe.
## Tap the globe to put a waypoint there (tap it again to remove it).

const W := 512                      # relief texture (longitude x latitude)
const H := 256
const SW := 256                     # state overlay texture
const SH := 128
const CACHE := "user://globe_relief_v1.png"
const ZOOM_MIN := 1.12
const ZOOM_MAX := 4.2

static var _relief: ImageTexture
static var _relief_img: Image
static var _keys := PackedInt32Array()   # chunk index of each state pixel
static var _regions := PackedByteArray() # region of each state pixel
static var _task := -1

var world: Node
var _font: Font
var _vp: SubViewport
var _cam: Camera3D
var _globe: MeshInstance3D
var _mat: ShaderMaterial
var _state_img: Image
var _state_tex: ImageTexture
var _state_t := 0.0
var _rot := Basis.IDENTITY          # globe orientation
var _dist := 3.3                    # camera distance (globe radius = 1)
var _touches := {}                  # index -> position
var _pinch_d := 0.0
var _tap_from := Vector2.INF        # where a possible tap started
var _tap_moved := 0.0
var _wp_button: Button
var _overlay: Control


static func prepare() -> void:
	if _relief != null or _task != -1:
		return
	var tints := PackedColorArray()
	for r in GameData.regions:
		tints.append(Color.html(r["tint"]))
	var cached: Image = null
	if FileAccess.file_exists(CACHE):
		cached = Image.load_from_file(CACHE)
		if cached != null and (cached.get_width() != W or cached.get_height() != H):
			cached = null
	_task = WorkerThreadPool.add_task(_generate.bind(tints, cached), false, "globe")


## Pixel centre of an equirectangular image -> direction (y = up).
static func pixel_dir(x: int, y: int, w: int, h: int) -> Vector3:
	var lon := (x + 0.5) / w * TAU - PI
	var lat := PI * 0.5 - (y + 0.5) / h * PI
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))


static func _generate(tints: PackedColorArray, cached: Image) -> void:
	TerrainGen.setup()
	var keys := PackedInt32Array()
	keys.resize(SW * SH)
	var regs := PackedByteArray()
	regs.resize(SW * SH)
	for y in SH:
		for x in SW:
			var d := pixel_dir(x, y, SW, SH)
			keys[y * SW + x] = TerrainGen.key_index(TerrainGen.key_of(d))
			regs[y * SW + x] = TerrainGen.region_dir(d)
	_keys = keys
	_regions = regs
	if cached != null:
		_relief_img = cached
		return
	var hs := PackedFloat32Array()
	hs.resize(W * H)
	var interior := PackedFloat32Array()
	interior.resize(W * H)
	for y in H:
		for x in W:
			var s := TerrainGen.sample_dir(pixel_dir(x, y, W, H))
			hs[y * W + x] = s.x
			interior[y * W + x] = s.y
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var px := TerrainGen.RADIUS * TAU / W
	for y in H:
		var lat := PI * 0.5 - (y + 0.5) / H * PI
		var ex := maxf(px * cos(lat), px * 0.25)     # metres per pixel east-west here
		for x in W:
			var i := y * W + x
			var hx: float = hs[y * W + (x + 1) % W]
			var hy: float = hs[mini(y + 1, H - 1) * W + x]
			var shade := clampf(0.62 + (hs[i] - hx) / ex * 1.6 + (hs[i] - hy) / px * 1.0 + hs[i] * 0.006, 0.18, 1.0)
			var d := pixel_dir(x, y, W, H)
			var c: Color = tints[TerrainGen.region_dir(d)] * shade
			c = c.darkened(interior[i] * 0.25)
			# Landing Zone border
			var s := acos(clampf(d.y, -1.0, 1.0)) * TerrainGen.RADIUS
			if absf(s - TerrainGen.ZONE_RADIUS) < 1.6:
				c = c.lerp(Color(1.0, 0.6, 0.2), 0.7)
			img.set_pixel(x, y, c)
	_relief_img = img
	img.save_png(CACHE)


func _ready() -> void:
	_font = UIKit.font_bold()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	prepare()
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	# No MSAA / transparency: in the Compatibility renderer on phones a multisampled,
	# transparent sub-viewport showed nothing at all.
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	svc.add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.01
	_cam.far = 20.0
	_vp.add_child(_cam)
	_globe = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 96
	sm.rings = 48
	_globe.mesh = sm
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/globe.gdshader")
	_globe.material_override = _mat
	_vp.add_child(_globe)
	_state_img = Image.create(SW, SH, false, Image.FORMAT_RGBA8)
	_state_tex = ImageTexture.create_from_image(_state_img)
	_mat.set_shader_parameter("state", _state_tex)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	# Zoom / recentre buttons for one-handed use.
	var bar := UIKit.vbox(8)
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.position = Vector2(-86, 12)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(bar)
	bar.add_child(UIKit.button("+", func(): _zoom(0.8), Vector2(72, 64), 30))
	bar.add_child(UIKit.button("-", func(): _zoom(1.25), Vector2(72, 64), 30))
	bar.add_child(UIKit.button("ME", _center_on_focus, Vector2(72, 64), 18))
	_wp_button = UIKit.button("CLEAR\nWP", func():
		if world and world.has_method("clear_waypoint"):
			world.clear_waypoint(), Vector2(72, 64), 14)
	bar.add_child(_wp_button)
	_center_on_focus()


## Turns the globe so the player (or their vehicle) faces the camera, base side up.
func _center_on_focus() -> void:
	var d := Vector3.UP * TerrainGen.RADIUS
	if world and world.has_method("focus_node"):
		d = world.focus_node().global_position
	_rot = _facing(d.normalized())


static func _facing(f: Vector3) -> Basis:
	var y := Vector3.UP - f * f.y
	if y.length() < 0.05:
		y = Vector3.FORWARD - f * f.dot(Vector3.FORWARD)
	y = y.normalized()
	var x := y.cross(f).normalized()
	return Basis(x, y, f).transposed()


func _zoom(k: float) -> void:
	_dist = clampf(_dist * k, ZOOM_MIN, ZOOM_MAX)


func _spin(rel: Vector2) -> void:
	# Drag speed follows how much of the globe fills the view.
	var k := 0.0055 * (_dist - 0.95) / 1.6
	_rot = (Basis(Vector3.UP, rel.x * k) * Basis(Vector3.RIGHT, rel.y * k) * _rot).orthonormalized()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_tap_from = event.position
				_tap_moved = 0.0
			else:
				_tap_from = Vector2.INF
		else:
			_touches.erase(event.index)
			if _touches.is_empty() and _tap_from != Vector2.INF and _tap_moved < 14.0:
				_tap(event.position)
			_tap_from = Vector2.INF
		_pinch_d = _pinch_distance()
		accept_event()
	elif event is InputEventScreenDrag:
		_tap_moved += event.relative.length()
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var pd := _pinch_distance()
			if _pinch_d > 1.0 and pd > 1.0:
				_zoom(_pinch_d / pd)
			_pinch_d = pd
		else:
			_spin(event.relative)
		accept_event()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_tap_from = event.position
				_tap_moved = 0.0
			elif _tap_from != Vector2.INF and _tap_moved < 14.0:
				_tap(event.position)
				_tap_from = Vector2.INF
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.1)
			accept_event()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION \
			and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_tap_moved += event.relative.length()
		_spin(event.relative)
		accept_event()
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / maxf(event.factor, 0.01))
		accept_event()


## A tap on the globe: put the waypoint there, or remove it when tapping right on it.
func _tap(pos: Vector2) -> void:
	if world == null or not world.has_method("set_waypoint"):
		return
	var d := globe_dir_at(pos)
	if d == Vector3.ZERO:
		return
	var w: Vector3 = world.waypoint()
	if w.is_finite():
		var ws := _screen(w)
		if ws != Vector2.INF and ws.distance_to(pos) < 28.0:
			world.clear_waypoint()
			Audio.play("ui_back")
			return
	world.set_waypoint(d * TerrainGen.RADIUS)
	Audio.play("ui_click")


## Direction from the Moon's centre under a point of the map view, or ZERO when the
## point is off the globe.
func globe_dir_at(pos: Vector2) -> Vector3:
	var o := _cam.project_ray_origin(pos)
	var r := _cam.project_ray_normal(pos)
	# |o + t r| = 1
	var b := o.dot(r)
	var c := o.dot(o) - 1.0
	var disc := b * b - c
	if disc < 0.0:
		return Vector3.ZERO
	var hit := o + r * (-b - sqrt(disc))
	return (_rot.inverse() * hit).normalized()


func _pinch_distance() -> float:
	if _touches.size() < 2:
		return 0.0
	var v: Array = _touches.values()
	return (v[0] as Vector2).distance_to(v[1])


func _process(delta: float) -> void:
	if _relief == null and _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_relief = ImageTexture.create_from_image(_relief_img)
	if _relief:
		_mat.set_shader_parameter("relief", _relief)
		_mat.set_shader_parameter("relief_ready", 1.0)
	_globe.basis = _rot
	_cam.position = Vector3(0, 0, _dist)
	_state_t -= delta
	if _state_t <= 0.0 and not _keys.is_empty():
		_state_t = 1.0
		_update_state()
	_wp_button.visible = world != null and world.has_method("waypoint") and (world.waypoint() as Vector3).is_finite()
	_overlay.queue_redraw()


## Cleaning progress per chunk, dust still left (final mission) and locked regions.
func _update_state() -> void:
	var dm := GameState.dirt
	var hunting: bool = world != null and world.has_method("hunting_dust") and world.hunting_dust()
	var n := 6 * TerrainGen.N * TerrainGen.N
	var cols := PackedColorArray()
	cols.resize(n)
	for key in dm.playable():
		var st := dm.chunk_state(key)
		var c := Color(0, 0, 0, 0)
		if st >= 1.0:
			c = Color(0.2, 1.0, 0.5, 0.55)
		elif st > 0.0:
			c = Color(1.0, 0.75, 0.2, 0.25 + 0.4 * st)
		elif hunting:
			c = Color(1.0, 0.25, 0.2, 0.3)
		cols[TerrainGen.key_index(key)] = c
	var locked := PackedByteArray()
	locked.resize(5)
	for r in 5:
		locked[r] = 0 if GameState.region_unlocked(r) else 1
	var data := PackedByteArray()
	data.resize(SW * SH * 4)
	for i in SW * SH:
		var c: Color = cols[_keys[i]]
		if locked[_regions[i]] == 1 and c.a < 0.5:
			c = Color(0, 0, 0, 0.55)
		data[i * 4] = int(c.r * 255.0)
		data[i * 4 + 1] = int(c.g * 255.0)
		data[i * 4 + 2] = int(c.b * 255.0)
		data[i * 4 + 3] = int(c.a * 255.0)
	_state_img.set_data(SW, SH, false, Image.FORMAT_RGBA8, data)
	_state_tex.update(_state_img)


# ------------------------------------------------------------------ overlay

## Screen position of a world point on the globe surface, or Vector2.INF when it is on
## the far side.
func _screen(p: Vector3, lift := 0.0) -> Vector2:
	var g := _rot * (p.normalized() * (1.0 + lift))
	if g.dot(_cam.position - g) <= 0.0:
		return Vector2.INF
	return _cam.unproject_position(g)


func _draw_overlay() -> void:
	var o := _overlay
	if _relief == null:
		o.draw_string(_font, size * 0.5 - Vector2(90, 0), "Charting the Moon...", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIKit.MUTED)
	var pct := "MOON CLEANED  %.1f%%" % (GameState.world_clean_fraction() * 100.0)
	_text(Vector2(12, 28), pct, 18, UIKit.GOOD)
	_text(Vector2(12, size.y - 12), "Drag to spin  -  pinch or +/- to zoom  -  tap to set a waypoint", 14, Color(0.7, 0.85, 1.0))
	var hunting: bool = world != null and world.has_method("hunting_dust") and world.hunting_dust()
	# Region names
	var names := {0: Vector2(0, 75), 1: Vector2(380, 0), 2: Vector2(0, -380), 3: Vector2(-380, 0), 4: Vector2(0, 380)}
	for idx in names:
		var m: Vector2 = names[idx]
		var sp := _screen(TerrainGen.map_to_dir(m.x, m.y))
		if sp == Vector2.INF:
			continue
		var txt: String = GameData.region(idx)["name"]
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_text(sp - Vector2(w * 0.5, 0), txt, 16, Color(1, 1, 1, 0.9) if GameState.region_unlocked(idx) else Color(1, 0.5, 0.4))
	# Landmarks
	if _dist < 2.2:
		for lm in TerrainGen.LANDMARK_CRATERS:
			var sp := _screen(TerrainGen.map_to_dir(lm[1], lm[2]))
			if sp != Vector2.INF:
				var nm := String(lm[0]).replace("_", " ").to_upper()
				var w := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				_text(sp - Vector2(w * 0.5, -4), nm, 12, Color(0.75, 0.88, 1.0, 0.85))
	if not GameState.flags.get("probe_recovered", false):
		_marker(TerrainGen.map_to_dir(Landmarks.PROBE_POS.x, Landmarks.PROBE_POS.y), UIKit.GOOD, "PROBE")
	_marker(TerrainGen.map_to_dir(Landmarks.RESEARCH_CENTER.x, Landmarks.RESEARCH_CENTER.y), Color(1.0, 0.6, 0.4), "SALVAGE")
	_marker(Vector3.UP, UIKit.ACCENT, "BASE")
	if world and world.has_method("waypoint"):
		var wp: Vector3 = world.waypoint()
		if wp.is_finite():
			_marker(wp, Color(0.35, 0.85, 1.0), "WAYPOINT")
	if hunting and world and world.has_method("dust_target"):
		var t: Vector3 = world.dust_target()
		if t.is_finite():
			_marker(t, Color(1.0, 0.35, 0.3), "DUST")
	for m in GameState.machines:
		var sp := _screen(AutomationSim.v3(m["pos"]))
		if sp != Vector2.INF:
			o.draw_rect(Rect2(sp - Vector2(3, 3), Vector2(6, 6)), Color.html(GameData.machine(m["id"]).get("color", "#ffffff")))
	for v in GameState.vehicles:
		var sp := _screen(AutomationSim.v3(v["pos"]))
		if sp != Vector2.INF:
			o.draw_circle(sp, 5, Color(0.7, 0.55, 1.0))
	# Player arrow
	if world and world.has_method("focus_node"):
		var f: Node3D = world.focus_node()
		var fp := f.global_position
		var sp := _screen(fp, 0.004)
		if sp != Vector2.INF:
			var ahead := _screen(fp - f.global_basis.z * 25.0, 0.004)
			var fwd := (ahead - sp).normalized() if ahead != Vector2.INF and ahead.distance_to(sp) > 0.5 else Vector2.UP
			var right := Vector2(-fwd.y, fwd.x)
			o.draw_colored_polygon(PackedVector2Array([sp + fwd * 13, sp - fwd * 7 + right * 8, sp - fwd * 4, sp - fwd * 7 - right * 8]), Color.WHITE)
			o.draw_polyline(PackedVector2Array([sp + fwd * 13, sp - fwd * 7 + right * 8, sp - fwd * 4, sp - fwd * 7 - right * 8, sp + fwd * 13]), Color(0, 0, 0, 0.8), 1.5, true)


func _marker(d: Vector3, c: Color, txt: String) -> void:
	var p := _screen(d)
	if p == Vector2.INF:
		return
	_overlay.draw_circle(p, 6, c)
	_overlay.draw_arc(p, 9, 0, TAU, 16, Color(0, 0, 0, 0.7), 2.0, true)
	_text(p + Vector2(10, 6), txt, 14, c)


func _text(p: Vector2, txt: String, fs: int, c: Color) -> void:
	_overlay.draw_string_outline(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
	_overlay.draw_string(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
