class_name Customer
extends Node3D
## A pub customer: walks in, queues, orders, waits, pays, sits, drinks and leaves.

signal left_pub(c: Customer)


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
var leaving := false         # on the way out: never called back to the bar
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

const GRIP_UP := 0.065                          # the hand wraps the glass this far above its base
const HOLD_AT := Vector3(0.14, 0.97, -0.26)     # glass base, body-local: held in front at waist height
const SIP_TIME := 3.4
const TABLE_SIP_TIME := 5.0
const PUT_TIME := 1.8

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
## Poses are written here, with negative x meaning forward (thigh, upper arm) and positive x
## meaning the knee folds back; _solve_joints maps them onto the joints.
var _arm_rot: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _leg_rot: Array[float] = [0.0, 0.0]
var _elbow_bend: Array[float] = [-0.12, -0.12]
var _grip: Node3D              # right fist; a held glass sits here
var _ik_w := 0.0               # how much the right arm follows the glass (0 = posed)
var _ik_goal: Array = []       # [glass base, glass basis] in body space
var _sip_dur := 1.0
var _sip_kind := ""            # "sip", "table" (pick up, drink, put back) or "put" (put down)
var _rig: MusicianRig = null    # musicians: the instrument and where the hands go
var _glass_spot := Vector3.ZERO   # where a seated drinker keeps the glass on the table
var _sip_gulp := 0.0           # how fast the level drops during this sip
var _shown_left := 1.0         # how full the glass looks; drops only while they drink
var model := ""
var _skel: Skeleton3D
var _bind_list: Array = []       # [bone index, joint node, bone rest in body space]
var _face_meshes: Array = []     # [MeshInstance3D, {blend shape name: index}]
var _fingers: Array = []         # [bone index, side, segment]
var _abduct: Array[float] = []    # how far each arm rests out from the body (radians, about Z)
var _upper_len := 0.3
var _grip_q := Vector3(-0.075, -0.335, -0.015)
var _lips_local := Vector3(0, -0.05, -0.105)
var _scale_k := 1.0
var _sit_drop := -0.4
var _curl := 0.15
var _mouth_open := 0.0
var _talk_left := 0.0
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
var _block_t := 0.0          # how long the player has been in the way
var _collider: AnimatableBody3D


func setup(w: Node, look: Dictionary, seed_v: int) -> void:
	world = w
	_rng.seed = hash(seed_v)   # nearby seeds (a band of musicians) would otherwise look alike
	_build(look)


## The realistic people, built from MakeHuman's CC0 data in Blender (tools/people). Regulars
## name their model in data/regulars.json; anyone else gets one of the right gender.
const MODELS_M := ["m_young_a", "m_mid_a", "m_old_a", "m_mid_b", "m_young_b", "m_old_b", "m_mid_c", "m_young_c"]
const MODELS_F := ["f_young_a", "f_mid_a", "f_old_a", "f_young_b", "f_young_c", "f_mid_b", "f_mid_c", "f_old_b"]
static var _model_info := {}
static var reserved_models: Array = []   # worn by hired staff, so customers don't share their face


static func model_info(model: String) -> Dictionary:
	if not _model_info.has(model):
		var f := FileAccess.open("res://assets/people_mh/%s.json" % model, FileAccess.READ)
		_model_info[model] = JSON.parse_string(f.get_as_text()) if f else {}
	return _model_info[model]


