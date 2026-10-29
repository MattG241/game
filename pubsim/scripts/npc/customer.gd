class_name Customer
extends Node3D
## A pub customer: walks in, queues, orders, waits, pays, sits, drinks and leaves.

signal left_pub(c: Customer)

const LID_REST := 0.55
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
var _face_m: ShaderMaterial
var _mouth_open := 0.0
var _talk_left := 0.0
var _lids: Node3D
var _blink_t := 3.0
var _torso_node: Node3D
var _partner: Node3D = null    # someone nearby they're chatting with
var _social_t := 0.0
var _gesture_t := 0.0
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
	var g := "f" if fem else "m"
	_body = Node3D.new()
	add_child(_body)
	MeshKit.contact_shadow(self, Vector3.ZERO, Vector2(0.7, 0.7), 0.45)
	var height: float = look.get("height", _rng.randf_range(0.94, 1.06) * (0.95 if fem else 1.0))
	_body.scale = Vector3.ONE * height
	var skin: Color = SKIN[int(look.get("skin", _rng.randi() % SKIN.size()))]
	var coat_c: Color
	if look.has("coat"):
		coat_c = Color(look["coat"][0], look["coat"][1], look["coat"][2])
	else:
		coat_c = Color.from_hsv(_rng.randf(), _rng.randf_range(0.2, 0.55), _rng.randf_range(0.18, 0.5))
	var hair_c: Color
	if look.has("hair"):
		hair_c = Color(look["hair"][0], look["hair"][1], look["hair"][2])
	else:
		hair_c = [Color(0.1, 0.07, 0.05), Color(0.3, 0.18, 0.08), Color(0.55, 0.22, 0.08), Color(0.75, 0.6, 0.35), Color(0.6, 0.6, 0.6)][_rng.randi() % 5]
	var shirt_c: Color = [Color(0.92, 0.9, 0.85), Color(0.75, 0.82, 0.9), Color(0.85, 0.8, 0.7), Color(0.3, 0.32, 0.36)][_rng.randi() % 4]
	var jumper: bool = bool(look.get("jumper", _rng.randf() < (0.45 if fem else 0.3)))
	var skirt: bool = fem and bool(look.get("skirt", _rng.randf() < 0.4))
	var style := 0 if jumper else (2 if fem and _rng.randf() < 0.5 else 1)
	var top_pat := 2 if jumper else (1 if _rng.randf() < 0.45 else 0)
	var denim := _rng.randf() < 0.45
	var trouser_c := Color(0.16, 0.22, 0.36).lerp(Color(0.1, 0.12, 0.2), _rng.randf()) if denim else Color.from_hsv(_rng.randf_range(0.05, 0.65), 0.25, _rng.randf_range(0.1, 0.28))
	var trouser_pat := 3 if denim else 0
	var shoe_c: Color = [Color(0.08, 0.06, 0.05), Color(0.25, 0.14, 0.07), Color(0.12, 0.12, 0.13)][_rng.randi() % 3]
	if skirt:
		trouser_c = Color(0.1, 0.08, 0.08)   # dark tights under the skirt
		trouser_pat = 0
	# --- torso, painted with the outfit
	var outfit := MeshKit.shader_mat("res://assets/shaders/outfit.gdshader", {"top_color": coat_c, "top_pattern": top_pat,
		"shirt_color": shirt_c, "trouser_color": trouser_c, "trouser_pattern": trouser_pat, "skin": skin, "style": style,
		"belt": 0.0 if skirt else 1.0})
	_part(_body, "torso_" + g, outfit)
	if skirt:
		_part(_body, "skirt", MeshKit.shader_mat("res://assets/shaders/fabric.gdshader", {"base_color": coat_c.darkened(0.15), "pattern": 0}))
	# --- legs: thigh from the hip, shin (with shoe) from the knee
	var hip_w := 0.095 if fem else 0.09
	var thigh_m := MeshKit.shader_mat("res://assets/shaders/limb.gdshader", {"cloth": trouser_c, "pattern": trouser_pat, "split_y": -9.0})
	var shin_m := MeshKit.shader_mat("res://assets/shaders/limb.gdshader", {"cloth": trouser_c, "pattern": trouser_pat,
		"end_color": shoe_c, "end_rough": 0.35, "split_y": -0.385})
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(side * hip_w, 0.86, 0)
		_body.add_child(hip)
		_part(hip, "thigh_" + g, thigh_m)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.42, 0)
		hip.add_child(knee)
		_part(knee, "shin_" + g, shin_m)
		_legs.append(hip)
		_knees.append(knee)
	# --- arms: upper arm from the shoulder, forearm and hand from the elbow
	var sh_w := 0.205 if fem else 0.245
	var sleeve_c := coat_c
	var upper_m := MeshKit.shader_mat("res://assets/shaders/limb.gdshader", {"cloth": sleeve_c, "pattern": top_pat, "split_y": -9.0})
	var fore_m := MeshKit.shader_mat("res://assets/shaders/limb.gdshader", {"cloth": sleeve_c, "pattern": top_pat,
		"end_color": skin, "split_y": -0.255, "cuff": 0.0 if jumper else 1.0, "cuff_color": shirt_c})
	for side in [-1, 1]:
		var sh := Node3D.new()
		sh.position = Vector3(side * sh_w, 1.41, 0)
		_body.add_child(sh)
		_part(sh, "upperarm_" + g, upper_m)
		var el := Node3D.new()
		el.position = Vector3(0, -0.3, 0)
		sh.add_child(el)
		_part(el, ("forearm_l_" if side == -1 else "forearm_r_") + g, fore_m)
		var hand := Node3D.new()
		hand.position = Vector3(side * -0.01, -0.33, -0.04)
		el.add_child(hand)
		_arms.append(sh)
		_elbows.append(el)
		_hands.append(hand)
		if side == 1:
			_right_hand = hand
	# --- head: sculpted face, eyes, hair
	_head = Node3D.new()
	_head.position = Vector3(0, 1.665, 0)
	_body.add_child(_head)
	var lip_c := skin.darkened(0.22).lerp(Color(0.62, 0.26, 0.28), 0.45 if fem else 0.2)
	_face_m = MeshKit.shader_mat("res://assets/shaders/face.gdshader", {"skin": skin, "brow_color": hair_c.darkened(0.2),
		"lip_color": lip_c, "stubble": 0.0 if fem else _rng.randf_range(0.0, 0.8), "blush": 0.45 if fem else 0.22})
	_part(_head, "head_" + g, _face_m)
	var white_m := MeshKit.color_mat(Color(0.86, 0.83, 0.78), 0.3)
	var iris_m := MeshKit.color_mat([Color(0.25, 0.42, 0.62), Color(0.32, 0.2, 0.1), Color(0.3, 0.46, 0.3), Color(0.16, 0.1, 0.07)][_rng.randi() % 4], 0.15)
	var pupil_m := MeshKit.color_mat(Color(0.02, 0.02, 0.02), 0.1)
	for side in [-1, 1]:
		MeshKit.sphere(_head, 0.0105, Vector3(side * 0.035, 0.011, -0.0905), white_m, Vector3.ONE, 10)
		MeshKit.sphere(_head, 0.0058, Vector3(side * 0.035, 0.011, -0.0985), iris_m, Vector3(1, 1, 0.45), 8)
		MeshKit.sphere(_head, 0.0027, Vector3(side * 0.035, 0.011, -0.1012), pupil_m, Vector3(1, 1, 0.45), 6)
	var hair_m := MeshKit.shader_mat("res://assets/shaders/hair.gdshader", {"color": hair_c})
	var styles_f := ["long", "bob", "ponytail", "bun", "curly", "long"]
	var styles_m := ["short", "short", "curly", "short", "bald", "short"]
	var style_h: String = look.get("hair_style", (styles_f if fem else styles_m)[_rng.randi() % 6])
	if style_h == "messy":
		style_h = "curly"
	if style_h != "bald":
		_part(_head, "hair_" + style_h, hair_m)
	if look.get("beard", (not fem) and _rng.randf() < 0.3):
		_part(_head, "beard", hair_m)
	if look.get("cap", (not fem) and _rng.randf() < 0.15):
		_part(_head, "cap", MeshKit.shader_mat("res://assets/shaders/fabric.gdshader", {"base_color": Color.from_hsv(_rng.randf(), 0.25, 0.25), "pattern": 1}))
	if look.get("glasses", _rng.randf() < 0.15):
		var gm := MeshKit.color_mat(Color(0.1, 0.1, 0.1), 0.3, 0.5)
		for side in [-1, 1]:
			MeshKit.torus(_head, 0.017, 0.021, Vector3(side * 0.035, 0.012, -0.112), gm, Vector3(PI / 2, 0, 0))
		MeshKit.box(_head, Vector3(0.016, 0.003, 0.003), Vector3(0, 0.016, -0.114), gm)
	MeshKit.merge_children(_head, "HeadDetails")
	# eyelids for blinking (kept separate so they can move)
	# upper eyelids: resting over the top of the eye, closing fully for a blink
	_lids = Node3D.new()
	_lids.position = Vector3(0, 0.0215, -0.0905)
	_head.add_child(_lids)
	var lid_m := MeshKit.color_mat(skin.darkened(0.08), 0.55)
	for side in [-1, 1]:
		MeshKit.sphere(_lids, 0.0118, Vector3(side * 0.035, 0.0, 0.0), lid_m, Vector3(1.0, 1.0, 1.0), 10)
	_lids.scale = Vector3(1, LID_REST, 1)
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


