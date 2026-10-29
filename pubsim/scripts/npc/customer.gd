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
var ordering := false        # sent up to the bar by the order dispatcher
var mingle_t := 0.0
var order_time := -1.0      # world.run_time when the order was taken
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
var _legs: Array[Node3D] = []     # hip joints
var _arms: Array[Node3D] = []     # shoulder joints
var _knees: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _hands: Array[Node3D] = []
var _mouth: Node3D
var _jaw_lip: MeshInstance3D
var _talk_left := 0.0
var gender := "m"
var voice := ""
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
	gender = str(look.get("gender", "f" if _rng.randf() < 0.45 else "m"))
	var fem := gender == "f"
	_body = Node3D.new()
	add_child(_body)
	var height: float = look.get("height", _rng.randf_range(0.93, 1.07) * (0.95 if fem else 1.0))
	_body.scale = Vector3.ONE * height
	var skin: Color = SKIN[int(look.get("skin", _rng.randi() % SKIN.size()))]
	var skin_m := MeshKit.color_mat(skin, 0.62)
	var coat_c: Color
	if look.has("coat"):
		coat_c = Color(look["coat"][0], look["coat"][1], look["coat"][2])
	else:
		coat_c = Color.from_hsv(_rng.randf(), _rng.randf_range(0.25, 0.6), _rng.randf_range(0.2, 0.55))
	var coat_m := MeshKit.color_mat(coat_c, 0.9)
	var coat_dark := MeshKit.color_mat(coat_c.darkened(0.25), 0.9)
	var shirt_c: Color = [Color(0.92, 0.9, 0.85), Color(0.75, 0.82, 0.9), Color(0.85, 0.8, 0.7), Color(0.3, 0.32, 0.36)][_rng.randi() % 4]
	var shirt_m := MeshKit.color_mat(shirt_c, 0.8)
	var trouser_m := MeshKit.color_mat(Color.from_hsv(_rng.randf_range(0.55, 0.65), 0.3, _rng.randf_range(0.1, 0.3)), 0.85)
	var shoe_m := MeshKit.color_mat(Color(0.08, 0.06, 0.05), 0.35)
	var hair_c: Color
	if look.has("hair"):
		hair_c = Color(look["hair"][0], look["hair"][1], look["hair"][2])
	else:
		hair_c = [Color(0.1, 0.07, 0.05), Color(0.3, 0.18, 0.08), Color(0.55, 0.22, 0.08), Color(0.75, 0.6, 0.35), Color(0.6, 0.6, 0.6)][_rng.randi() % 5]
	var hair_m := MeshKit.color_mat(hair_c, 0.75)
	var skirt: bool = fem and bool(look.get("skirt", _rng.randf() < 0.4))
	var jumper: bool = bool(look.get("jumper", _rng.randf() < (0.5 if fem else 0.3)))
	var leg_m: Material = MeshKit.color_mat(Color(0.12, 0.1, 0.1), 0.6) if skirt else trouser_m
	var hip_w := 0.1 if fem else 0.09
	var sh_w := 0.21 if fem else 0.25
	# legs: thigh from the hip, shin from the knee
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(side * hip_w, 0.86, 0)
		_body.add_child(hip)
		MeshKit.capsule(hip, 0.078, 0.46, Vector3(0, -0.21, 0), leg_m)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.42, 0)
		hip.add_child(knee)
		MeshKit.capsule(knee, 0.064, 0.44, Vector3(0, -0.2, 0), leg_m)
		MeshKit.box(knee, Vector3(0.1, 0.07, 0.2), Vector3(0, -0.41, -0.04), shoe_m)
		MeshKit.sphere(knee, 0.05, Vector3(0, -0.415, -0.12), shoe_m, Vector3(1.0, 0.65, 1.0))
		MeshKit.merge_children(knee, "Shin")
		MeshKit.merge_children(hip, "Thigh")
		_legs.append(hip)
		_knees.append(knee)
	# torso: tapered body, shirt front, lapels or a knitted collar, belt or skirt
	var torso_mesh := _torso_mesh(fem)
	var torso := MeshInstance3D.new()
	torso.mesh = torso_mesh
	torso.material_override = coat_m
	torso.scale = Vector3(1.0, 1.0, 0.72)
	_body.add_child(torso)
	if jumper:
		MeshKit.torus(_body, 0.055, 0.085, Vector3(0, 1.49, 0), coat_dark)
		for i in 4:
			MeshKit.box(_body, Vector3(0.012, 0.3, 0.012), Vector3(-0.06 + i * 0.04, 1.2, -0.145), coat_dark)  # cable knit
	else:
		MeshKit.box(_body, Vector3(0.1, 0.26, 0.01), Vector3(0, 1.33, -0.146), shirt_m)
		for side in [-1, 1]:
			MeshKit.box(_body, Vector3(0.065, 0.3, 0.012), Vector3(side * 0.058, 1.3, -0.15), coat_dark, Vector3(0, 0, side * 0.28))
		MeshKit.sphere(_body, 0.012, Vector3(0, 1.12, -0.147), MeshKit.color_mat(Color(0.2, 0.16, 0.1), 0.4))
	if skirt:
		MeshKit.cyl(_body, 0.19, 0.26, 0.42, Vector3(0, 0.7, 0), coat_dark, 14)
	else:
		MeshKit.cyl(_body, 0.172, 0.172, 0.04, Vector3(0, 0.9, 0), MeshKit.color_mat(Color(0.12, 0.08, 0.05), 0.4), 14)
	MeshKit.cyl(_body, 0.055, 0.065, 0.09, Vector3(0, 1.52, 0), skin_m, 10)
	MeshKit.merge_children(_body, "Torso")
	# arms: upper arm from the shoulder, forearm from the elbow, a hand that holds the glass
	for side in [-1, 1]:
		var sh := Node3D.new()
		sh.position = Vector3(side * sh_w, 1.42, 0)
		_body.add_child(sh)
		MeshKit.sphere(sh, 0.07, Vector3.ZERO, coat_m)
		MeshKit.capsule(sh, 0.062, 0.34, Vector3(0, -0.15, 0), coat_m)
		var el := Node3D.new()
		el.position = Vector3(0, -0.3, 0)
		sh.add_child(el)
		MeshKit.capsule(el, 0.055, 0.3, Vector3(0, -0.13, 0), coat_m)
		MeshKit.cyl(el, 0.052, 0.05, 0.03, Vector3(0, -0.27, 0), shirt_m if not jumper else coat_dark, 10)
		MeshKit.sphere(el, 0.045, Vector3(0, -0.325, -0.008), skin_m, Vector3(0.75, 1.0, 1.0))
		MeshKit.sphere(el, 0.018, Vector3(side * -0.03, -0.31, -0.03), skin_m)  # thumb
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.33, -0.05)
		el.add_child(hand)
		MeshKit.merge_children(el, "Forearm")
		MeshKit.merge_children(sh, "UpperArm")
		_arms.append(sh)
		_elbows.append(el)
		_hands.append(hand)
		if side == 1:
			_right_hand = hand
	# head: face with eyes, brows, nose, ears and a mouth that moves when they talk
	_head = Node3D.new()
	_head.position = Vector3(0, 1.68, 0)
	_body.add_child(_head)
	MeshKit.sphere(_head, 0.118, Vector3(0, 0.01, 0), skin_m, Vector3(0.9, 1.06, 0.98))
	MeshKit.sphere(_head, 0.085, Vector3(0, -0.055, -0.03), skin_m, Vector3(1.0, 0.8, 1.0) if fem else Vector3(1.08, 0.85, 1.0))  # jaw
	MeshKit.sphere(_head, 0.024, Vector3(0, -0.005, -0.118), skin_m, Vector3(0.8, 1.2, 1.0))  # nose
	MeshKit.sphere(_head, 0.014, Vector3(0, -0.03, -0.125), skin_m)
	var white_m := MeshKit.color_mat(Color(0.95, 0.94, 0.9), 0.3)
	var iris_m := MeshKit.color_mat([Color(0.25, 0.4, 0.6), Color(0.3, 0.2, 0.1), Color(0.3, 0.45, 0.3), Color(0.15, 0.1, 0.07)][_rng.randi() % 4], 0.2)
	for side in [-1, 1]:
		MeshKit.sphere(_head, 0.017, Vector3(side * 0.042, 0.025, -0.098), white_m)
		MeshKit.sphere(_head, 0.009, Vector3(side * 0.042, 0.025, -0.112), iris_m)
		MeshKit.box(_head, Vector3(0.04, 0.008, 0.012), Vector3(side * 0.043, 0.052, -0.108), hair_m, Vector3(0, 0, side * -0.12))  # brows
		MeshKit.sphere(_head, 0.024, Vector3(side * 0.11, 0.005, 0.0), skin_m, Vector3(0.5, 1.0, 0.8))  # ears
	_mouth = Node3D.new()
	_mouth.position = Vector3(0, -0.058, -0.106)
	_head.add_child(_mouth)
	var lip_m := MeshKit.color_mat(skin.darkened(0.3).lerp(Color(0.6, 0.25, 0.25), 0.35 if fem else 0.15), 0.5)
	MeshKit.box(_mouth, Vector3(0.046, 0.009, 0.012), Vector3(0, 0.005, 0), lip_m)
	_jaw_lip = MeshKit.box(_mouth, Vector3(0.042, 0.009, 0.012), Vector3(0, -0.005, 0), lip_m)
	MeshKit.box(_mouth, Vector3(0.036, 0.012, 0.004), Vector3(0, 0.0, 0.004), MeshKit.color_mat(Color(0.15, 0.05, 0.05), 0.8))
	var styles_f := ["long", "bob", "ponytail", "bun", "curly", "long"]
	var styles_m := ["short", "short", "messy", "curly", "bald", "short"]
	var style: String = look.get("hair_style", (styles_f if fem else styles_m)[_rng.randi() % 6])
	match style:
		"short":
			MeshKit.sphere(_head, 0.125, Vector3(0, 0.045, 0.015), hair_m, Vector3(0.95, 0.72, 1.0))
		"messy", "curly":
			MeshKit.sphere(_head, 0.122, Vector3(0, 0.04, 0.02), hair_m, Vector3(0.95, 0.75, 1.0))
			for i in 8:
				var a := TAU * i / 8.0
				MeshKit.sphere(_head, 0.05, Vector3(sin(a) * 0.085, 0.09 + (i % 2) * 0.02, cos(a) * 0.075 + 0.02), hair_m)
		"long":
			MeshKit.sphere(_head, 0.128, Vector3(0, 0.035, 0.02), hair_m, Vector3(1.0, 0.85, 1.0))
			MeshKit.box(_head, Vector3(0.23, 0.3, 0.09), Vector3(0, -0.12, 0.075), hair_m)
			for side in [-1, 1]:
				MeshKit.box(_head, Vector3(0.04, 0.22, 0.08), Vector3(side * 0.105, -0.07, 0.0), hair_m)
		"bob":
			MeshKit.sphere(_head, 0.133, Vector3(0, 0.015, 0.02), hair_m, Vector3(1.0, 0.9, 1.0))
		"ponytail":
			MeshKit.sphere(_head, 0.125, Vector3(0, 0.045, 0.015), hair_m, Vector3(0.95, 0.72, 1.0))
			MeshKit.capsule(_head, 0.035, 0.22, Vector3(0, -0.04, 0.15), hair_m, Vector3(0.4, 0, 0))
		"bun":
			MeshKit.sphere(_head, 0.125, Vector3(0, 0.045, 0.015), hair_m, Vector3(0.95, 0.72, 1.0))
			MeshKit.sphere(_head, 0.055, Vector3(0, 0.1, 0.1), hair_m)
		"bald":
			MeshKit.sphere(_head, 0.121, Vector3(0, -0.005, 0.03), hair_m, Vector3(1.0, 0.5, 1.0))
	if look.get("beard", (not fem) and _rng.randf() < 0.3):
		MeshKit.sphere(_head, 0.092, Vector3(0, -0.075, -0.035), hair_m, Vector3(1.0, 0.75, 0.85))
	if look.get("cap", (not fem) and _rng.randf() < 0.15):
		var cap_m := MeshKit.color_mat(Color.from_hsv(_rng.randf(), 0.3, 0.25), 0.9)
		MeshKit.cyl(_head, 0.124, 0.128, 0.07, Vector3(0, 0.1, 0.0), cap_m, 14)
		MeshKit.box(_head, Vector3(0.2, 0.012, 0.1), Vector3(0, 0.075, -0.14), cap_m)
	if look.get("glasses", _rng.randf() < 0.15):
		var gm := MeshKit.color_mat(Color(0.1, 0.1, 0.1), 0.3, 0.5)
		for side in [-1, 1]:
			MeshKit.torus(_head, 0.02, 0.026, Vector3(side * 0.042, 0.025, -0.118), gm, Vector3(PI / 2, 0, 0))
	MeshKit.merge_children(_head, "Head")
	_relax_pose()
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


