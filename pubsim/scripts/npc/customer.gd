class_name Customer
extends Node3D
## A pub customer: walks in, queues, orders, waits, pays, sits, drinks and leaves.

signal left_pub(c: Customer)

const SKIN := [Color(0.95, 0.78, 0.66), Color(0.86, 0.66, 0.5), Color(0.55, 0.38, 0.27), Color(0.36, 0.24, 0.17)]

var world: Node
var display_name := "Customer"
var regular_id := ""
var drink_id := "stout"
var visitor := "local"
var budget := 1              # drinks they intend to have
var drinks_had := 0
var patience_max := 75.0
var patience := 75.0
var tip_mult := 1.0
var state := "enter"
var bar_spot := -1
var seat := -1
var queue_slot := -1
var order_taken := false
var wait_time := 0.0
var satisfaction_sum := 0.0
var served_count := 0
var glass: PintGlass = null
var drink_left := 0.0
var drink_rate := 0.008
var speed := 1.25
var music_enjoy := 0.0
var instrument := ""
var music_style := ""
var _react_anim := 0.0       # >0 while cheering / laughing
var _react_kind := ""
var _audience_return := Vector3.ZERO
var _audience_face := Vector3.ZERO
var beat := 0.5
var _prop: Node3D

var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _after_path := ""
var _anim_t := 0.0
var _sip_t := 0.0
var _sip_phase := 0.0
var _react_t := 0.0
var _seated := false
var _bubble: Label3D
var _name_tag: Label3D
var _body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _head: Node3D
var _right_hand: Node3D
var _seat_yaw := 0.0
var _say_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(w: Node, look: Dictionary, seed_v: int) -> void:
	world = w
	_rng.seed = seed_v
	_build(look)