func _build(look: Dictionary) -> void:
	gender = str(look.get("gender", "f" if _rng.randf() < 0.45 else "m"))
	var fem := gender == "f"
	model = str(look.get("model", ""))
	if model == "":
		var pool: Array = (MODELS_F if fem else MODELS_M).filter(func(m): return not reserved_models.has(m))
		if pool.is_empty():
			pool = MODELS_F if fem else MODELS_M
		model = pool[_rng.randi() % pool.size()]
	var info := model_info(model)
	_body = Node3D.new()
	add_child(_body)
	# a solid body the player bumps into (layer 3); NPCs themselves steer by navigation
	_collider = AnimatableBody3D.new()
	_collider.collision_layer = 4
	_collider.collision_mask = 0
	_collider.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	_collider.add_child(cs)
	add_child(_collider)
	MeshKit.contact_shadow(self, Vector3.ZERO, Vector2(0.7, 0.7), 0.45)
	var scene: Node3D = (load("res://assets/people_mh/%s.gltf" % model) as PackedScene).instantiate()
	_body.add_child(scene)
	_skel = scene.find_children("*", "Skeleton3D", true, false)[0]
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var shapes := {}
		for k in m.mesh.get_blend_shape_count():
			shapes[str(m.mesh.get_blend_shape_name(k))] = k
		if not shapes.is_empty():
			_face_meshes.append([m, shapes])
	var rest := func(bone: String) -> Transform3D:
		return _skel.get_bone_global_rest(_skel.find_bone(bone))
	# --- the animation joints sit on the model's joints; their turns are copied to its bones
	for side in [-1, 1]:
		var sfx := "_l" if side == -1 else "_r"
		var hip_p: Vector3 = rest.call("thigh" + sfx).origin
		var knee_p: Vector3 = rest.call("calf" + sfx).origin
		var hip := Node3D.new()
		hip.position = hip_p
		_body.add_child(hip)
		var knee := Node3D.new()
		knee.position = knee_p - hip_p
		hip.add_child(knee)
		_legs.append(hip)
		_knees.append(knee)
		_bind("thigh" + sfx, hip)
		_bind("calf" + sfx, knee)
		var sh_p: Vector3 = rest.call("upperarm" + sfx).origin
		var el_p: Vector3 = rest.call("lowerarm" + sfx).origin
		var wr_p: Vector3 = rest.call("hand" + sfx).origin
		# the model's arms rest a little away from the body; the shoulder joint carries that angle,
		# so in its own frame the arm still hangs straight down (what the reach solver expects)
		var abduct := atan2(el_p.x - sh_p.x, sh_p.y - el_p.y)
		_abduct.append(abduct)
		var hang := Basis(Vector3.BACK, abduct).inverse()
		var sh := Node3D.new()
		sh.position = sh_p
		sh.rotation.z = abduct
		_body.add_child(sh)
		var el := Node3D.new()
		el.position = hang * (el_p - sh_p)
		sh.add_child(el)
		var wrist := Node3D.new()
		wrist.position = hang * (wr_p - el_p)
		el.add_child(wrist)
		var hand := Node3D.new()          # the palm: what instruments are held by
		hand.position = wrist.position + Vector3(0, -0.075, -0.005)
		el.add_child(hand)
		_arms.append(sh)
		_elbows.append(el)
		_hands.append(hand)
		_bind("upperarm" + sfx, sh, sh.basis)
		_bind("lowerarm" + sfx, el, sh.basis)
		_bind("hand" + sfx, wrist, sh.basis)
		if side == 1:
			_right_hand = hand
			_upper_len = sh_p.distance_to(el_p)
			_grip_q = hand.position + Vector3(-0.045, 0.01, -0.01)   # the glass sits against the palm
			_grip = Node3D.new()
			_grip.position = _grip_q
			el.add_child(_grip)
	for f in ["index", "middle", "ring", "pinky"]:
		for k in 3:
			for sfx in ["_l", "_r"]:
				var bi := _skel.find_bone("%s_%02d%s" % [f, k + 1, sfx])
				if bi >= 0:
					_fingers.append([bi, -1 if sfx == "_l" else 1, k])
	_head = Node3D.new()
	_head.position = rest.call("head").origin
	_body.add_child(_head)
	_bind("head", _head)
	var anchors: Dictionary = info.get("anchors", {})
	var lips: Array = anchors.get("lips", [0, 1.62, -0.11])
	_lips_local = Vector3(lips[0], lips[1], lips[2]) - _head.position
	_scale_k = _arms[0].position.y / 1.395
	_sit_drop = -(_legs[0].position.y - 0.58)
	var height := float(anchors.get("height", 1.75)) / 1.75
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
	# names only when you're close enough to talk; the room stays uncluttered
	_name_tag.visibility_range_end = 4.5
	_name_tag.visibility_range_end_margin = 1.0
	_name_tag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_name_tag)


