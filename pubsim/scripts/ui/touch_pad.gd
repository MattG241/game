class_name TouchPad
extends Control
## Invisible drag surface for mini-games: reports drags, presses and releases from one finger.

signal pressed_at(pos: Vector2)
signal dragged(rel: Vector2)
signal released

var _touch := -1
var _last := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("touch_widget")
	z_index = -1


func touch_down(idx: int, pos: Vector2) -> void:
	if _touch >= 0:
		return
	_touch = idx
	_last = pos
	pressed_at.emit(pos)


func touch_drag(idx: int, pos: Vector2) -> void:
	if idx != _touch:
		return
	dragged.emit(pos - _last)
	_last = pos


func touch_up(idx: int, _pos: Vector2) -> void:
	if idx != _touch:
		return
	_touch = -1
	released.emit()


func cancel() -> void:
	_touch = -1