func _build(look: Dictionary) -> void:
	_body = Node3D.new()
	add_child(_body)
	var height: float = look.get("height", _rng.randf_range(0.93, 1.07))
	_body.scale = Vector3.ONE * height
	var skin: Color = SKIN[int(look.get("skin", _rng.randi() % SKIN.size()))]
	var skin_m := MeshKit.color_mat(skin, 0.65)
	var coat_c: Color
	if look.has("coat"):
		coat_c = Color(look["coat"][0], look["coat"][1], look["coat"][2])
	else:
		coat_c = Color.from_hsv(_rng.randf(), _rng.randf_range(0.25, 0.6), _rng.randf_range(0.2, 0.55))
	var coat_m := MeshKit.color_mat(coat_c, 0.85)
	var trouser_m := MeshKit.color_mat(Color.from_hsv(_rng.randf_range(0.55, 0.65), 0.3, _rng.randf_range(0.1, 0.3)), 0.8)
	var shoe_m := MeshKit.color_mat(Color(0.08, 0.06, 0.05), 0.4)
	var hair_c: Color
	if look.has("hair"):
		hair_c = Color(look["hair"][0], look["hair"][1], look["hair"][2])
	else:
		hair_c = [Color(0.1, 0.07, 0.05), Color(0.3, 0.18, 0.08), Color(0.55, 0.22, 0.08), Color(0.75, 0.6, 0.35), Color(0.6, 0.6, 0.6)][_rng.randi() % 5]
	var hair_m := MeshKit.color_mat(hair_c, 0.8)
	# legs (pivot at hip)
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.09, 0.86, 0)
		_body.add_child(hip)
		MeshKit.capsule(hip, 0.07, 0.82, Vector3(0, -0.41, 0), trouser_m)
		MeshKit.box(hip, Vector3(0.11, 0.07, 0.24), Vector3(0, -0.83, -0.04), shoe_m)
		_legs.append(hip)
	# torso
	var torso := MeshKit.capsule(_body, 0.2, 0.72, Vector3(0, 1.17, 0), coat_m)
	torso.scale = Vector3(1.0, 1.0, 0.72)
	MeshKit.cyl(_body, 0.06, 0.07, 0.08, Vector3(0, 1.5, 0), skin_m, 10)
	# arms (pivot at shoulder)
	for side in [-1, 1]:
		var sh := Node3D.new()
		sh.position = Vector3(side * 0.25, 1.42, 0)
		_body.add_child(sh)
		MeshKit.capsule(sh, 0.06, 0.62, Vector3(0, -0.29, 0), coat_m)
		var hand := MeshKit.sphere(sh, 0.05, Vector3(0, -0.6, 0), skin_m)
		_arms.append(sh)
		if side == 1:
			_right_hand = Node3D.new()
			_right_hand.position = Vector3(0, -0.62, -0.05)
			sh.add_child(_right_hand)
	# head
	_head = Node3D.new()
	_head.position = Vector3(0, 1.66, 0)
	_body.add_child(_head)
	MeshKit.sphere(_head, 0.12, Vector3(0, 0.0, 0), skin_m, Vector3(0.92, 1.05, 0.98))
	MeshKit.sphere(_head, 0.025, Vector3(0, -0.01, -0.12), skin_m)  # nose
	var eye_m := MeshKit.color_mat(Color(0.05, 0.05, 0.05), 0.3)
	for side in [-1, 1]:
		MeshKit.sphere(_head, 0.014, Vector3(side * 0.045, 0.025, -0.105), eye_m)
		MeshKit.sphere(_head, 0.025, Vector3(side * 0.115, 0.0, 0.0), skin_m)  # ears
	MeshKit.box(_head, Vector3(0.05, 0.008, 0.01), Vector3(0, -0.06, -0.112), MeshKit.color_mat(skin.darkened(0.35), 0.6))
	var style: String = look.get("hair_style", ["short", "long", "bob", "messy", "ponytail", "curly", "bald"][_rng.randi() % 7])
	match style:
		"short":
			MeshKit.sphere(_head, 0.128, Vector3(0, 0.035, 0.015), hair_m, Vector3(0.95, 0.75, 1.0))
		"messy", "curly":
			for i in 7:
				var a := TAU * i / 7.0
				MeshKit.sphere(_head, 0.06, Vector3(sin(a) * 0.08, 0.08 + (i % 2) * 0.02, cos(a) * 0.07 + 0.02), hair_m)
		"long":
			MeshKit.sphere(_head, 0.13, Vector3(0, 0.03, 0.02), hair_m, Vector3(1.0, 0.85, 1.0))
			MeshKit.box(_head, Vector3(0.24, 0.3, 0.1), Vector3(0, -0.12, 0.08), hair_m)
		"bob":
			MeshKit.sphere(_head, 0.135, Vector3(0, 0.01, 0.02), hair_m, Vector3(1.0, 0.9, 1.0))
		"ponytail":
			MeshKit.sphere(_head, 0.128, Vector3(0, 0.035, 0.015), hair_m, Vector3(0.95, 0.75, 1.0))
			MeshKit.capsule(_head, 0.035, 0.22, Vector3(0, -0.04, 0.15), hair_m, Vector3(0.4, 0, 0))
		"bun":
			MeshKit.sphere(_head, 0.128, Vector3(0, 0.035, 0.015), hair_m, Vector3(0.95, 0.75, 1.0))
			MeshKit.sphere(_head, 0.055, Vector3(0, 0.1, 0.1), hair_m)
		"bald":
			MeshKit.sphere(_head, 0.124, Vector3(0, -0.01, 0.02), hair_m, Vector3(1.0, 0.55, 1.0))
	if look.get("beard", false):
		MeshKit.sphere(_head, 0.1, Vector3(0, -0.07, -0.04), hair_m, Vector3(1.0, 0.8, 0.8))
	if look.get("cap", false):
		var cap_m := MeshKit.color_mat(Color.from_hsv(_rng.randf(), 0.3, 0.25), 0.9)
		MeshKit.cyl(_head, 0.125, 0.13, 0.07, Vector3(0, 0.09, 0.0), cap_m, 14)
		MeshKit.box(_head, Vector3(0.2, 0.012, 0.1), Vector3(0, 0.065, -0.14), cap_m)
	if look.get("glasses", false):
		var gm := MeshKit.color_mat(Color(0.1, 0.1, 0.1), 0.3, 0.5)
		for side in [-1, 1]:
			MeshKit.torus(_head, 0.022, 0.028, Vector3(side * 0.045, 0.025, -0.115), gm, Vector3(PI / 2, 0, 0))
	# speech bubble & name
	_bubble = Label3D.new()
	_bubble.position = Vector3(0, 2.05 * height, 0)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font = MeshKit.font_ui(800)
	_bubble.font_size = 40
	_bubble.pixel_size = 0.0028
	_bubble.outline_size = 14
	_bubble.outline_modulate = Color(0.05, 0.03, 0.02, 0.9)
	_bubble.width = 600.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.visible = false
	add_child(_bubble)
	_name_tag = Label3D.new()
	_name_tag.position = Vector3(0, 1.9 * height, 0)
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.font = MeshKit.font_ui(600)
	_name_tag.font_size = 28
	_name_tag.pixel_size = 0.0025
	_name_tag.outline_size = 10
	_name_tag.modulate = Color(0.9, 0.85, 0.7, 0.85)
	_name_tag.visible = false
	add_child(_name_tag)


