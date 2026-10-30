class_name StaffMember
extends Customer
## Hired help, on the same realistic bodies as the customers.
##
## Bar staff take the orders of customers the player isn't already looking after, fetch a clean
## glass from the rack, pour at the tap (stout gets its two-part pour and settle) and hand it over.
## The glass collector clears empties from the tables, washes them back onto the rack and wipes
## spills. Their skill sets how quick they are and how good their pints come out.

const BEHIND_Z := -2.62          # standing room behind the bar, facing the customers
const BACK_Z := -4.18            # at the back counter (rack, sink)
const BAR_HOME := Vector3(-2.0, 0.0, -3.3)
const FLOOR_HOME := Vector3(3.15, 0.0, -0.9)

var staff_id := ""
var role := "bartender"
var skill := 0.6
var target: Customer = null      # who the bartender is serving
var _fetch: Node3D = null        # the empty glass or spill the collector is heading for
var carried: Array[PintGlass] = []   # empties in the collector's hands (glass is the bottom one)
var _job_t := 0.0
var _look_t := 0.0
var _pour_id := ""
var _pour_phase := ""            # "first", "settle", "top" (stout) or "pour"
var _pour_t := 0.0
var _pour_len := 1.0
var _tap: Dictionary = {}
var _settle_left := 0.0
var _moan_t := 0.0
var _final := {}
var _reach_w := 0.0              # how far the left hand has gone to the tap handle
var _stream: MeshInstance3D      # the beer running from the nozzle while they pour


func setup_staff(w: Node, entry: Dictionary, seed_v: int) -> void:
	staff_id = str(entry.get("id", ""))
	role = str(entry.get("role", "bartender"))
	skill = clampf(float(entry.get("skill", 0.6)), 0.2, 1.0)
	display_name = str(entry.get("name", "Staff")).split(" ")[0]
	speed = 1.3 + skill * 0.25
	setup(w, {"gender": entry.get("gender", "m"), "model": entry.get("model", "")}, seed_v)
	set_name_tag("%s · %s" % [display_name, "bar" if role == "bartender" else "floor"])


func home() -> Vector3:
	return BAR_HOME if role == "bartender" else FLOOR_HOME


func busy() -> bool:
	return state != "st_idle"


## Glasses this person is holding (for the glass count check).
func glass_count() -> int:
	return carried.size() if role == "collector" else (1 if glass != null else 0)


func _refresh_bubble() -> void:
	hide_bubble()


func _process_state(delta: float) -> void:
	if _say_t > 0.0:
		_say_t -= delta
		if _say_t <= 0.0:
			hide_bubble()
	_moan_t = maxf(0.0, _moan_t - delta)
	if state == "walk":
		_walk(delta)
		return
	_job_t -= delta
	match state:
		"st_idle":
			_face_yaw(PI if role == "bartender" else PI * 0.5, delta)
			_idle_anim(delta)
			_look_t -= delta
			if _look_t <= 0.0:
				_look_t = 0.5
				_find_work()
		"st_order":
			_face_yaw(PI, delta)
			_idle_anim(delta)
			if not _target_ok("wait_order"):
				_drop_target()
			elif _job_t <= 0.0:
				world.staff_take_order(self, target)
				_go(Vector3(PubLayout.RACK_POS.x, 0, BACK_Z), "st_glass")
		"st_glass":
			_face_yaw(0.0, delta)
			_idle_anim(delta)
			if _job_t <= 0.0:
				_take_clean_glass()
		"st_pour":
			_face_yaw(PI, delta)
			_idle_anim(delta)
			_pour(delta)
		"st_serve":
			_face_yaw(PI, delta)
			_idle_anim(delta)
			if _job_t <= 0.0:
				_hand_over()
		"st_tip":
			_face_yaw(0.0, delta)
			_idle_anim(delta)
			if _job_t <= 0.0:
				world.staff_tip_away(self)
				_go_home()
		"st_collect":
			_face_point(_fetch, delta)
			_idle_anim(delta)
			if _job_t <= 0.0:
				_collect()
		"st_wash":
			_face_yaw(0.0, delta)
			_idle_anim(delta)
			_arm_rot[0].x = -0.7 + sin(_anim_t * 6.0) * 0.12
			if _job_t <= 0.0:
				_wash_one()
		"st_wipe":
			_face_point(_fetch, delta)
			_idle_anim(delta)
			_arm_rot[0].x = -0.8
			_arm_rot[0].z = sin(_anim_t * 8.0) * 0.25
			if _job_t <= 0.0:
				_arm_rot[0] = Vector3.ZERO
				if is_instance_valid(_fetch) and world.spills.has(_fetch):
					world.staff_wipe(self, _fetch)
				_fetch = null
				_after_collect()
		_:
			_idle_anim(delta)