func _bind(bone: String, joint: Node3D, joint_rest := Basis()) -> void:
	var bi := _skel.find_bone(bone)
	if bi >= 0:
		_bind_list.append([bi, joint, joint_rest.inverse() * _skel.get_bone_global_rest(bi).basis])


## Copies the joints' turns onto the model's bones, and curls the fingers round whatever is held.
func _sync_bones() -> void:
	if _skel == null:
		return
	var inv_body := _body.global_transform.affine_inverse()
	for b in _bind_list:
		var jt: Transform3D = inv_body * (b[1] as Node3D).global_transform
		_skel.set_bone_global_pose(b[0], Transform3D(jt.basis.orthonormalized() * (b[2] as Basis), jt.origin))
	var holding := (glass != null and glass.get_parent() == _grip) or state == "musician"
	_curl = lerpf(_curl, 1.0 if holding else 0.15, 0.2)
	for f in _fingers:
		var bi: int = f[0]
		if f.size() < 5:
			var rest_g := _skel.get_bone_global_rest(bi).basis
			f.append(_skel.get_bone_rest(bi).basis.get_rotation_quaternion())
			f.append((rest_g.inverse() * Vector3(0, 0, -float(f[1]))).normalized())
		var amount: float = _curl * [0.9, 1.15, 0.8][int(f[2])]
		if state == "musician" and int(f[1]) == -1:
			amount *= 0.7   # the left hand holds a neck or a strap, not a fist
		_skel.set_bone_pose_rotation(bi, (f[3] as Quaternion) * Quaternion(f[4] as Vector3, amount))


func _set_face(shape: String, value: float) -> void:
	for fm in _face_meshes:
		var shapes: Dictionary = fm[1]
		if shapes.has(shape):
			(fm[0] as MeshInstance3D).set_blend_shape_value(shapes[shape], value)


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
		var hx := _leg_rot[i]
		var bend := maxf(0.0, hx) * 1.1 + 0.04
		if hx < -1.0:
			bend = -hx  # seated: shins hang straight down
		_legs[i].rotation.x = -hx
		_knees[i].rotation.x = -bend
	for i in _arms.size():
		var pose: Vector3 = _arm_rot[i]
		var want := -0.12
		if state == "musician":
			want = -0.35   # instrument poses are set at the shoulder; keep the elbow soft
		elif pose.x < -0.3:
			want = clampf(pose.x * 0.9, -1.9, -0.3)  # raised arm: bend the elbow to bring the hand in
		_elbow_bend[i] = lerpf(_elbow_bend[i], want, minf(1.0, delta * 12.0))
		# arms hang slightly away from the hips
		_arms[i].rotation = Vector3(-pose.x, pose.y, pose.z + _abduct[i])
		_elbows[i].rotation.x = -_elbow_bend[i]
		# keep whatever is in the hand upright relative to the body
		_hands[i].rotation.x = pose.x + _elbow_bend[i]
		_hands[i].rotation.z = -pose.z
	# blink every few seconds
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = _rng.randf_range(2.5, 6.0)
	_set_face("blink", 1.0 if _blink_t < 0.12 else 0.0)
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
		_set_face("mouth_open", _mouth_open * 0.55)
		_head.rotation.x += sin(_anim_t * 4.0) * 0.004
	elif _mouth_open > 0.0:
		_mouth_open = 0.0
		_set_face("mouth_open", 0.0)
	_glass_arm(delta)
	if _rig:
		_apply_rig()
	_reach(delta)
	_sync_bones()


