class_name TouchControls
extends Control
## Multi-touch gameplay controls: floating left joystick, right-side swipe look,
## thumb-arc action buttons and a top-right menu row. All hit-testing is manual so
## several fingers work at once and controls stay responsive under load.

signal pressed(id: String)
signal released(id: String)

const JOY_RADIUS := 95.0

## id -> {icon, text, anchor ("br" bottom-right / "tr" top-right / "bl"), offset, r, modes}
var defs := {
	"clean": {"icon": "brush", "text": "CLEAN", "anchor": "br", "offset": Vector2(-215, -185), "r": 88, "modes": ["foot", "vehicle", "fly", "place"]},
	"jump": {"icon": "up", "text": "JUMP", "anchor": "br", "offset": Vector2(-78, -290), "r": 54, "modes": ["foot", "vehicle", "fly"]},
	"down": {"icon": "down", "text": "DOWN", "anchor": "br", "offset": Vector2(-205, -335), "r": 46, "modes": ["fly"]},
	"interact": {"icon": "hand", "text": "USE", "anchor": "br", "offset": Vector2(-400, -95), "r": 60, "modes": ["foot", "vehicle", "fly", "place"]},
	"sprint": {"icon": "run", "text": "SPRINT", "anchor": "br", "offset": Vector2(-80, -125), "r": 50, "modes": ["foot"]},
	"exit": {"icon": "exit", "text": "EXIT", "anchor": "br", "offset": Vector2(-80, -125), "r": 50, "modes": ["vehicle", "fly"]},
	"switch": {"icon": "swap", "text": "TOOL", "anchor": "br", "offset": Vector2(-385, -265), "r": 50, "modes": ["foot", "place"]},
	"menu": {"icon": "menu", "text": "", "anchor": "tr", "offset": Vector2(-52, 52), "r": 36, "modes": ["foot", "vehicle", "fly", "place"]},
	"view": {"icon": "eye", "text": "", "anchor": "tr", "offset": Vector2(-52, 140), "r": 34, "modes": ["foot"]},
	"map": {"icon": "map", "text": "", "anchor": "tr", "offset": Vector2(-140, 52), "r": 36, "modes": ["foot", "vehicle", "fly"]},
	"missions": {"icon": "flag", "text": "", "anchor": "tr", "offset": Vector2(-228, 52), "r": 36, "modes": ["foot", "vehicle", "fly"]},
	"build": {"icon": "build", "text": "", "anchor": "tr", "offset": Vector2(-316, 52), "r": 36, "modes": ["foot"]},
	"shop": {"icon": "shop", "text": "", "anchor": "tr", "offset": Vector2(-404, 52), "r": 36, "modes": ["foot", "vehicle", "fly"]},
}

var mode := "foot"
var enabled := true
var editing := false
var move_vector := Vector2.ZERO
var held := {}                 # id -> true
var toggled := {}              # id -> bool (sprint, clean-toggle)
var labels := {}               # id -> override text
var highlight := {}            # id -> true (e.g. interact available)

var _look_accum := Vector2.ZERO
var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _button_touch := {}        # touch index -> id
var _button_last := {}         # touch index -> last pos (for drag-look from buttons)
var _button_moved := {}        # touch index -> accumulated move
var _edit_drag := {}           # touch index -> id
var _insets := Vector4(12, 8, 12, 8)
var _font: Font
var _pulse := 0.0
var blockers: Array[Control] = []   # visible HUD buttons that take touches first


