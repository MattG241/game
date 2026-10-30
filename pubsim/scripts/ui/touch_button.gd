class_name TouchButton
extends Control
## Multitouch-safe on-screen button drawn in code. Routed by TouchControls.

signal pressed
signal released
signal held_complete

var text := ""
var sub := ""
var color := Color(0.08, 0.3, 0.17, 0.92)
var enabled := true
var hold_seconds := 0.0
var font_size := 26
var round_btn := false
var style := "lacquer"       # "lacquer" (menus, pour), "glass" (HUD) or "accent" (the main action)
var is_down := false
var hold_progress := 0.0
var _touch := -1


func _init(t := "", c := Color(0.08, 0.3, 0.17, 0.92)) -> void:
	text = t
	color = c
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("touch_widget")


func _process(delta: float) -> void:
	if is_down and hold_seconds > 0.0 and enabled:
		hold_progress += delta / hold_seconds
		if hold_progress >= 1.0:
			hold_progress = 0.0
			held_complete.emit()
		queue_redraw()


func touch_down(idx: int, _pos: Vector2) -> void:
	if not enabled:
		return
	_touch = idx
	is_down = true
	hold_progress = 0.0
	pressed.emit()
	GameState.vibrate(10)
	queue_redraw()


func touch_drag(_idx: int, _pos: Vector2) -> void:
	pass


func touch_up(idx: int, _pos: Vector2) -> void:
	if idx != _touch:
		return
	_touch = -1
	is_down = false
	hold_progress = 0.0
	released.emit()
	queue_redraw()


func cancel() -> void:
	_touch = -1
	is_down = false
	hold_progress = 0.0
	queue_redraw()


func set_label(t: String, s := "") -> void:
	if t != text or s != sub:
		text = t
		sub = s
		queue_redraw()


func _draw() -> void:
	if style != "lacquer":
		_draw_modern()
		return
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	var c := color if enabled else Color(0.25, 0.22, 0.2, 0.75)
	if is_down:
		c = c.lightened(0.2)
	sb.bg_color = c
	sb.border_color = Color(0.85, 0.68, 0.35, 0.9) if enabled else Color(0.45, 0.4, 0.35, 0.7)
	sb.set_border_width_all(3)
	var radius := int(minf(size.x, size.y) / 2.0) if round_btn else 20
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 4
	draw_style_box(sb, r)
	if enabled:
		# lacquer sheen on the upper half and a fine inner brass line
		var hi := StyleBoxFlat.new()
		hi.bg_color = Color(1, 1, 1, 0.07 if not is_down else 0.12)
		hi.set_corner_radius_all(maxi(radius - 4, 0))
		hi.corner_radius_bottom_left = 0
		hi.corner_radius_bottom_right = 0
		draw_style_box(hi, Rect2(Vector2(5, 5), Vector2(size.x - 10, size.y * 0.45)))
		var line := StyleBoxFlat.new()
		line.draw_center = false
		line.border_color = Color(0.0, 0.0, 0.0, 0.35)
		line.set_border_width_all(1)
		line.set_corner_radius_all(maxi(radius - 3, 0))
		draw_style_box(line, Rect2(Vector2(4, 4), size - Vector2(8, 8)))
	if hold_progress > 0.0:
		var pr := Rect2(Vector2(6, size.y - 12), Vector2((size.x - 12) * hold_progress, 6))
		draw_rect(pr, UITheme.GOLD)
	var font := MeshKit.font_ui(800)
	var lines := text.split("\n")
	var total_h := lines.size() * font_size * 1.1 + (font_size * 0.8 if sub != "" else 0.0)
	var y := (size.y - total_h) / 2.0 + font_size * 0.85
	for ln in lines:
		draw_string(font, Vector2(8, y), ln, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, font_size, UITheme.CREAM if enabled else UITheme.MUTED)
		y += font_size * 1.1
	if sub != "":
		draw_string(font, Vector2(8, y - font_size * 0.2), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, int(font_size * 0.7), UITheme.GOLD)


## Flat, modern look for the in-game HUD.
func _draw_modern() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	var radius := int(minf(size.x, size.y) / 2.0) if round_btn else 16
	sb.set_corner_radius_all(radius)
	if style == "accent":
		var c := color if enabled else Color(0.2, 0.2, 0.2, 0.6)
		sb.bg_color = c.lightened(0.12) if is_down else c
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = 10
	else:
		sb.bg_color = Color(0.05, 0.045, 0.04, 0.78 if is_down else 0.6)
		sb.border_color = Color(1, 1, 1, 0.16 if enabled else 0.06)
		sb.set_border_width_all(1)
	draw_style_box(sb, r)
	if hold_progress > 0.0:
		draw_rect(Rect2(Vector2(radius * 0.5, size.y - 5), Vector2((size.x - radius) * hold_progress, 3)), UITheme.GOLD)
	var font := MeshKit.font_ui(700)
	var lines := text.split("\n")
	var total_h := lines.size() * font_size * 1.1 + (font_size * 0.75 if sub != "" else 0.0)
	var y := (size.y - total_h) / 2.0 + font_size * 0.85
	var col := Color(1, 0.98, 0.94) if enabled else Color(1, 1, 1, 0.4)
	for ln in lines:
		draw_string(font, Vector2(8, y), ln, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, font_size, col)
		y += font_size * 1.1
	if sub != "":
		draw_string(font, Vector2(8, y - font_size * 0.2), sub.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, int(font_size * 0.6), Color(1, 1, 1, 0.6))