func set_name_tag(text: String) -> void:
	_name_tag.text = text
	_name_tag.visible = text != ""


func say(text: String, seconds := 3.5, color := Color(1, 0.97, 0.9)) -> void:
	_bubble.text = text
	_bubble.modulate = color
	_bubble.visible = true
	_say_t = seconds
	if GameState.settings.get("subtitles", true) and world and world.has_method("subtitle"):
		world.subtitle(display_name, text, self)


func show_bubble(text: String, color: Color) -> void:
	_bubble.text = text
	_bubble.modulate = color
	_bubble.visible = true
	_say_t = 0.0


func hide_bubble() -> void:
	_bubble.visible = false


func walk_to(target: Vector3, then_state: String) -> void:
	_path = world.nav_path(global_position, target)
	if _path.is_empty():
		_path = PackedVector3Array([target])
	_path_i = 0
	_after_path = then_state
	state = "walk"
	_set_seated(false)


func _process(delta: float) -> void:
	_anim_t += delta
	if _say_t > 0.0:
		_say_t -= delta
		if _say_t <= 0.0:
			_refresh_bubble()
	match state:
		"walk":
			_walk(delta)
		"queue":
			_tick_patience(delta, 0.6)
			var spot: int = world.request_bar_spot(self)
			if spot >= 0:
				world.release_queue_slot(self)
				bar_spot = spot
				walk_to(world.bar_spot_pos(spot), "wait_order")
		"wait_order", "wait_drink":
			_face_yaw(PI, delta)
			_tick_patience(delta, 1.0 if state == "wait_order" else 0.85)
			_idle_anim(delta)
		"react":
			_react_t -= delta
			_idle_anim(delta)
			if _react_t <= 0.0:
				_after_served()
		"drinking":
			_drinking(delta)
		"stand_drink":
			_drinking(delta)
		"musician":
			_play_anim(delta)
		"audience":
			_audience_anim(delta)
		_:
			_idle_anim(delta)


func _walk(delta: float) -> void:
	if _path_i >= _path.size():
		_arrive()
		return
	var target := _path[_path_i]
	target.y = global_position.y
	var to := target - global_position
	var dist := to.length()
	if dist < 0.08:
		_path_i += 1
		return
	var step := minf(dist, speed * delta)
	global_position += to / dist * step
	var yaw := atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, delta * 8.0))
	var sw := sin(_anim_t * 7.5) * 0.45
	_legs[0].rotation.x = sw
	_legs[1].rotation.x = -sw
	_arms[0].rotation.x = -sw * 0.6
	_arms[1].rotation.x = sw * 0.6 if glass == null else -0.5
	_body.position.y = absf(cos(_anim_t * 7.5)) * 0.025


func _arrive() -> void:
	_legs[0].rotation.x = 0
	_legs[1].rotation.x = 0
	_arms[0].rotation.x = 0
	_arms[1].rotation.x = 0 if glass == null else -0.5
	_body.position.y = 0
	var next := _after_path
	_after_path = ""
	match next:
		"choose":
			world.customer_choose(self)
		"wait_order":
			state = "wait_order"
			rotation.y = PI
			if world.has_method("on_customer_at_bar"):
				world.on_customer_at_bar(self)
			_refresh_bubble()
		"queue":
			state = "queue"
			_refresh_bubble()
		"seated":
			state = "drinking"
			rotation.y = _seat_yaw
			_set_seated(true)
			_place_glass_on_table()
		"audience":
			state = "audience"
		"exit":
			state = "gone"
			left_pub.emit(self)
			queue_free()
		_:
			state = next if next != "" else "idle"


