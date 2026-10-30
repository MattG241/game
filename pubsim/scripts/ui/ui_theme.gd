class_name UITheme
extends RefCounted
## Colours, fonts and the shared Theme for menus.

const WOOD := Color(0.13, 0.08, 0.05, 0.94)
const WOOD_LIGHT := Color(0.22, 0.14, 0.08, 0.96)
const CREAM := Color(0.96, 0.91, 0.78)
const GOLD := Color(0.95, 0.76, 0.36)
const GREEN := Color(0.2, 0.55, 0.32)
const GREEN_DARK := Color(0.08, 0.3, 0.17)
const RED := Color(0.75, 0.22, 0.16)
const MUTED := Color(0.75, 0.68, 0.55)

static var _theme: Theme
static var _tex_boxes := {}


## A 9-patch box from one of the pub's UI textures (assets/ui, made by tools/gen_ui.py):
## "panel_timber", "button_timber", "button_green" or "ticket_ivory".
static func tex_box(name: String, modulate := Color.WHITE, margin_h := 18, margin_v := 12) -> StyleBoxTexture:
	var key := "%s|%s|%d|%d" % [name, modulate.to_html(), margin_h, margin_v]
	if _tex_boxes.has(key):
		return _tex_boxes[key]
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/ui/%s.png" % name)
	sb.set_texture_margin_all(26.0)
	sb.modulate_color = modulate
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	_tex_boxes[key] = sb
	return sb


static func panel_box(bg := WOOD, border := Color(0.55, 0.38, 0.18), radius := 18, border_w := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	return sb


## The in-game HUD's look: dark smoked glass, a hairline edge, optional accent stripe on the left.
const GLASS := Color(0.05, 0.045, 0.04, 0.6)
const HAIRLINE := Color(1, 1, 1, 0.09)


static func glass_box(alpha := 0.6, radius := 14, accent := Color(0, 0, 0, 0), pad_h := 14, pad_v := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GLASS.r, GLASS.g, GLASS.b, alpha)
	sb.set_corner_radius_all(radius)
	if accent.a > 0.0:
		sb.border_color = accent
		sb.border_width_left = 4
	else:
		sb.border_color = HAIRLINE
		sb.set_border_width_all(1)
	sb.content_margin_left = pad_h + (4 if accent.a > 0.0 else 0)
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 10
	return sb


## HUD text: a soft drop shadow instead of a heavy outline.
static func hud_label(text: String, size := 20, color := CREAM, weight := 700) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MeshKit.font_ui(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("outline_size", 0)
	return l


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = MeshKit.font_ui(700)
	t.default_font_size = 26
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color(1, 1, 0.92))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.55, 0.45, 0.7))
	# buttons: green lacquer in a brass rim; panels: dark timber in a brass rim
	var normal := tex_box("button_green", Color.WHITE, 18, 10)
	var hover := tex_box("button_green", Color(1.25, 1.25, 1.2), 18, 10)
	var pressed := tex_box("button_green", Color(0.75, 0.75, 0.75), 18, 10)
	var disabled := tex_box("button_timber", Color(0.7, 0.68, 0.65, 0.85), 18, 10)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", tex_box("panel_timber"))
	t.set_stylebox("panel", "Panel", tex_box("panel_timber"))
	var tab_sel := tex_box("button_green", Color(1.15, 1.15, 1.1), 14, 8)
	var tab_unsel := tex_box("button_timber", Color.WHITE, 14, 8)
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_unsel)
	t.set_stylebox("tab_hovered", "TabBar", tab_unsel)
	t.set_color("font_selected_color", "TabBar", Color(1, 1, 0.92))
	t.set_color("font_unselected_color", "TabBar", MUTED)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = GOLD
	grabber.set_corner_radius_all(10)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.05, 0.03, 0.02)
	slider_bg.set_corner_radius_all(8)
	slider_bg.content_margin_top = 8
	slider_bg.content_margin_bottom = 8
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", grabber)
	t.set_stylebox("grabber_area_highlight", "HSlider", grabber)
	var icon := _circle_icon(34, GOLD)
	t.set_icon("grabber", "HSlider", icon)
	t.set_icon("grabber_highlight", "HSlider", icon)
	var sb_scroll := StyleBoxFlat.new()
	sb_scroll.bg_color = Color(0.3, 0.2, 0.1, 0.5)
	sb_scroll.set_corner_radius_all(6)
	t.set_stylebox("scroll", "VScrollBar", sb_scroll)
	var sb_grab := StyleBoxFlat.new()
	sb_grab.bg_color = GOLD
	sb_grab.set_corner_radius_all(6)
	t.set_stylebox("grabber", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_grab)
	var le := panel_box(Color(0.06, 0.04, 0.03), Color(0.6, 0.45, 0.2), 10, 2)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_color", "CheckButton", CREAM)
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckButton", _toggle_icon(true))
	t.set_icon("unchecked", "CheckButton", _toggle_icon(false))
	_theme = t
	return t


static func _circle_icon(size: int, c: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


static func _toggle_icon(on: bool) -> ImageTexture:
	var w := 76
	var h := 40
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg := GREEN if on else Color(0.3, 0.25, 0.2)
	var knob_x := w - h / 2.0 if on else h / 2.0
	for y in h:
		for x in w:
			var cx := clampf(x + 0.5, h / 2.0, w - h / 2.0)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - h / 2.0).length()
			var a := clampf(h / 2.0 - d, 0.0, 1.0)
			var col := bg
			var dk := Vector2(x + 0.5 - knob_x, y + 0.5 - h / 2.0).length()
			if dk < h / 2.0 - 4:
				col = CREAM
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


static func label(text: String, size := 26, color := CREAM, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	l.add_theme_constant_override("outline_size", 6)
	if font:
		l.add_theme_font_override("font", font)
	return l


static func button(text: String, cb: Callable, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(func():
		Sfx.play("ui_click", -6.0, 0.0)
		cb.call())
	return b