## Lets a subclass put a hand on something after the pose is solved (staff pulling a tap).
func _reach(_delta: float) -> void:
	pass


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
	var dir := to / dist
	# step round the player rather than through them: pause a moment, then sidestep
	var pl: Node3D = world.player if world and "player" in world else null
	if pl:
		var away := global_position - pl.global_position
		away.y = 0.0
		if away.length() < 0.7 and dir.dot(-away.normalized()) > 0.2:
			_block_t += delta
			if _block_t < 0.6:
				_leg_rot[0] = 0.0
				_leg_rot[1] = 0.0
				return
			var side := Vector3(-dir.z, 0, dir.x)
			if side.dot(away) < 0.0:
				side = -side
			dir = (side * 0.85 + dir * 0.15).normalized()
		else:
			_block_t = 0.0
	global_position += dir * step
	var yaw := atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, delta * 8.0))
	# the stride keeps pace with the walking speed, so feet don't skate
	var stride_f := speed * 5.6
	var sw := sin(_anim_t * stride_f) * 0.45
	_leg_rot[0] = sw
	_leg_rot[1] = -sw
	_arm_rot[0].x = -sw * 0.6
	_arm_rot[1].x = sw * 0.6 if glass == null else -0.5
	_body.position.y = absf(cos(_anim_t * stride_f)) * 0.025


func _arrive() -> void:
	_leg_rot[0] = 0
	_leg_rot[1] = 0
	_arm_rot[0].x = 0
	_arm_rot[1].x = 0 if glass == null else -0.5
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
			_pick_glass_spot()
			if glass and glass.get_parent() == _grip:
				_start_glass_move("put", PUT_TIME)
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
	var base_y := _sit_drop if _seated else 0.0
	_body.position.y = base_y + sin(_anim_t * 1.3) * 0.005
	_head.rotation.y = sin(_anim_t * 0.4) * 0.25
	if music_enjoy > 0.0:
		var speed := 7.0 if music_style == "dance" else 5.0
		_head.rotation.x = sin(_anim_t * speed) * 0.08 * music_enjoy
		_body.rotation.z = sin(_anim_t * speed * 0.3) * 0.04 * music_enjoy
		if _seated and music_style in ["dance", "sing"]:
			_leg_rot[1] = -1.45 + maxf(0.0, sin(_anim_t * speed)) * 0.15  # tapping a foot
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
		_bubble.modulate = UITheme.patience_color(f)


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
	_grip.add_child(g)
	g.position = Vector3(0, -GRIP_UP, 0)
	g.rotation = Vector3.ZERO
	served_count += 1
	drinks_had += 1
	drink_left = 1.0
	_shown_left = 1.0
	_sip_t = _rng.randf_range(3.0, 6.0)
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
		_body.position.y = _sit_drop
		_leg_rot[0] = -1.45
		_leg_rot[1] = -1.45
	else:
		_body.position.y = 0.0
		_leg_rot[0] = 0.0
		_leg_rot[1] = 0.0


## Where a seated drinker keeps the glass: on the table, in easy reach of the right hand.
func _pick_glass_spot() -> void:
	if seat < 0:
		return
	var tp: Vector3 = world.seat_info(seat)["table"]
	var b := global_transform.basis
	var near := global_position - b.z * 0.46 + b.x * 0.14
	near.y = tp.y
	_glass_spot = near if near.distance_to(tp) < 0.32 else tp


## Puts the glass straight down on the table (no animation).
func _place_glass_on_table() -> void:
	if glass == null or seat < 0:
		return
	_pick_glass_spot()
	_set_glass_down()


func _set_glass_down() -> void:
	if glass.get_parent():
		glass.get_parent().remove_child(glass)
	world.add_child(glass)
	glass.global_position = _glass_spot
	glass.rotation = Vector3.ZERO


## The glass goes into the right hand, keeping where it is; it then settles into the grip.
func _take_glass() -> void:
	var t := glass.global_transform
	if glass.get_parent():
		glass.get_parent().remove_child(glass)
	_grip.add_child(glass)
	glass.global_transform = t