func _arrive() -> void:
	var next := _after_path
	super._arrive()
	match next:
		"st_order":
			_job_t = lerpf(1.2, 0.5, skill)
		"st_glass", "st_serve", "st_tip":
			_job_t = lerpf(1.0, 0.4, skill)
		"st_collect":
			_job_t = lerpf(1.0, 0.4, skill)
		"st_wash":
			_job_t = _wash_time()
		"st_wipe":
			_job_t = lerpf(2.6, 1.4, skill)
		"st_pour":
			_start_pour()


func _face_point(n: Node3D, delta: float) -> void:
	if n != null and is_instance_valid(n):
		var to := n.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.05:
			_face_yaw(atan2(-to.x, -to.z), delta)


func _go(pos: Vector3, then_state: String) -> void:
	walk_to(world.reach_point(pos), then_state)


func _go_home() -> void:
	_go(home(), "st_idle")


func _find_work() -> void:
	if role == "bartender":
		var c: Customer = world.staff_next_customer(self)
		if c != null:
			target = c
			c.set_meta("served_by", self)
			_go(Vector3(world.bar_spot_pos(c.bar_spot).x, 0, BEHIND_Z), "st_order")
		elif global_position.distance_to(home()) > 0.6:
			_go_home()
		return
	# floor: spills first (someone could slip), then the empties
	var s: Node3D = world.staff_next_spill(self)
	if s != null:
		_fetch = s
		s.set_meta("staff", self)
		_go(s.global_position, "st_wipe")
		return
	if carried.size() < carry_max():
		var g: PintGlass = world.staff_next_glass(self)
		if g != null:
			_fetch = g
			g.set_meta("staff", self)
			_go(g.global_position, "st_collect")
			return
	if not carried.is_empty():
		_go(Vector3(PubLayout.SINK_POS.x, 0, BACK_Z), "st_wash")
	elif global_position.distance_to(home()) > 0.6:
		_go_home()


func carry_max() -> int:
	return 3 + int(skill * 3.0)


# ------------------------------------------------------------------ bar staff
func _target_ok(want_state: String) -> bool:
	return target != null and is_instance_valid(target) and target.state == want_state and target.bar_spot >= 0


func _drop_target() -> void:
	if target != null and is_instance_valid(target) and target.has_meta("served_by") and target.get_meta("served_by") == self:
		target.remove_meta("served_by")
	target = null
	if glass != null:
		_go(Vector3(PubLayout.SINK_POS.x, 0, BACK_Z), "st_tip")
	else:
		_go_home()


func _take_clean_glass() -> void:
	if not _target_ok("wait_drink"):
		_drop_target()
		return
	var id := target.drink_id
	if GameState.serves_left(id) < 1.0:
		_moan("The %s's run dry! Change the keg in the cellar." % GameData.drink(id).get("short", id))
		_drop_target()
		return
	if world.rack_clean <= 0:
		_moan("We're out of clean glasses!")
		_job_t = 1.0      # look again in a moment
		return
	glass = world.staff_take_glass(self, GameData.drink(id).get("glass", "pint"))
	_take_glass()
	_pour_id = id
	var tap: Dictionary = world.info["taps"].get(id, {})
	var x := float(tap["glass"].x) if not tap.is_empty() else float(PubLayout.TAP_X.get(id, -1.0))
	_go(Vector3(x, 0, BEHIND_Z), "st_pour")


func _moan(text: String) -> void:
	if _moan_t <= 0.0:
		_moan_t = 20.0
		say(text, 3.5, Color(1, 0.8, 0.5))
		world.notify("%s: %s" % [display_name, text], "bad")


## The pour, in stages; the result depends on skill (a little off on the angle, the first fill or
## the settle for a novice, near enough perfect for an old hand).
func _start_pour() -> void:
	_tap = world.info["taps"].get(_pour_id, {})
	if glass == null or not GameState.draw_units(_pour_id, 1.0):
		_moan("Can't pour that, the keg's empty.")
		_drop_target()
		return
	var d := GameData.drink(_pour_id)
	var c := glass.contents
	c.reset()
	c.drink_id = _pour_id
	c.serve = str(d.get("serve", "stout"))
	var off := (1.0 - skill) * 1.6
	var r := func(): return _rng.randf_range(-1.0, 1.0) * off
	if c.serve == "stout":
		_final = {"first": 0.75 + r.call() * 0.2, "angle": 45.0 + r.call() * 24.0,
			"topup": 0.05 + absf(r.call()) * 0.3, "body": 0.88 + r.call() * 0.06, "foam": 0.13 + r.call() * 0.08}
		_pour_phase = "first"
		_pour_len = lerpf(6.0, 4.0, skill)
	else:
		_final = {"body": 0.9 + r.call() * 0.08, "foam": 0.09 + r.call() * 0.07}
		_pour_phase = "pour"
		_pour_len = lerpf(6.0, 4.0, skill)
	_pour_t = 0.0
	if _tap.has("root"):
		Sfx.play_at("tap_clunk", _tap["glass"], world, -10.0)