func _idle_anim(delta: float) -> void:
	var base_y := -0.4 if _seated else 0.0
	_body.position.y = base_y + sin(_anim_t * 1.3) * 0.005
	_head.rotation.y = sin(_anim_t * 0.4) * 0.25
	if music_enjoy > 0.0:
		var speed := 7.0 if music_style == "dance" else 5.0
		_head.rotation.x = sin(_anim_t * speed) * 0.08 * music_enjoy
		_body.rotation.z = sin(_anim_t * speed * 0.3) * 0.04 * music_enjoy
		if _seated and music_style in ["dance", "sing"]:
			_legs[1].rotation.x = -1.45 + maxf(0.0, sin(_anim_t * speed)) * 0.15  # tapping a foot
	else:
		_body.rotation.z = 0.0
	_apply_reaction(delta)


func _face_yaw(yaw: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, delta * 6.0))


func _tick_patience(delta: float, rate: float) -> void:
	wait_time += delta
	patience -= delta * rate * world.patience_drain()
	if patience <= 0.0:
		_walk_out()
	elif patience < patience_max * 0.35 and int(_anim_t * 10) % 120 == 0 and _say_t <= 0.0:
		say(world.line("waiting"), 2.5, Color(1, 0.8, 0.4))
	else:
		_refresh_bubble_color()


func _refresh_bubble() -> void:
	match state:
		"wait_order":
			show_bubble("!", Color(1.0, 0.85, 0.3))
		"queue":
			show_bubble("...", Color(0.9, 0.9, 0.9))
		"wait_drink":
			show_bubble(GameData.drink(drink_id).get("short", drink_id), Color(1, 1, 1))
		_:
			hide_bubble()
	_refresh_bubble_color()


func _refresh_bubble_color() -> void:
	if state in ["wait_order", "wait_drink", "queue"] and _say_t <= 0.0:
		var f := clampf(patience / patience_max, 0.0, 1.0)
		var c := Color(1.0, 0.35, 0.25).lerp(Color(0.55, 1.0, 0.55), f)
		_bubble.modulate = c


func patience_frac() -> float:
	return clampf(patience / patience_max, 0.0, 1.0)


func _walk_out() -> void:
	say(world.line("angry"), 3.0, Color(1, 0.5, 0.4))
	world.on_walkout(self)
	leave()


func take_order() -> String:
	order_taken = true
	state = "wait_drink"
	patience = minf(patience_max, patience + patience_max * 0.15)
	var line: String = world.order_line(self)
	say(line, 4.0)
	return line


## Called by the world when the player hands over a drink.
func receive_drink(g: PintGlass) -> void:
	glass = g
	if g.get_parent():
		g.get_parent().remove_child(g)
	_right_hand.add_child(g)
	g.position = Vector3.ZERO
	g.rotation = Vector3.ZERO
	_arms[1].rotation.x = -0.5
	served_count += 1
	drinks_had += 1
	drink_left = 1.0
	state = "react"
	_react_t = 2.2
	hide_bubble()


func refuse_drink(text: String) -> void:
	say(text, 3.0, Color(1, 0.7, 0.4))


func _after_served() -> void:
	world.release_bar_spot(self)
	bar_spot = -1
	var s: int = world.request_seat(self)
	if s >= 0:
		seat = s
		var sd: Dictionary = world.seat_info(s)
		_seat_yaw = sd["yaw"]
		walk_to(sd["pos"], "seated")
	else:
		state = "stand_drink"
		var p: Vector3 = world.standing_spot(self)
		walk_to(p, "stand_drink")


func _set_seated(on: bool) -> void:
	_seated = on
	if on:
		_body.position.y = -0.4
		for leg in _legs:
			leg.rotation.x = -1.45
	else:
		_body.position.y = 0.0
		for leg in _legs:
			leg.rotation.x = 0.0