func _drinking(delta: float) -> void:
	_idle_anim(delta)
	if glass == null:
		_finish_drink()
		return
	drink_left = maxf(0.0, drink_left - delta * drink_rate * world.drink_speed_mult())
	if drink_left <= 0.0 and _shown_left <= 0.001 and _sip_phase <= 0.0:
		_finish_drink()
		return
	_sip_t -= delta
	if _sip_phase <= 0.0 and (_sip_t <= 0.0 or drink_left <= 0.0):
		_sip_t = _rng.randf_range(6.0, 12.0)
		if glass.get_parent() == _grip:
			_start_glass_move("sip", SIP_TIME)
		elif _seated:
			_start_glass_move("table", TABLE_SIP_TIME)
		else:
			_take_glass()
			_start_glass_move("sip", SIP_TIME)
	# the level only drops while the glass is at their lips: each sip catches up with what they've drunk
	if _sip_phase > 0.0 and _sip_weight(1.0 - _sip_phase / _sip_dur) > 0.9:
		_shown_left = move_toward(_shown_left, drink_left, delta * maxf(0.12, _sip_gulp))
	var c := glass.contents
	# drinking takes the liquid first; the head thins and leaves lacing on the glass
	if c.total() > 0.0:
		c.cascade = 0.0
		c.body = maxf(0.0, _shown_left * 0.88)
		if _shown_left < 0.08:
			c.foam *= 0.97
		glass.lace_top = maxf(glass.lace_top, minf(c.total(), 1.0))


func _start_glass_move(kind: String, seconds: float) -> void:
	# a sip takes down what they've drunk since the last one, within the time the glass is at the lips
	var at_lips := 0.41 if kind == "sip" else 0.28
	_sip_gulp = maxf(0.0, _shown_left - drink_left) / (seconds * at_lips * 0.9)
	_sip_kind = kind
	_sip_dur = seconds
	_sip_phase = seconds


## 0..1: how far the glass is up at the lips at this point of a sip.
func _sip_weight(p: float) -> float:
	match _sip_kind:
		"sip":
			if p < 0.27:
				return smoothstep(0.0, 1.0, p / 0.27)
			if p < 0.68:
				return 1.0
			return 1.0 - smoothstep(0.0, 1.0, (p - 0.68) / 0.32)
		"table":
			if p < 0.14 or p >= 0.84:
				return 0.0
			if p < 0.36:
				return smoothstep(0.0, 1.0, (p - 0.14) / 0.22)
			if p < 0.64:
				return 1.0
			return 1.0 - smoothstep(0.0, 1.0, (p - 0.64) / 0.2)
	return 0.0


## Where the glass should be, in body space: [base position, orientation], or [] to leave the arm posed.
func _glass_goal() -> Array:
	if glass == null or not is_instance_valid(glass) or state in ["musician", "audience"]:
		return []
	var held := glass.get_parent() == _grip
	var hold := [HOLD_AT * _scale_k + Vector3(0, sin(_anim_t * 1.3) * 0.004, 0), Basis()]
	if _seated:
		hold[0] += Vector3(0, 0.12, -0.04)   # above the lap
	if _sip_phase <= 0.0 or _sip_kind == "":
		return hold if held else []
	var p := 1.0 - _sip_phase / _sip_dur
	var on_table := [_body.to_local(_glass_spot), Basis()]
	if _sip_kind == "put":
		return _mix(hold, on_table, smoothstep(0.0, 1.0, p / 0.7)) if p < 0.7 else []
	if _sip_kind == "table" and p >= 0.84:
		return []
	var sw := _sip_weight(p)
	# look ahead and tip the head back as the glass comes up, more as it empties
	var empty := 1.0 - _shown_left
	_head.rotation.y = lerp_angle(_head.rotation.y, 0.0, sw)
	_head.rotation.x = lerpf(_head.rotation.x, 0.06 + 0.22 * empty, sw)
	var tilt := lerpf(0.45, 1.25, empty)
	var g := Basis(Vector3.RIGHT, tilt)
	var lips := _head.transform * _lips_local
	var at_lips := [lips + Vector3(0, 0, -0.008) - g * Vector3(0, glass.height, 0.04), g]
	return _mix(on_table if _sip_kind == "table" else hold, at_lips, sw)


func _mix(a: Array, b: Array, t: float) -> Array:
	return [(a[0] as Vector3).lerp(b[0], t), (a[1] as Basis).slerp(b[1], t)]