static var _torso_meshes := {}


static func _torso_mesh(fem: bool) -> ArrayMesh:
	var key := "f" if fem else "m"
	if not _torso_meshes.has(key):
		var prof: PackedVector2Array
		if fem:
			prof = PackedVector2Array([Vector2(0.0, 0.84), Vector2(0.185, 0.85), Vector2(0.2, 0.95), Vector2(0.158, 1.1),
				Vector2(0.18, 1.27), Vector2(0.185, 1.38), Vector2(0.13, 1.47), Vector2(0.06, 1.51), Vector2(0.0, 1.515)])
		else:
			prof = PackedVector2Array([Vector2(0.0, 0.84), Vector2(0.172, 0.85), Vector2(0.18, 0.96), Vector2(0.19, 1.12),
				Vector2(0.215, 1.3), Vector2(0.21, 1.4), Vector2(0.14, 1.48), Vector2(0.065, 1.515), Vector2(0.0, 1.52)])
		_torso_meshes[key] = MeshKit.lathe(prof, 18, false)
	return _torso_meshes[key]


func _relax_pose() -> void:
	for e in _elbows:
		e.rotation = Vector3(-0.12, 0, 0)


## Starts the mouth moving for a spoken line.
func talk_for(seconds: float) -> void:
	_talk_left = seconds