func _place_glass_on_table() -> void:
	if glass == null or seat < 0:
		return
	var sd: Dictionary = world.seat_info(seat)
	var tp: Vector3 = sd["table"]
	_right_hand.remove_child(glass)
	world.add_child(glass)
	glass.global_position = tp
	glass.rotation = Vector3.ZERO
	_arms[1].rotation.x = 0.0


func _drinking(delta: float) -> void:
	_idle_anim(delta)
	if glass == null:
		_finish_drink()
		return
	drink_left -= delta * drink_rate * world.drink_speed_mult()
	var c := glass.contents
	var lvl := maxf(0.0, drink_left)
	# drinking takes the liquid first; the head thins and leaves lacing on the glass
	if c.total() > 0.0:
		c.cascade = 0.0
		c.body = maxf(0.0, lvl * 0.88)
		if lvl < 0.08:
			c.foam *= 0.97
		glass.lace_top = maxf(glass.lace_top, minf(c.total(), 1.0))
	_sip_t -= delta
	if _sip_t <= 0.0:
		_sip_t = _rng.randf_range(7.0, 14.0)
		_sip_phase = 2.4
	if _sip_phase > 0.0:
		_sip_phase -= delta
		var k := sin(clampf(1.0 - _sip_phase / 2.4, 0.0, 1.0) * PI)
		if _seated and glass.get_parent() != _right_hand:
			glass.get_parent().remove_child(glass)
			_right_hand.add_child(glass)
			glass.position = Vector3.ZERO
			glass.rotation = Vector3.ZERO
		_arms[1].rotation.x = -0.5 - k * 1.7
		_arms[1].rotation.z = k * 0.35
		glass.rotation.x = k * 0.9
		if _sip_phase <= 0.0:
			_arms[1].rotation.x = -0.5
			_arms[1].rotation.z = 0.0
			glass.rotation.x = 0.0
			if _seated:
				_place_glass_on_table()
	if drink_left <= 0.0:
		_finish_drink()


func _finish_drink() -> void:
	if glass:
		glass.contents.reset()
		glass.set_dirty(0.75)
		var pos: Vector3
		if seat >= 0:
			pos = world.seat_info(seat)["table"]
		else:
			pos = world.nearest_ledge(global_position)
		if glass.get_parent():
			glass.get_parent().remove_child(glass)
		world.leave_dirty_glass(glass, pos)
		glass = null
	_arms[1].rotation = Vector3.ZERO
	if drinks_had < budget and world.can_reorder(self):
		var s := seat
		seat = -1
		if s >= 0:
			world.release_seat(s)
		order_taken = false
		patience = patience_max
		drink_id = world.pick_drink(self)
		world.customer_choose(self)
	else:
		leave()


func leave() -> void:
	if bar_spot >= 0:
		world.release_bar_spot(self)
		bar_spot = -1
	if queue_slot >= 0:
		world.release_queue_slot(self)
	if seat >= 0:
		world.release_seat(seat)
		seat = -1
	if glass:
		# walked out holding a drink: leave it behind on the nearest ledge
		var g := glass
		glass = null
		g.contents.reset()
		g.set_dirty(0.75)
		if g.get_parent():
			g.get_parent().remove_child(g)
		world.leave_dirty_glass(g, world.nearest_ledge(global_position))
	if served_count > 0 and _rng.randf() < 0.5:
		say(world.line("leave"), 2.5)
	walk_to(world.exit_point(self), "exit")
	state = "walk"
	_after_path = "exit"


func apply_music(level: float, style := "sway") -> void:
	music_enjoy = level
	music_style = style


func cheer() -> void:
	_react_kind = "cheer"
	_react_anim = 1.6


func laugh() -> void:
	_react_kind = "laugh"
	_react_anim = 2.0


## Leaves the seat (keeping it) to stand, dance or sing in front of the musicians.
func join_audience(pos: Vector3, style: String, face: Vector3) -> void:
	if glass and glass.get_parent() != _right_hand:
		var gp := glass.get_parent()
		if gp:
			gp.remove_child(glass)
		_right_hand.add_child(glass)
		glass.position = Vector3.ZERO
		glass.rotation = Vector3.ZERO
	_audience_return = global_position
	_audience_face = face
	music_style = style
	walk_to(pos, "audience")


