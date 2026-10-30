class_name TouchSlider
extends Control
## Vertical drag control (glass tilt, tap handle). value 0..1, bottom to top unless inverted.

signal changed(v: float)

var value := 0.0
var title := ""
var spring_back := false     # tap handles close when released
var inverted := false        # true: drag DOWN increases the value (pulling a handle)
var target_band := Vector2(-1, -1)
var marker_text := ""
var readout := ""
var accent := Color(0.95, 0.76, 0.36)
var _touch := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("touch_widget")


func _value_from(pos: Vector2) -> float:
	var local := pos - global_position
	var t := clampf((local.y - 40.0) / maxf(1.0, size.y - 80.0), 0.0, 1.0)
	return t if inverted else 1.0 - t


func touch_down(idx: int, pos: Vector2) -> void:
	_touch = idx
	value = _value_from(pos)
	changed.emit(value)
	queue_redraw()


func touch_drag(idx: int, pos: Vector2) -> void:
	if idx != _touch:
		return
	value = _value_from(pos)
	changed.emit(value)
	queue_redraw()


func touch_up(idx: int, _pos: Vector2) -> void:
	if idx != _touch:
		return
	_touch = -1
	if spring_back:
		value = 0.0
		changed.emit(value)
	queue_redraw()


func cancel() -> void:
	_touch = -1
	if spring_back:
		value = 0.0
		changed.emit(value)
	queue_redraw()


func is_held() -> bool:
	return _touch >= 0


func set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var font := MeshKit.font_ui(800)
	var track := Rect2(Vector2(size.x / 2.0 - 22, 40), Vector2(44, size.y - 80))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.045, 0.04, 0.6)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(22)
	draw_style_box(sb, track)
	if target_band.x >= 0.0:
		var y0 := _y_for(target_band.y)
		var y1 := _y_for(target_band.x)
		draw_rect(Rect2(Vector2(track.position.x + 4, minf(y0, y1)), Vector2(track.size.x - 8, absf(y1 - y0))), Color(0.3, 0.8, 0.4, 0.45))
		if marker_text != "":
			draw_string(font, Vector2(track.end.x + 6, (y0 + y1) / 2.0 + 8), marker_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 1, 0.65))
	var fy := _y_for(value)
	var fill_top := minf(fy, _y_for(0.0))
	var fill := Rect2(Vector2(track.position.x + 6, fill_top), Vector2(track.size.x - 12, absf(_y_for(0.0) - fy)))
	draw_rect(fill, Color(accent.r, accent.g, accent.b, 0.35))
	var knob := Rect2(Vector2(size.x / 2.0 - 46, fy - 26), Vector2(92, 52))
	var kb := StyleBoxFlat.new()
	kb.bg_color = accent if _touch >= 0 else accent.darkened(0.2)
	kb.set_corner_radius_all(18)
	kb.shadow_color = Color(0, 0, 0, 0.3)
	kb.shadow_size = 8
	draw_style_box(kb, knob)
	draw_string(font, Vector2(0, 28), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Color(1, 0.97, 0.9, 0.8))
	if readout != "":
		draw_string(font, Vector2(knob.position.x, fy + 9), readout, HORIZONTAL_ALIGNMENT_CENTER, knob.size.x, 22, Color(0.1, 0.06, 0.03))


func _y_for(v: float) -> float:
	var t := v if inverted else 1.0 - v
	return 40.0 + t * (size.y - 80.0)