func _ready() -> void:
	UIKit.fill_viewport(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UIKit.font_bold()
	_apply_layout()
	Settings.changed.connect(_apply_layout)
	get_viewport().size_changed.connect(_on_resized)
	_insets = UIKit.safe_insets(get_viewport())


func _on_resized() -> void:
	_insets = UIKit.safe_insets(get_viewport())
	queue_redraw()


func _apply_layout() -> void:
	var layout: Dictionary = Settings.get_value("layout", {})
	for id in defs:
		if layout.has(id):
			var v = layout[id]
			if v is Vector2:
				defs[id]["custom"] = v
			elif v is Array and v.size() == 2:
				defs[id]["custom"] = Vector2(v[0], v[1])
		else:
			defs[id].erase("custom")
	queue_redraw()


func reset_layout() -> void:
	Settings.set_value("layout", {})


func save_layout() -> void:
	var layout := {}
	for id in defs:
		if defs[id].has("custom"):
			var v: Vector2 = defs[id]["custom"]
			layout[id] = [v.x, v.y]
	Settings.set_value("layout", layout)


func consume_look() -> Vector2:
	var v := _look_accum
	_look_accum = Vector2.ZERO
	return v


func is_held(id: String) -> bool:
	return held.get(id, false)


func _screen() -> Vector2:
	var s := get_viewport_rect().size
	if s.x < 10.0 or s.y < 10.0:
		s = Vector2(1280, 720)
	return s


func button_center(id: String) -> Vector2:
	var d: Dictionary = defs[id]
	var s := _screen()
	var scl := float(Settings.get_value("controls_scale", 1.0))
	var off: Vector2 = d.get("custom", d["offset"] * scl)
	match d["anchor"]:
		"br":
			return Vector2(s.x - _insets.z, s.y - _insets.w) + off
		"tr":
			return Vector2(s.x - _insets.z, _insets.y) + off
		_:
			return Vector2(_insets.x, s.y - _insets.w) + off


func button_radius(id: String) -> float:
	var r: float = defs[id]["r"]
	return r * float(Settings.get_value("controls_scale", 1.0))


func _visible_ids() -> Array:
	var out := []
	for id in defs:
		if mode in defs[id]["modes"]:
			out.append(id)
	return out


func _hit(pos: Vector2) -> String:
	for id in _visible_ids():
		var r := button_radius(id) * 1.15
		if pos.distance_to(button_center(id)) <= r:
			return id
	return ""


func release_all() -> void:
	for id in held.keys():
		released.emit(id)
	held.clear()
	_button_touch.clear()
	_joy_index = -1
	_look_index = -1
	move_vector = Vector2.ZERO
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		# Still honour finger-up events so nothing stays held while a menu is open.
		if event is InputEventScreenTouch and not event.pressed:
			_on_touch(event)
		return
	if event is InputEventScreenTouch:
		if event.canceled:
			# The OS took the touch (gesture bar, notification shade): drop everything.
			release_all()
			return
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(e: InputEventScreenTouch) -> void:
	var pos := e.position
	if e.pressed:
		if editing:
			var hid := _hit(pos)
			if hid != "":
				_edit_drag[e.index] = hid
			return
		for b in blockers:
			if is_instance_valid(b) and b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
				return
		var id := _hit(pos)
		if id != "":
			_button_touch[e.index] = id
			_button_last[e.index] = pos
			_button_moved[e.index] = 0.0
			_press(id)
			get_viewport().set_input_as_handled()
			return
		var scr := _screen()
		if pos.x < scr.x * 0.42 and pos.y > scr.y * 0.22 and _joy_index == -1:
			_joy_index = e.index
			_joy_origin = pos
			_joy_pos = pos
			move_vector = Vector2.ZERO
			get_viewport().set_input_as_handled()
		elif _look_index == -1 and pos.y > 90.0:
			_look_index = e.index
			_look_last = pos
			get_viewport().set_input_as_handled()
	else:
		if editing:
			if _edit_drag.has(e.index):
				_edit_drag.erase(e.index)
				save_layout()
			return
		if _button_touch.has(e.index):
			var id: String = _button_touch[e.index]
			_button_touch.erase(e.index)
			_button_last.erase(e.index)
			_button_moved.erase(e.index)
			_release(id)
		if e.index == _joy_index:
			_joy_index = -1
			move_vector = Vector2.ZERO
		if e.index == _look_index:
			_look_index = -1
	queue_redraw()


func _on_drag(e: InputEventScreenDrag) -> void:
	if editing:
		if _edit_drag.has(e.index):
			var id: String = _edit_drag[e.index]
			var d: Dictionary = defs[id]
			var base: Vector2 = button_center(id) - d.get("custom", d["offset"] * float(Settings.get_value("controls_scale", 1.0)))
			d["custom"] = e.position - base
			queue_redraw()
		return
	if e.index == _joy_index:
		_joy_pos = e.position
		var v := (_joy_pos - _joy_origin) / JOY_RADIUS
		if v.length() > 1.0:
			# Joystick follows the thumb when dragged beyond its rim.
			_joy_origin = _joy_pos - v.normalized() * JOY_RADIUS
			v = v.normalized()
		move_vector = v
		queue_redraw()
	elif e.index == _look_index:
		_look_accum += e.position - _look_last
		_look_last = e.position
	elif _button_touch.has(e.index):
		# Sliding a finger that holds CLEAN (or any button) also steers the camera,
		# so you can scrub and sweep with one thumb.
		var last: Vector2 = _button_last[e.index]
		var delta := e.position - last
		_button_moved[e.index] += delta.length()
		if _button_moved[e.index] > 14.0:
			_look_accum += delta
		_button_last[e.index] = e.position


func _press(id: String) -> void:
	held[id] = true
	Settings.vibrate(10, 0.3)
	pressed.emit(id)
	queue_redraw()


func _release(id: String) -> void:
	held.erase(id)
	released.emit(id)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	if highlight.size() > 0 or held.size() > 0 or _joy_index != -1:
		queue_redraw()


# -------------------------------------------------------------------- drawing

func _draw() -> void:
	var alpha := float(Settings.get_value("controls_opacity", 0.85))
	# Joystick
	if mode != "menu":
		if _joy_index != -1:
			draw_circle(_joy_origin, JOY_RADIUS, Color(0.05, 0.08, 0.12, 0.35 * alpha))
			draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(0.6, 0.8, 1.0, 0.5 * alpha), 3.0, true)
			draw_circle(_joy_origin + move_vector * JOY_RADIUS, 42, Color(0.85, 0.92, 1.0, 0.55 * alpha))
		else:
			var hint := Vector2(_insets.x + 170, size.y - _insets.w - 160)
			draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(0.6, 0.8, 1.0, 0.18 * alpha), 2.0, true)
			draw_circle(hint, 30, Color(0.85, 0.92, 1.0, 0.12 * alpha))
			_draw_text_center("MOVE", hint + Vector2(0, JOY_RADIUS + 22), 18, Color(1, 1, 1, 0.3 * alpha))
	for id in _visible_ids():
		_draw_button(id, alpha)
	if editing:
		_draw_text_center("Drag buttons to rearrange. Tap DONE in settings when finished.", Vector2(size.x * 0.5, size.y * 0.5), 26, UIKit.ACCENT)