func leave_audience() -> void:
	_body.rotation = Vector3.ZERO
	_arms[0].rotation = Vector3.ZERO
	_arms[1].rotation = Vector3(-0.5, 0, 0)
	if seat >= 0:
		var sd: Dictionary = world.seat_info(seat)
		_seat_yaw = sd["yaw"]
		walk_to(sd["pos"], "seated")
	else:
		walk_to(_audience_return, "stand_drink")


func _audience_anim(delta: float) -> void:
	var to := _audience_face - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 4.0))
	var t := _anim_t
	match music_style:
		"dance":
			# a lively step: hops, alternating arms and a turn now and then
			_body.position.y = absf(sin(t * 5.0)) * 0.08
			_legs[0].rotation.x = sin(t * 5.0) * 0.6
			_legs[1].rotation.x = -sin(t * 5.0) * 0.6
			_arms[0].rotation = Vector3(-0.3, 0, -0.5 - 0.3 * sin(t * 2.5))
			_arms[1].rotation = Vector3(-0.6, 0, 0.4)
			_body.rotation.y = sin(t * 0.9) * 0.6
		"sing":
			# glass raised, swaying with the crowd
			_body.rotation.z = sin(t * 1.6) * 0.08
			_arms[1].rotation = Vector3(-2.6, 0, 0.25)
			_arms[0].rotation = Vector3(-0.2, 0, -0.9 - 0.2 * sin(t * 1.6))
			_head.rotation.x = -0.25
			_body.position.y = absf(sin(t * 3.2)) * 0.02
		_:
			_head.rotation.x = sin(t * 5.0) * 0.08
			_body.rotation.z = sin(t * 1.4) * 0.05
	_apply_reaction(delta)


func _apply_reaction(delta: float) -> void:
	if _react_anim <= 0.0:
		return
	_react_anim -= delta
	if _react_kind == "cheer":
		_arms[0].rotation = Vector3(-2.8, 0, -0.3)
		if not glass or state == "audience":
			_arms[1].rotation = Vector3(-2.6, 0, 0.3)
	elif _react_kind == "laugh":
		_head.rotation.x = -0.3 + sin(_react_anim * 22.0) * 0.08
		_body.position.y += absf(sin(_react_anim * 18.0)) * 0.01
	if _react_anim <= 0.0 and state != "audience":
		_arms[0].rotation = Vector3.ZERO
		if _sip_phase <= 0.0:
			_arms[1].rotation = Vector3(-0.5, 0, 0) if (glass and glass.get_parent() == _right_hand) else Vector3.ZERO