## The right arm reaches for, holds and drinks from the glass. Picking up and putting down
## happen here too, at the matching point of the movement.
func _glass_arm(delta: float) -> void:
	if _sip_phase > 0.0:
		_sip_phase -= delta
		var p := 1.0 - _sip_phase / _sip_dur
		if glass and is_instance_valid(glass):
			var held := glass.get_parent() == _grip
			if _sip_kind == "table" and p >= 0.14 and p < 0.84 and not held:
				_take_glass()
			elif ((_sip_kind == "table" and p >= 0.84) or (_sip_kind == "put" and p >= 0.7)) and held:
				_set_glass_down()
		if _sip_phase <= 0.0:
			_sip_kind = ""
	var goal := _glass_goal()
	if (_sip_phase <= 0.0 or _sip_kind == "put") and music_enjoy <= 0.0 and _react_anim <= 0.0 and state != "musician":
		_head.rotation.x = lerpf(_head.rotation.x, 0.0, minf(1.0, delta * 3.0))   # level the head after a sip
	_ik_w = move_toward(_ik_w, 0.0 if goal.is_empty() else 1.0, delta * 2.5)
	if not goal.is_empty():
		_ik_goal = goal
	var w := smoothstep(0.0, 1.0, _ik_w)
	var gb := Basis()
	if w > 0.0 and not _ik_goal.is_empty():
		var gbasis: Basis = _ik_goal[1]
		var sol := _solve_ik(1, _ik_goal[0] + gbasis * Vector3(0, GRIP_UP, 0), _grip_q, Vector3(0.6, -0.8, 0.25))
		var fk := _arms[1].basis.get_rotation_quaternion()
		_arms[1].basis = Basis(fk.slerp((sol[0] as Basis).get_rotation_quaternion(), w))
		_elbows[1].rotation.x = lerpf(_elbows[1].rotation.x, sol[1], w)
		gb = Basis().slerp(gbasis, w)
	_grip.basis = (_arms[1].basis * _elbows[1].basis).inverse() * gb
	if glass and is_instance_valid(glass) and glass.get_parent() == _grip:
		glass.transform = glass.transform.interpolate_with(Transform3D(Basis(), Vector3(0, -GRIP_UP, 0)), minf(1.0, delta * 10.0))


## Two-bone reach: shoulder orientation and elbow bend that put the point `q` (elbow-local, in
## the forearm) at `target` (body space), with the elbow pointing towards `pole`.
func _solve_ik(i: int, target: Vector3, q: Vector3, pole: Vector3) -> Array:
	var d := target - _arms[i].position
	var a := _upper_len
	var r := Vector2(q.y, q.z).length()
	var off := atan2(-q.z, -q.y)
	var b2 := q.length_squared()
	var reach := clampf(d.length(), 0.12, sqrt(a * a + b2 + 2.0 * a * r) * 0.999)
	var phi := maxf(0.0, acos(clampf((reach * reach - a * a - b2) / (2.0 * a * r), -1.0, 1.0)) - off)
	var end0 := Vector3(0, -a, 0) + Basis(Vector3.RIGHT, phi) * q
	var elbow0 := Vector3(0, -a, 0)
	var u0 := end0.normalized()
	var p0 := (elbow0 - u0 * elbow0.dot(u0)).normalized()
	var u1 := d.normalized() if d.length() > 0.001 else Vector3.DOWN
	var pn := pole.normalized()
	var p1 := pn - u1 * pn.dot(u1)
	p1 = p1.normalized() if p1.length() > 0.001 else Vector3.BACK
	var b0 := Basis(u0, p0, u0.cross(p0))
	var b1 := Basis(u1, p1, u1.cross(p1))
	return [b1 * b0.transposed(), phi]


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
	_arm_rot[1] = Vector3.ZERO
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
	leaving = true
	world.dispatcher.remove(self)
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
	if glass and glass.get_parent() != _grip:
		_take_glass()
	_sip_phase = 0.0
	_sip_kind = ""
	_audience_return = global_position
	_audience_face = face
	music_style = style
	walk_to(pos, "audience")


