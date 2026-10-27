class_name UIKit
extends RefCounted
## Shared visual language: fonts, colours, theme and widget helpers.

const BG := Color(0.035, 0.045, 0.075, 0.94)
const PANEL := Color(0.07, 0.09, 0.14, 0.92)
const PANEL_LIGHT := Color(0.11, 0.14, 0.2, 0.95)
const LINE := Color(0.25, 0.32, 0.45, 0.9)
const ACCENT := Color(1.0, 0.62, 0.11)
const CYAN := Color(0.16, 0.85, 1.0)
const TEXT := Color(0.93, 0.95, 0.98)
const MUTED := Color(0.6, 0.66, 0.76)
const GOOD := Color(0.35, 0.95, 0.55)
const BAD := Color(1.0, 0.35, 0.35)

static var _body: FontVariation
static var _bold: FontVariation
static var _title: FontFile
static var _theme: Theme


static func font_body() -> Font:
	if _body == null:
		var f: FontFile = load("res://assets/fonts/Exo2.ttf")
		_body = FontVariation.new()
		_body.base_font = f
		_body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
	return _body


static func font_bold() -> Font:
	if _bold == null:
		var f: FontFile = load("res://assets/fonts/Exo2.ttf")
		_bold = FontVariation.new()
		_bold.base_font = f
		_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 750}
	return _bold


static func font_title() -> Font:
	if _title == null:
		_title = load("res://assets/fonts/Rajdhani-Bold.ttf")
	return _title


static func box(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 14, margin := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font_body()
	t.default_font_size = 24
	# Buttons
	var bn := box(Color(0.12, 0.16, 0.24, 0.96), Color(0.3, 0.4, 0.55), 2, 12, 12)
	var bh := box(Color(0.16, 0.21, 0.31, 0.98), CYAN * Color(1, 1, 1, 0.8), 2, 12, 12)
	var bp := box(ACCENT * Color(0.85, 0.85, 0.85), ACCENT, 2, 12, 12)
	var bd := box(Color(0.09, 0.1, 0.13, 0.8), Color(0.2, 0.22, 0.28), 2, 12, 12)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.05, 0.05, 0.08))
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.48, 0.55))
	t.set_font_size("font_size", "Button", 24)
	t.set_font("font", "Button", font_bold())
	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 2)
	# Panels
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 2, 18, 18))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE, 2, 18, 0))
	# Progress bars
	t.set_stylebox("background", "ProgressBar", box(Color(0.05, 0.06, 0.09, 0.9), Color(0.25, 0.3, 0.4), 1, 8, 0))
	t.set_stylebox("fill", "ProgressBar", box(CYAN, Color(0, 0, 0, 0), 0, 8, 0))
	t.set_font_size("font_size", "ProgressBar", 16)
	# Sliders
	var track := box(Color(0.1, 0.13, 0.2), LINE, 1, 8, 0)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", box(CYAN * Color(1, 1, 1, 0.7), Color(0, 0, 0, 0), 0, 8, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(CYAN, Color(0, 0, 0, 0), 0, 8, 0))
	var grab := _circle_tex(36, Color.WHITE)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)
	# Check buttons
	t.set_font_size("font_size", "CheckButton", 24)
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckButton", _toggle_tex(true))
	t.set_icon("unchecked", "CheckButton", _toggle_tex(false))
	# Scroll bars: wide enough for thumbs
	var sb := box(Color(0.1, 0.12, 0.18, 0.6), Color(0, 0, 0, 0), 0, 6, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", box(Color(0.35, 0.45, 0.6, 0.9), Color(0, 0, 0, 0), 0, 6, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(CYAN, Color(0, 0, 0, 0), 0, 6, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(CYAN, Color(0, 0, 0, 0), 0, 6, 0))
	_theme = t
	return t


static var _dot: ImageTexture


## Soft round particle sprite.
static func soft_dot() -> ImageTexture:
	if _dot == null:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.5))
		_dot = ImageTexture.create_from_image(img)
	return _dot


static func _circle_tex(size: int, c: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - 1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


static func _toggle_tex(on: bool) -> ImageTexture:
	var w := 76
	var h := 40
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg := ACCENT if on else Color(0.25, 0.28, 0.36)
	var knob_x := w - h * 0.5 if on else h * 0.5
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(px.x, h * 0.5, w - h * 0.5)
			var d := px.distance_to(Vector2(cx, h * 0.5))
			var a := clampf(h * 0.5 - d, 0.0, 1.0)
			var col := Color(bg.r, bg.g, bg.b, a)
			var dk := px.distance_to(Vector2(knob_x, h * 0.5))
			var ka := clampf(h * 0.5 - 5.0 - dk, 0.0, 1.0)
			col = col.lerp(Color(1, 1, 1, maxf(a, ka)), ka)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# ----------------------------------------------------------------- widgets

static func label(text: String, size := 24, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold())
	return l


static func title(text: String, size := 44, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_title())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_size := Vector2(200, 72), font_size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(func():
		Audio.play("ui_click")
		Settings.vibrate(8, 0.25)
		cb.call())
	return b


static func accent_button(text: String, cb: Callable, min_size := Vector2(200, 72), font_size := 24) -> Button:
	var b := button(text, cb, min_size, font_size)
	b.add_theme_stylebox_override("normal", box(ACCENT * Color(0.9, 0.9, 0.9), ACCENT.lightened(0.3), 2, 12, 12))
	b.add_theme_stylebox_override("hover", box(ACCENT, Color.WHITE, 2, 12, 12))
	b.add_theme_color_override("font_color", Color(0.06, 0.05, 0.08))
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.05, 0.08))
	return b


static func panel(bg := PANEL, border := LINE, radius := 18, margin := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, 2, radius, margin))
	return p


static func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func bar(color := CYAN, height := 22.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(0, height)
	p.show_percentage = false
	p.add_theme_stylebox_override("fill", box(color, Color(0, 0, 0, 0), 0, 8, 0))
	return p


static func spacer(h := true) -> Control:
	var c := Control.new()
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Makes a root Control cover the whole viewport, now and after rotations/resizes.
static func fill_viewport(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit(c)
	# _fit guards against `c` having been freed (screens outlive menus on rotation).
	c.get_viewport().size_changed.connect(_fit.bind(c))


static func _fit(c) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	c.position = Vector2.ZERO
	c.size = c.get_viewport_rect().size


## Insets (left, top, right, bottom) in viewport units for notches / gesture bars.
static func safe_insets(vp: Viewport) -> Vector4:
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var vs := vp.get_visible_rect().size
	var kx := vs.x / float(win.x)
	var ky := vs.y / float(win.y)
	var screen := DisplayServer.screen_get_size()
	if safe.size.x <= 0 or screen.x != win.x:
		return Vector4(12, 8, 12, 8)
	var l := maxf(safe.position.x * kx, 12.0)
	var t := maxf(safe.position.y * ky, 8.0)
	var r := maxf((screen.x - safe.end.x) * kx, 12.0)
	var b := maxf((screen.y - safe.end.y) * ky, 8.0)
	return Vector4(l, t, r, b)