## Turns this character into a seated musician holding an instrument.
func make_musician(kind: String, beat_s: float) -> void:
	state = "musician"
	instrument = kind
	beat = maxf(beat_s, 0.2)
	_set_seated(true)
	_bubble.visible = false
	_prop = Node3D.new()
	_body.add_child(_prop)
	var wood := MeshKit.color_mat(Color(0.45, 0.2, 0.07), 0.35)
	var dark := MeshKit.color_mat(Color(0.1, 0.06, 0.03), 0.5)
	match kind:
		"fiddle":
			_prop.position = Vector3(-0.08, 1.48, -0.18)
			_prop.rotation = Vector3(0.3, 0.5, 0.6)
			var b := MeshKit.sphere(_prop, 0.09, Vector3.ZERO, wood, Vector3(0.7, 0.25, 1.0))
			MeshKit.box(_prop, Vector3(0.02, 0.02, 0.25), Vector3(0, 0.0, -0.2), dark)
			var bow := MeshKit.cyl(_right_hand, 0.004, 0.004, 0.6, Vector3(0.0, 0.0, 0.0), MeshKit.color_mat(Color(0.3, 0.2, 0.1), 0.5), 6, Vector3(0, 0, PI / 2.0))
			_arms[0].rotation = Vector3(-1.6, 0, -0.5)
			_arms[1].rotation = Vector3(-1.1, 0, 0.3)
		"whistle":
			_prop.position = Vector3(0, 1.58, -0.2)
			_prop.rotation = Vector3(1.1, 0, 0)
			MeshKit.cyl(_prop, 0.01, 0.01, 0.28, Vector3.ZERO, MeshKit.color_mat(Color(0.75, 0.75, 0.7), 0.25, 0.8), 8)
			_arms[0].rotation = Vector3(-1.5, 0, -0.3)
			_arms[1].rotation = Vector3(-1.3, 0, 0.3)
		"bodhran":
			_prop.position = Vector3(-0.12, 1.15, -0.28)
			_prop.rotation = Vector3(PI / 2.0 - 0.3, 0, 0.2)
			MeshKit.cyl(_prop, 0.22, 0.22, 0.07, Vector3.ZERO, MeshKit.color_mat(Color(0.85, 0.75, 0.55), 0.7), 20)
			MeshKit.torus(_prop, 0.2, 0.225, Vector3(0, 0.0, 0), wood)
			MeshKit.cyl(_right_hand, 0.008, 0.008, 0.2, Vector3.ZERO, wood, 6, Vector3(PI / 2.0, 0, 0))
			_arms[0].rotation = Vector3(-0.9, 0, -0.4)
		"accordion":
			_prop.position = Vector3(0, 1.12, -0.26)
			MeshKit.box(_prop, Vector3(0.12, 0.3, 0.2), Vector3(-0.17, 0, 0), MeshKit.color_mat(Color(0.6, 0.08, 0.08), 0.3))
			MeshKit.box(_prop, Vector3(0.12, 0.3, 0.2), Vector3(0.17, 0, 0), MeshKit.color_mat(Color(0.6, 0.08, 0.08), 0.3))
			var bellows := MeshKit.box(_prop, Vector3(0.22, 0.28, 0.18), Vector3.ZERO, MeshKit.color_mat(Color(0.1, 0.1, 0.1), 0.6))
			bellows.name = "Bellows"
			_arms[0].rotation = Vector3(-0.9, 0, -0.3)
			_arms[1].rotation = Vector3(-0.9, 0, 0.3)
		"guitar", "banjo":
			_prop.position = Vector3(0.0, 1.0, -0.2)
			_prop.rotation = Vector3(0, 0, 0.9)
			if kind == "guitar":
				MeshKit.sphere(_prop, 0.17, Vector3(0, -0.05, 0), wood, Vector3(1.0, 1.25, 0.4))
			else:
				MeshKit.cyl(_prop, 0.14, 0.14, 0.06, Vector3(0, -0.05, 0), MeshKit.color_mat(Color(0.9, 0.88, 0.8), 0.5), 20, Vector3(PI / 2.0, 0, 0))
			MeshKit.box(_prop, Vector3(0.04, 0.5, 0.025), Vector3(0, 0.33, 0), dark)
			_arms[0].rotation = Vector3(-1.2, 0, -0.6)
			_arms[1].rotation = Vector3(-0.7, 0, 0.2)


func _play_anim(_delta: float) -> void:
	var ph := _anim_t / beat * TAU
	_body.position.y = -0.4 + absf(sin(ph * 0.5)) * 0.012
	_head.rotation.x = sin(ph * 0.5) * 0.08
	_legs[0].rotation.x = -1.45 + maxf(0.0, sin(ph)) * 0.12  # foot tapping
	match instrument:
		"fiddle":
			_arms[1].rotation.z = 0.3 + sin(ph * 0.5) * 0.45
			_head.rotation.z = 0.25
		"whistle":
			_head.rotation.x = -0.1 + sin(ph * 0.5) * 0.05
		"bodhran":
			_arms[1].rotation.x = -1.1 + absf(sin(ph * 0.5)) * 0.6
		"accordion":
			var b := _prop.get_node_or_null("Bellows") as Node3D
			if b:
				b.scale.x = 1.0 + 0.6 * sin(ph * 0.125)
			_prop.get_child(0).position.x = -0.17 - 0.06 * sin(ph * 0.125)
			_prop.get_child(1).position.x = 0.17 + 0.06 * sin(ph * 0.125)
		"guitar", "banjo":
			_arms[1].rotation.x = -0.7 + sin(ph) * 0.25