## Knees and elbows follow the hips and shoulders, so every existing pose gets natural joints:
## the back leg bends when walking, shins hang when seated, a held glass stays upright.
func _solve_joints(delta: float) -> void:
	for i in _legs.size():
		var hx := _legs[i].rotation.x
		var bend := maxf(0.0, hx) * 1.1 + 0.04
		if hx < -1.0:
			bend = -hx  # seated: shins hang straight down
		_knees[i].rotation.x = bend
	for i in _arms.size():
		var sx := _arms[i].rotation.x
		var want := -0.12
		if state == "musician":
			want = -0.35   # instrument poses are set at the shoulder; keep the elbow soft
		elif sx < -0.3:
			want = clampf(sx * 0.9, -1.9, -0.3)  # raised arm: bend the elbow to bring the hand in
		_elbows[i].rotation.x = lerpf(_elbows[i].rotation.x, want, minf(1.0, delta * 12.0))
		# keep whatever is in the hand upright relative to the body
		_hands[i].rotation.x = -(sx + _elbows[i].rotation.x)
		_hands[i].rotation.z = -_arms[i].rotation.z
	if _talk_left > 0.0:
		_talk_left -= delta
		var open := absf(sin(_anim_t * 17.0)) * 0.6 + absf(sin(_anim_t * 7.3)) * 0.4
		_jaw_lip.position.y = -0.005 - open * 0.012
		_head.rotation.x += sin(_anim_t * 4.0) * 0.004
	elif _jaw_lip.position.y != -0.005:
		_jaw_lip.position.y = move_toward(_jaw_lip.position.y, -0.005, delta * 0.1)


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


