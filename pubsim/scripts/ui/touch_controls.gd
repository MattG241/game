class_name TouchControls
extends Control
## Routes every finger: on-screen widgets first, then the floating joystick (left) or look (right).

signal look_delta(d: Vector2)

var enabled := true
var gameplay := true            # joystick & look active (false in pour mode)
var move := Vector2.ZERO
var _owners: Dictionary = {}    # touch index -> widget / "joy" / "look"
var _joy_center := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _joy_radius := 90.0
var _last_look: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_press(e.index, e.position)
		else:
			_release(e.index, e.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position, d.relative)


func _widget_at(pos: Vector2) -> Control:
	var best: Control = null
	for w in get_tree().get_nodes_in_group("touch_widget"):
		var c := w as Control
		if c == null or not c.is_visible_in_tree():
			continue
		if c.get_global_rect().grow(6).has_point(pos):
			if best == null or c.z_index >= best.z_index:
				best = c
	return best


func _press(idx: int, pos: Vector2) -> void:
	var w := _widget_at(pos)
	if w:
		_owners[idx] = w
		w.touch_down(idx, pos)
		get_viewport().set_input_as_handled()
		return
	if not gameplay:
		return
	var vp := get_viewport_rect().size
	if pos.x < vp.x * 0.42 and not _owners.values().has("joy"):
		_owners[idx] = "joy"
		_joy_center = pos
		_joy_pos = pos
		move = Vector2.ZERO
	else:
		_owners[idx] = "look"
		_last_look[idx] = pos
	queue_redraw()


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if not _owners.has(idx):
		return
	var o = _owners[idx]
	if o is Control:
		(o as Control).touch_drag(idx, pos)
	elif o == "joy":
		_joy_pos = pos
		var v := (pos - _joy_center) / _joy_radius
		if v.length() > 1.0:
			# drag the base along so the stick never feels stuck
			_joy_center = pos - v.normalized() * _joy_radius
			v = v.normalized()
		move = v
		queue_redraw()
	elif o == "look":
		var last: Vector2 = _last_look.get(idx, pos)
		_last_look[idx] = pos
		look_delta.emit(pos - last)


func _release(idx: int, pos: Vector2) -> void:
	if not _owners.has(idx):
		return
	var o = _owners[idx]
	_owners.erase(idx)
	if o is Control and is_instance_valid(o):
		(o as Control).touch_up(idx, pos)
	elif o == "joy":
		move = Vector2.ZERO
		queue_redraw()
	_last_look.erase(idx)


func reset() -> void:
	for idx in _owners.keys():
		var o = _owners[idx]
		if o is Control and is_instance_valid(o):
			o.cancel()
	_owners.clear()
	_last_look.clear()
	move = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if not gameplay:
		return
	var alpha := float(GameState.settings.get("button_opacity", 0.85))
	if _owners.values().has("joy"):
		draw_circle(_joy_center, _joy_radius, Color(0.05, 0.03, 0.02, 0.35 * alpha))
		draw_arc(_joy_center, _joy_radius, 0, TAU, 48, Color(0.95, 0.8, 0.5, 0.6 * alpha), 3.0)
		var knob := _joy_center + move * _joy_radius
		draw_circle(knob, 38, Color(0.95, 0.76, 0.36, 0.75 * alpha))
	else:
		# idle hint where the stick lives
		var vp := get_viewport_rect().size
		var c := Vector2(170, vp.y - 170)
		draw_arc(c, _joy_radius, 0, TAU, 48, Color(0.95, 0.8, 0.5, 0.25 * alpha), 3.0)
		draw_circle(c, 30, Color(0.95, 0.76, 0.36, 0.22 * alpha))