func _draw_button(id: String, alpha: float) -> void:
	var c := button_center(id)
	var r := button_radius(id)
	var d: Dictionary = defs[id]
	var is_held: bool = held.get(id, false) or toggled.get(id, false)
	var hl: bool = highlight.get(id, false)
	var bg := Color(0.06, 0.09, 0.14, 0.55 * alpha)
	var ring := Color(0.55, 0.75, 1.0, 0.7 * alpha)
	if id == "clean":
		ring = Color(UIKit.CYAN, 0.9 * alpha)
	if hl:
		ring = Color(UIKit.ACCENT, (0.75 + 0.25 * sin(_pulse * 6.0)) * alpha)
	if is_held:
		bg = Color(UIKit.CYAN if id == "clean" else UIKit.ACCENT, 0.55 * alpha)
	draw_circle(c, r, bg)
	draw_arc(c, r, 0, TAU, 48, ring, 3.0 if r < 60 else 4.0, true)
	var icon_col := Color(1, 1, 1, 0.95 * alpha)
	_draw_icon(d["icon"], c, r * 0.5, icon_col)
	var text: String = labels.get(id, d["text"])
	if text != "":
		_draw_text_center(text, c + Vector2(0, r + 18), 17 if r < 70 else 19, Color(1, 1, 1, 0.8 * alpha))