## Says a line for a situation: a recorded voice line when there is one (with its words as the
## bubble), otherwise just the written fallback.
func speak(tag: String, fallback := "", seconds := 3.5, color := Color(1, 0.97, 0.9), important := false) -> void:
	var said := ""
	if world and world.get("voices") and voice != "":
		var drink := drink_id if tag.begins_with("order") else ""
		said = world.voices.speak(self, voice, tag, important, drink)
	if said != "":
		say(said, seconds, color)
	elif fallback != "":
		say(fallback, seconds, color)


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
	_solve_joints(delta)
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
		"mingle":
			# in the pub, chatting, not yet ordering: no patience is lost here
			_idle_anim(delta)
			mingle_t += delta
			if mingle_t > 300.0:
				leave()
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
		"mingle":
			state = "mingle"
			if seat >= 0:
				rotation.y = _seat_yaw
				_set_seated(true)
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
		speak("wait", world.line("waiting"), 2.5, Color(1, 0.8, 0.4))
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
	speak("complain", world.line("angry"), 3.0, Color(1, 0.5, 0.4))
	world.on_walkout(self)
	leave()


func take_order() -> String:
	order_taken = true
	order_time = world.run_time
	state = "wait_drink"
	patience = minf(patience_max, patience + patience_max * 0.15)
	var line: String = world.order_line(self)
	speak("order_stout" if drink_id == "stout" else "order_other", line, 4.0, Color(1, 0.97, 0.9), true)
	return line


## Called by the world when the player hands over a drink.
func receive_drink(g: PintGlass) -> void:
	ordering = false
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
	if on and not _seated and is_inside_tree():
		Sfx.play_at("stool", global_position + Vector3(0, 0.4, 0), world, -12.0)
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
		order_taken = false
		patience = patience_max
		drink_id = world.pick_drink(self)
		world.customer_wants_order(self)
	else:
		leave()


## Sit or stand somewhere and wait for the dispatcher to call us up to order.
func start_mingling(pos: Vector3, yaw: float) -> void:
	mingle_t = 0.0
	_seat_yaw = yaw
	walk_to(pos, "mingle")


func go_to_bar(spot: int, pos: Vector3) -> void:
	ordering = true
	bar_spot = spot
	patience = patience_max
	order_taken = false
	walk_to(pos, "wait_order")


func leave() -> void:
	if served_count > 0 and state not in ["walk", "gone"]:
		speak("goodbye", "", 2.5)
	ordering = false
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