func _pour(delta: float) -> void:
	if glass == null:
		return
	_pour_t += delta
	var c := glass.contents
	var p := clampf(_pour_t / _pour_len, 0.0, 1.0)
	match _pour_phase:
		"first":
			c.body = float(_final["first"]) * p * 0.6
			c.cascade = float(_final["first"]) * p * 0.4
			c.angle_sum = float(_final["angle"])
			c.angle_vol = 1.0
			if p >= 1.0:
				c.first_pour_level = float(_final["first"])
				c.stage = 2
				_pour_phase = "settle"
				_settle_left = lerpf(14.0, 9.0, skill)
				_set_down_at_tap()
		"settle":
			_settle_left -= delta
			var s := clampf(1.0 - _settle_left / 12.0, 0.0, 1.0)
			var lvl := float(_final["first"])
			c.cascade = lvl * 0.4 * (1.0 - s)
			c.body = lvl - c.cascade - 0.08 * s
			c.foam = 0.08 * s
			if _settle_left <= 0.0:
				_take_glass()
				_pour_phase = "top"
				_pour_t = 0.0
				_pour_len = lerpf(3.0, 2.0, skill)
				c.topup_cascade = float(_final["topup"])
				c.stage = 3
		"top":
			var lvl := float(_final["first"])
			c.body = lerpf(lvl - 0.08, float(_final["body"]), p)
			c.foam = lerpf(0.08, float(_final["foam"]), p)
			c.cascade = 0.03 * (1.0 - p)
			if p >= 1.0:
				_finish_pour()
		"pour":
			c.body = float(_final["body"]) * p
			c.foam = float(_final["foam"]) * minf(1.0, p * 1.4)
			if p >= 1.0:
				_finish_pour()
	glass.update_visual()


func _finish_pour() -> void:
	var c := glass.contents
	c.cascade = 0.0
	c.finished_at = world.run_time
	_arm_rot[0] = Vector3.ZERO
	_pour_phase = ""
	if _tap.has("root"):
		Sfx.play_at("tap_clunk", _tap["glass"], world, -12.0)
	if _target_ok("wait_drink"):
		_go(Vector3(world.bar_spot_pos(target.bar_spot).x, 0, BEHIND_Z), "st_serve")
	else:
		_hand_over()


## The stout sits on the drip tray under the tap while it settles.
func _set_down_at_tap() -> void:
	var pos: Vector3 = _tap["glass"] if _tap.has("glass") else global_position + Vector3(0, PubLayout.BAR_TOP, 0.35)
	if glass.get_parent():
		glass.get_parent().remove_child(glass)
	world.add_child(glass)
	glass.global_position = Vector3(pos.x, PubLayout.BAR_TOP, pos.z)
	glass.rotation = Vector3.ZERO


func _hand_over() -> void:
	var c := target
	if not _target_ok("wait_drink"):
		# they've gone (or been served): anyone else waiting on the same drink gets it
		c = world.staff_other_taker(self, _pour_id)
	if c == null:
		_drop_target()
		return
	target = c
	var ok: bool = world.staff_serve(self, c)
	if c.has_meta("served_by") and c.get_meta("served_by") == self:
		c.remove_meta("served_by")
	target = null
	if ok:
		_go_home()
	else:
		_go(Vector3(PubLayout.SINK_POS.x, 0, BACK_Z), "st_tip")


## Where the held glass goes while pouring: tilted under the nozzle, straightening as it fills.
func _glass_goal() -> Array:
	if state == "st_pour" and glass != null and glass.get_parent() == _grip and _tap.has("nozzle") and _pour_phase in ["first", "top", "pour"]:
		var nozzle: Vector3 = _tap["nozzle"]
		var p := clampf(_pour_t / _pour_len, 0.0, 1.0)
		var tilt := deg_to_rad(45.0) * (1.0 - smoothstep(0.55, 1.0, p)) if _pour_phase != "top" else 0.0
		var g := Basis(Vector3.RIGHT, -tilt)
		var rim := _body.to_local(nozzle - Vector3(0, 0.03, 0))
		return [rim - g * Vector3(0, glass.height, 0) + Vector3(0, 0, 0.02), g]
	return super._glass_goal()