func _draw_text_center(text: String, pos: Vector2, fsize: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string_outline(_font, pos - Vector2(w * 0.5, -fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, col.a * 0.7))
	draw_string(_font, pos - Vector2(w * 0.5, -fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _draw_icon(icon: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(s * 0.16, 3.0)
	match icon:
		"brush":
			# Toothbrush: handle + head + bristles
			draw_line(c + Vector2(-s, s * 0.7), c + Vector2(s * 0.45, -s * 0.35), col, w * 1.4, true)
			var head := PackedVector2Array([c + Vector2(s * 0.25, -s * 0.65), c + Vector2(s * 1.0, -s * 1.05), c + Vector2(s * 1.12, -s * 0.8), c + Vector2(s * 0.42, -s * 0.38)])
			draw_colored_polygon(head, col)
			for i in 4:
				var p := c + Vector2(s * (0.38 + i * 0.2), -s * (0.55 + i * 0.12))
				draw_line(p, p + Vector2(s * 0.12, s * 0.32), col, w * 0.7, true)
			for i in 3:
				draw_circle(c + Vector2(-s * 0.6 + i * s * 0.55, s * 0.95), s * 0.1, Color(col, col.a * 0.6))
		"up":
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, s * 0.1), c + Vector2(0, -s * 0.7), c + Vector2(s * 0.7, s * 0.1)]), col, w * 1.3, true)
			draw_line(c + Vector2(0, -s * 0.6), c + Vector2(0, s * 0.8), col, w * 1.3, true)
		"down":
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.1), c + Vector2(0, s * 0.7), c + Vector2(s * 0.7, -s * 0.1)]), col, w * 1.3, true)
			draw_line(c + Vector2(0, s * 0.6), c + Vector2(0, -s * 0.8), col, w * 1.3, true)
		"hand":
			draw_circle(c + Vector2(0, s * 0.2), s * 0.45, col)
			for i in 4:
				var x := -s * 0.36 + i * s * 0.24
				draw_line(c + Vector2(x, 0), c + Vector2(x, -s * (0.7 - absf(i - 1.5) * 0.12)), col, w * 1.3, true)
			draw_line(c + Vector2(-s * 0.4, s * 0.25), c + Vector2(-s * 0.8, -s * 0.1), col, w * 1.3, true)
		"run":
			for k in 2:
				var o := Vector2(-s * 0.45 + k * s * 0.6, 0)
				draw_polyline(PackedVector2Array([c + o + Vector2(-s * 0.3, -s * 0.6), c + o + Vector2(s * 0.3, 0), c + o + Vector2(-s * 0.3, s * 0.6)]), col, w * 1.3, true)
		"swap":
			draw_arc(c, s * 0.65, PI * 1.1, PI * 1.9, 16, col, w, true)
			draw_arc(c, s * 0.65, PI * 0.1, PI * 0.9, 16, col, w, true)
			var a1 := c + Vector2.from_angle(PI * 1.9) * s * 0.65
			draw_colored_polygon(PackedVector2Array([a1 + Vector2(-s * 0.25, -s * 0.1), a1 + Vector2(s * 0.2, -s * 0.15), a1 + Vector2(0, s * 0.25)]), col)
			var a2 := c + Vector2.from_angle(PI * 0.9) * s * 0.65
			draw_colored_polygon(PackedVector2Array([a2 + Vector2(s * 0.25, s * 0.1), a2 + Vector2(-s * 0.2, s * 0.15), a2 + Vector2(0, -s * 0.25)]), col)
		"eye":
			draw_arc(c + Vector2(0, s * 0.55), s * 0.95, PI * 1.2, PI * 1.8, 16, col, w * 1.1, true)
			draw_arc(c - Vector2(0, s * 0.55), s * 0.95, PI * 0.2, PI * 0.8, 16, col, w * 1.1, true)
			draw_circle(c, s * 0.28, col)
		"menu":
			for i in 3:
				draw_line(c + Vector2(-s * 0.6, (i - 1) * s * 0.45), c + Vector2(s * 0.6, (i - 1) * s * 0.45), col, w * 1.1, true)
		"map":
			var pts := PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.55), c + Vector2(-s * 0.27, -s * 0.75), c + Vector2(s * 0.27, -s * 0.55), c + Vector2(s * 0.8, -s * 0.75), c + Vector2(s * 0.8, s * 0.6), c + Vector2(s * 0.27, s * 0.8), c + Vector2(-s * 0.27, s * 0.6), c + Vector2(-s * 0.8, s * 0.8), c + Vector2(-s * 0.8, -s * 0.55)])
			draw_polyline(pts, col, w, true)
			draw_line(c + Vector2(-s * 0.27, -s * 0.75), c + Vector2(-s * 0.27, s * 0.6), col, w * 0.7, true)
			draw_line(c + Vector2(s * 0.27, -s * 0.55), c + Vector2(s * 0.27, s * 0.8), col, w * 0.7, true)
		"flag":
			draw_line(c + Vector2(-s * 0.55, s * 0.85), c + Vector2(-s * 0.55, -s * 0.85), col, w * 1.1, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.5, -s * 0.8), c + Vector2(s * 0.75, -s * 0.45), c + Vector2(-s * 0.5, -s * 0.05)]), col)
		"build":
			draw_arc(c, s * 0.5, 0, TAU, 20, col, w * 1.2, true)
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(c + Vector2.from_angle(a) * s * 0.55, c + Vector2.from_angle(a) * s * 0.85, col, w * 1.4, true)
			draw_circle(c, s * 0.18, col)
		"shop":
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.9, -s * 0.7), c + Vector2(-s * 0.6, -s * 0.7), c + Vector2(-s * 0.35, s * 0.35), c + Vector2(s * 0.7, s * 0.35), c + Vector2(s * 0.85, -s * 0.4), c + Vector2(-s * 0.5, -s * 0.4)]), col, w, true)
			draw_circle(c + Vector2(-s * 0.2, s * 0.7), s * 0.15, col)
			draw_circle(c + Vector2(s * 0.55, s * 0.7), s * 0.15, col)
		"exit":
			draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.8), Vector2(s * 0.8, s * 1.6)), col, false, w)
			draw_line(c + Vector2(-s * 0.1, 0), c + Vector2(s * 0.9, 0), col, w * 1.2, true)
			draw_polyline(PackedVector2Array([c + Vector2(s * 0.55, -s * 0.35), c + Vector2(s * 0.9, 0), c + Vector2(s * 0.55, s * 0.35)]), col, w * 1.2, true)
		"brake":
			draw_arc(c, s * 0.75, 0, TAU, 24, col, w * 1.2, true)
			draw_rect(Rect2(c - Vector2(s * 0.35, s * 0.35), Vector2(s * 0.7, s * 0.7)), col)
		"check":
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, 0), c + Vector2(-s * 0.15, s * 0.55), c + Vector2(s * 0.75, -s * 0.6)]), col, w * 1.6, true)
		"cross":
			draw_line(c + Vector2(-s * 0.6, -s * 0.6), c + Vector2(s * 0.6, s * 0.6), col, w * 1.5, true)
			draw_line(c + Vector2(-s * 0.6, s * 0.6), c + Vector2(s * 0.6, -s * 0.6), col, w * 1.5, true)
		"vacuum":
			draw_arc(c, s * 0.75, 0, TAU, 24, col, w, true)
			for i in 3:
				draw_arc(c, s * (0.2 + i * 0.18), _pulse * 3.0 + i, _pulse * 3.0 + i + PI, 12, col, w * 0.8, true)
		_:
			draw_circle(c, s * 0.4, col)