static var _people_meshes := {}


## A sculpted body part from assets/people (made by tools/gen_people.py), shared between people.
static func people_mesh(name: String) -> Mesh:
	if not _people_meshes.has(name):
		_people_meshes[name] = load("res://assets/people/%s.obj" % name)
	return _people_meshes[name]


func _part(parent: Node3D, mesh_name: String, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = people_mesh(mesh_name)
	mi.material_override = mat
	parent.add_child(mi)
	return mi


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
	# blink every few seconds
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = _rng.randf_range(2.5, 6.0)
	_lids.scale.y = 1.0 if _blink_t < 0.12 else LID_REST
	_lids.position.y = 0.011 if _blink_t < 0.12 else 0.0215
	# breathing
	_body.scale.x = _body.scale.y * (1.0 + sin(_anim_t * 1.6) * 0.006)
	_social(delta)
	# glance at the bartender when they're close and this person is at the bar or chatting
	var pl: Node3D = world.get("player") if world else null
	var look_at_node: Node3D = null
	if pl and state in ["wait_order", "wait_drink", "mingle", "drinking", "stand_drink"] and pl.global_position.distance_to(global_position) < 3.0:
		look_at_node = pl
	elif _partner and is_instance_valid(_partner):
		look_at_node = _partner
	if look_at_node:
		var local := global_transform.basis.inverse() * (look_at_node.global_position - global_position)
		var want := clampf(atan2(-local.x, -local.z), -0.9, 0.9)
		_head.rotation.y = lerp_angle(_head.rotation.y, want, minf(1.0, delta * 4.0))
	if _talk_left > 0.0:
		_talk_left -= delta
		_mouth_open = absf(sin(_anim_t * 17.0)) * 0.6 + absf(sin(_anim_t * 7.3)) * 0.4
		_face_m.set_shader_parameter("mouth_open", _mouth_open)
		_head.rotation.x += sin(_anim_t * 4.0) * 0.004
	elif _mouth_open > 0.0:
		_mouth_open = 0.0
		_face_m.set_shader_parameter("mouth_open", 0.0)


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
	_process_state(delta)
	_solve_joints(delta)


func _process_state(delta: float) -> void:
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
			_face_yaw(0.0, delta)   # face the bar (and the bartender behind it)
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
			rotation.y = 0.0
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


## People sitting or standing near each other fall into conversation: they turn to each other,
## talk (mouths moving, no audio), gesture with the free hand and now and then laugh.
func _social(delta: float) -> void:
	if not state in ["mingle", "drinking", "stand_drink", "idle"] or world == null:
		_partner = null
		return
	_social_t -= delta
	if _social_t <= 0.0:
		_social_t = _rng.randf_range(4.0, 9.0)
		_partner = null
		var crowd: Variant = world.get("customers")
		if crowd is Array:
			var best := 1.8
			for o in crowd:
				if o == self or not is_instance_valid(o):
					continue
				var d: float = o.global_position.distance_to(global_position)
				if d < best:
					best = d
					_partner = o
		if _partner and _rng.randf() < 0.55:
			talk_for(_rng.randf_range(1.5, 3.5))
			_gesture_t = _rng.randf_range(1.2, 2.5)
		elif _partner and _rng.randf() < 0.2:
			laugh()
	if _gesture_t > 0.0 and _react_anim <= 0.0 and _sip_phase <= 0.0:
		_gesture_t -= delta
		var k := sin(_anim_t * 5.0)
		_arms[0].rotation.x = lerpf(_arms[0].rotation.x, -0.55 + k * 0.18, minf(1.0, delta * 6.0))
		_arms[0].rotation.z = lerpf(_arms[0].rotation.z, -0.15, minf(1.0, delta * 6.0))
		if _gesture_t <= 0.0:
			_arms[0].rotation = Vector3.ZERO


## A plain wooden stool for a musician playing away from the seats.
func add_stool() -> void:
	var st := Node3D.new()
	add_child(st)
	var w := MeshKit.mat("oak_y")
	MeshKit.cyl(st, 0.17, 0.17, 0.04, Vector3(0, 0.44, 0.02), MeshKit.mat("oak"), 16)
	for i in 3:
		var a := TAU * i / 3.0
		MeshKit.cyl(st, 0.018, 0.022, 0.44, Vector3(sin(a) * 0.12, 0.22, cos(a) * 0.12 + 0.02), w, 6, Vector3(cos(a) * 0.12, 0, -sin(a) * 0.12))
	MeshKit.contact_shadow(st, Vector3.ZERO, Vector2(0.5, 0.5), 0.4)


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
			# under the chin on the left shoulder, scroll pointing forward-left
			_prop.position = Vector3(-0.1, 1.47, -0.14)
			_prop.rotation = Vector3(0.25, 0.55, 0.65)
			var varnish := MeshKit.color_mat(Color(0.55, 0.22, 0.06), 0.22)
			varnish.clearcoat_enabled = true
			MeshKit.sphere(_prop, 1.0, Vector3(0, 0, -0.055), varnish, Vector3(0.068, 0.024, 0.075))
			MeshKit.sphere(_prop, 1.0, Vector3(0, 0, 0.06), varnish, Vector3(0.082, 0.026, 0.088))
			MeshKit.box(_prop, Vector3(0.05, 0.03, 0.04), Vector3(0, 0, 0.0), varnish)  # waist
			MeshKit.box(_prop, Vector3(0.022, 0.016, 0.2), Vector3(0, 0.012, -0.22), dark)  # neck and fingerboard
			MeshKit.sphere(_prop, 0.018, Vector3(0, 0.012, -0.33), varnish)  # scroll
			MeshKit.box(_prop, Vector3(0.014, 0.004, 0.36), Vector3(0, 0.03, -0.1), MeshKit.color_mat(Color(0.85, 0.85, 0.8), 0.3, 0.8))  # strings
			MeshKit.box(_prop, Vector3(0.03, 0.008, 0.05), Vector3(0, 0.03, 0.1), dark)  # tailpiece
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