func leave_audience() -> void:
	_body.rotation = Vector3.ZERO
	_arm_rot[0] = Vector3.ZERO
	_arm_rot[1] = Vector3(-0.5, 0, 0)
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
			_leg_rot[0] = sin(t * 5.0) * 0.6
			_leg_rot[1] = -sin(t * 5.0) * 0.6
			_arm_rot[0] = Vector3(-0.3, 0, -0.5 - 0.3 * sin(t * 2.5))
			_arm_rot[1] = Vector3(-0.6, 0, 0.4)
			_body.rotation.y = sin(t * 0.9) * 0.6
		"sing":
			# glass raised, swaying with the crowd
			_body.rotation.z = sin(t * 1.6) * 0.08
			_arm_rot[1] = Vector3(-2.6, 0, 0.25)
			_arm_rot[0] = Vector3(-0.2, 0, -0.9 - 0.2 * sin(t * 1.6))
			_head.rotation.x = 0.2
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
		_arm_rot[0] = Vector3(-2.8, 0, -0.3)
		if not glass or state == "audience":
			_arm_rot[1] = Vector3(-2.6, 0, 0.3)
	elif _react_kind == "laugh":
		_head.rotation.x = 0.25 + sin(_react_anim * 22.0) * 0.08
		_set_face("smile", clampf(_react_anim, 0.0, 1.0))
		_body.position.y += absf(sin(_react_anim * 18.0)) * 0.01
	if _react_anim <= 0.0 and state != "audience":
		_arm_rot[0] = Vector3.ZERO
		if _sip_phase <= 0.0:
			_arm_rot[1] = Vector3.ZERO


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
		_arm_rot[0].x = lerpf(_arm_rot[0].x, -0.55 + k * 0.18, minf(1.0, delta * 6.0))
		_arm_rot[0].z = lerpf(_arm_rot[0].z, -0.15, minf(1.0, delta * 6.0))
		if _gesture_t <= 0.0:
			_arm_rot[0] = Vector3.ZERO


## A wooden stool for a musician playing away from the seats.
func add_stool() -> void:
	var st := Node3D.new()
	add_child(st)
	MeshKit.prop(st, "music_stool", Vector3(0, 0, 0.03))   # a turned wooden stool
	MeshKit.contact_shadow(st, Vector3.ZERO, Vector2(0.5, 0.5), 0.4)


## Turns this character into a seated musician playing an instrument (see MusicianRig).
func make_musician(kind: String, beat_s: float) -> void:
	state = "musician"
	instrument = kind
	beat = maxf(beat_s, 0.2)
	_set_seated(true)
	_bubble.visible = false
	_rig = MusicianRig.new()
	_rig.size_k = _scale_k
	_rig.lips = _head.position + _lips_local
	_rig.build(_body, _right_hand, kind)
	_prop = _rig.prop


func _play_anim(_delta: float) -> void:
	var ph := _anim_t / beat * TAU
	_body.position.y = _sit_drop + absf(sin(ph * 0.5)) * 0.012
	_head.rotation.x = sin(ph * 0.5) * 0.06
	_head.rotation.y = 0.0
	_leg_rot[0] = -1.45 + maxf(0.0, sin(ph)) * 0.12  # foot tapping
	match instrument:
		"fiddle":
			_head.rotation.z = 0.28   # cheek down on the chin rest
			_head.rotation.y = -0.25
			_head.rotation.x = -0.12
		"whistle":
			_head.rotation.x = -0.06 + sin(ph * 0.5) * 0.03
		"accordion", "guitar", "banjo", "bodhran":
			_head.rotation.x = -0.18 + sin(ph * 0.5) * 0.05   # eyes on the hands
			_head.rotation.y = 0.15 if instrument in ["guitar", "banjo"] else 0.0


## Both arms reach for the instrument; whatever is in the right hand is turned to match.
func _apply_rig() -> void:
	var pose := _rig.pose(_anim_t, beat)
	for i in 2:
		var key := "l" if i == 0 else "r"
		var sol := _solve_ik(i, pose[key], _hands[i].position, pose["p" + key])
		_arms[i].basis = sol[0]
		_elbows[i].rotation.x = sol[1]
	if pose.has("held"):
		_hands[1].basis = (_arms[1].basis * _elbows[1].basis).inverse() * (pose["held"] as Basis)