## The left hand takes the tap handle and pulls it while the beer flows.
func _reach(delta: float) -> void:
	var h: Node3D = _tap.get("handle")
	var pulling := state == "st_pour" and _pour_phase in ["first", "top", "pour"]
	_reach_w = move_toward(_reach_w, 1.0 if pulling else 0.0, delta * 2.5)
	if h == null or (_reach_w <= 0.0 and is_zero_approx(h.rotation.x)):
		return
	var w := smoothstep(0.0, 1.0, _reach_w)
	_update_stream(pulling and _reach_w > 0.7)
	h.rotation.x = -0.8 * smoothstep(0.6, 1.0, _reach_w) if pulling else lerpf(h.rotation.x, 0.0, minf(1.0, delta * 8.0))
	if w <= 0.0:
		return
	var grab := h.global_transform * Vector3(0, 0.15, 0)
	var sol := _solve_ik(0, _body.to_local(grab), _hands[0].position, Vector3(-0.6, -0.8, 0.25))
	_arms[0].basis = Basis(_arms[0].basis.get_rotation_quaternion().slerp((sol[0] as Basis).get_rotation_quaternion(), w))
	_elbows[0].rotation.x = lerpf(_elbows[0].rotation.x, sol[1], w)


func _update_stream(on: bool) -> void:
	if on and _stream == null:
		_stream = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006
		cm.bottom_radius = 0.007
		cm.height = 1.0
		cm.radial_segments = 8
		cm.rings = 1
		_stream.mesh = cm
		_stream.material_override = MeshKit.shader_mat("res://assets/shaders/stream.gdshader")
		_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(_stream)
	if _stream == null:
		return
	_stream.visible = on and glass != null and _tap.has("nozzle")
	if not _stream.visible:
		return
	var nozzle: Vector3 = _tap["nozzle"]
	var c := glass.contents
	var surface := glass.to_global(Vector3(0, PintGlass.BASE + clampf(c.total(), 0.0, 1.0) * glass.inner_height, 0))
	var bottom_y := minf(surface.y, nozzle.y - 0.01)
	if glass.global_transform.basis.y.y < 0.95:
		bottom_y = maxf(bottom_y, nozzle.y - 0.08)    # running down the side of the tilted glass
	var len := maxf(0.005, nozzle.y - bottom_y)
	_stream.global_position = Vector3(nozzle.x, nozzle.y - len / 2.0, nozzle.z)
	_stream.scale = Vector3(1.1, len, 1.1)
	var col: Array = GameData.drink(_pour_id).get("color", [0.4, 0.25, 0.1])
	(_stream.material_override as ShaderMaterial).set_shader_parameter("color", Color(0.62, 0.44, 0.28) if c.serve == "stout" else Color(col[0], col[1], col[2]).lightened(0.2))


func _exit_tree() -> void:
	if _stream and is_instance_valid(_stream):
		_stream.queue_free()


# ------------------------------------------------------------------ floor staff
func _collect() -> void:
	var g := _fetch as PintGlass
	_fetch = null
	if g != null and is_instance_valid(g) and world.loose_glasses.has(g):
		world.staff_pick_up(self, g)
		if carried.is_empty():
			glass = g
			_take_glass()
		else:
			if g.get_parent():
				g.get_parent().remove_child(g)
			glass.add_child(g)
			g.position = Vector3(0, 0.045 * carried.size(), 0)
			g.rotation = Vector3.ZERO
		carried.append(g)
		Sfx.play_at("clink", g.global_position, world, -10.0)
	_after_collect()


func _after_collect() -> void:
	_look_t = 0.0
	state = "st_idle"
	_find_work()


func _wash_time() -> float:
	return lerpf(2.6, 1.1, skill)


func _wash_one() -> void:
	if carried.is_empty():
		glass = null
		_after_collect()
		return
	var g: PintGlass = carried.pop_back()
	if g == glass:
		glass = null
	world.staff_wash(self, g)
	_job_t = _wash_time()
	if carried.is_empty():
		glass = null
		_arm_rot[0] = Vector3.ZERO
		_job_t = 0.4


## Clocking off (fired, or the world closing): put down whatever they're holding.
func clock_off() -> void:
	if target != null and is_instance_valid(target) and target.has_meta("served_by") and target.get_meta("served_by") == self:
		target.remove_meta("served_by")
	if is_instance_valid(_fetch) and _fetch.has_meta("staff") and _fetch.get_meta("staff") == self:
		_fetch.remove_meta("staff")
	world.staff_drop_all(self)
