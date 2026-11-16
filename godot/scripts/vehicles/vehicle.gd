class_name LunarVehicle
extends VehicleBody3D
## Drivable lunar vehicle with soft low-gravity suspension, a dust hopper and an
## optional cleaning deck that stamps into the same persistent dirt map as tools.

var index := -1
var info := {}
var driving := false
var cleaning := false
var throttle := 0.0
var steer_input := 0.0
var braking := false
var cam: Camera3D
var cam_yaw := 0.0
var cam_pitch := -0.32
var driver: Node3D

var _wheels: Array[VehicleWheel3D] = []
var _wheel_meshes: Array = []
var _deck: Node3D
var _deck_brush: Node3D
var _particles: CPUParticles3D
var _flip_t := 0.0
var _park_t := 0.0
var _last_pos := Vector3.ZERO
var _stuck_t := 0.0
var _good_xform := Transform3D.IDENTITY
var _good_t := 0.0
var _t := 0.0
var _haptic_t := 0.0
var _full_warn_t := 0.0
# Flying vehicles (the Lunar Saucer): no wheels, hovers at a height above the ground.
var flying := false
var descending := false        # saucer DOWN held
var _paint_parts: Array[MeshInstance3D] = []
var _paint_mat: Material


var _driver_pos := Vector3.ZERO
var _driver_suit := ""


func _make_driver(body: Node3D) -> void:
	var was_visible := driver != null and driver.visible
	if driver:
		driver.queue_free()
	var sk := Cosmetics.equipped("suit")
	_driver_suit = sk.get("id", "")
	driver = Meshes.astronaut(Color.html(sk.get("accent", "#f28020")), Color.html(sk.get("suit", "#eeeee6")))
	driver.position = _driver_pos
	driver.scale = Vector3.ONE * 0.92
	driver.visible = was_visible
	body.add_child(driver)


## Factory paint, or the vehicle skin the player is wearing (and the driver's suit).
func apply_paint() -> void:
	if driver and Cosmetics.equipped_id("suit") != _driver_suit:
		_make_driver(driver.get_parent())
	var m := Cosmetics.skin_material(Cosmetics.equipped("vehicle"))
	for mi in _paint_parts:
		mi.material_override = m if m else _paint_mat
var _fly_speed := 0.0
var _fly_alt := 1.2
var _beam: MeshInstance3D
const CRUISE_ALT := 7.0
const MIN_ALT := 2.0
const MAX_ALT := 60.0
const MAX_BEAM_ALT := 35.0


func setup(vehicle_index: int) -> void:
	index = vehicle_index
	info = GameState.vehicle_stats(vehicle_index)
	flying = bool(info.get("flying", false))
	var sz: Array = info["size"]
	var w: float = sz[0]
	var h: float = sz[1]
	var l: float = sz[2]
	mass = float(info["mass"])
	collision_layer = 4
	collision_mask = 1 | 4
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.35, 0)
	angular_damp = 1.2
	linear_damp = 0.05
	can_sleep = true
	var col := Color.html(info["color"])
	var paint := Meshes.hs(col, 0.45, 0.35, Color(0, 0, 0), 0.0, 1.2, 0.25)
	var dark := Meshes.hs(Color(0.15, 0.16, 0.19), 0.5, 0.5, Color(0, 0, 0), 0.0, 2.0, 0.3)
	var metal := Meshes.hs(Color(0.7, 0.72, 0.75), 0.85, 0.3)
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, h, l)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, h * 0.5 + 0.15, 0)
	add_child(cs)
	match info["id"]:
		"scooter":
			Meshes.part(body, Meshes.box(Vector3(w * 0.6, h * 0.6, l)), paint, Vector3(0, h * 0.5, 0))
			Meshes.part(body, Meshes.box(Vector3(w * 0.9, 0.12, l * 0.9)), dark, Vector3(0, h * 0.18, 0))
			Meshes.part(body, Meshes.cyl(0.05, 1.0, 8), metal, Vector3(0, h + 0.4, -l * 0.38), Vector3(0.35, 0, 0))
			Meshes.part(body, Meshes.box(Vector3(0.9, 0.06, 0.06)), dark, Vector3(0, h + 0.88, -l * 0.52))
			Meshes.part(body, Meshes.box(Vector3(w * 0.5, 0.25, 0.7)), dark, Vector3(0, h + 0.1, l * 0.12))
			Meshes.part(body, Meshes.box(Vector3(w * 0.7, 0.6, 0.7)), Meshes.hs(Color(0.3, 0.32, 0.36), 0.4, 0.5), Vector3(0, h + 0.2, l * 0.42))
		"utility_rover":
			Meshes.part(body, Meshes.box(Vector3(w, h * 0.5, l)), paint, Vector3(0, h * 0.45, 0))
			Meshes.part(body, Meshes.box(Vector3(w * 0.95, h * 0.9, l * 0.35)), paint, Vector3(0, h * 1.0, -l * 0.18))
			Meshes.part(body, Meshes.box(Vector3(w * 0.9, h * 0.5, 0.05)), Meshes.glow(Color(0.4, 0.8, 1.0), 0.6), Vector3(0, h * 1.1, -l * 0.36), Vector3(-0.3, 0, 0))
			Meshes.part(body, Meshes.box(Vector3(w * 0.85, h * 0.7, l * 0.38)), dark, Vector3(0, h * 0.9, l * 0.28))
			Meshes.part(body, Meshes.cyl(0.04, 1.6, 6), metal, Vector3(w * 0.4, h * 1.9, l * 0.1))
			Meshes.part(body, Meshes.sphere(0.35, 12, true), metal, Vector3(w * 0.4, h * 2.7, l * 0.1), Vector3(PI * 0.7, 0, 0))
		"vacuum_buggy":
			Meshes.part(body, Meshes.box(Vector3(w * 0.8, h * 0.5, l * 0.8)), paint, Vector3(0, h * 0.55, 0))
			Meshes.part(body, Meshes.cyl(h * 0.6, l * 0.5, 16), Meshes.hs(Color(0.85, 0.85, 0.9), 0.7, 0.25), Vector3(0, h * 1.15, l * 0.15), Vector3(PI * 0.5, 0, 0))
			Meshes.part(body, Meshes.torus(h * 0.55, h * 0.66, 20), Meshes.glow(Color(0.7, 0.5, 1.0), 2.0), Vector3(0, h * 1.15, l * 0.4), Vector3(PI * 0.5, 0, 0))
			Meshes.part(body, Meshes.box(Vector3(0.06, 1.0, 0.06)), metal, Vector3(-0.3, h + 0.5, -l * 0.25))
		"lunar_ufo":
			# A flying saucer: hull disc, glass dome, glowing rim and a beam emitter.
			Meshes.part(body, Meshes.cyl(w * 0.5, h * 0.35, 40, w * 0.36), paint, Vector3(0, h * 0.62, 0))
			Meshes.part(body, Meshes.cyl(w * 0.36, h * 0.3, 40, w * 0.5), Meshes.hs(col.darkened(0.3), 0.7, 0.3), Vector3(0, h * 0.3, 0))
			Meshes.part(body, Meshes.sphere(w * 0.2, 24, true), Meshes.visor(), Vector3(0, h * 0.78, 0))
			Meshes.part(body, Meshes.torus(w * 0.47, w * 0.52, 48), Meshes.glow(Color(0.4, 1.0, 0.9), 3.0), Vector3(0, h * 0.5, 0), Vector3.ZERO, Vector3.ONE, false)
			for i in 8:
				var a := i * TAU / 8.0
				Meshes.part(body, Meshes.sphere(0.12), Meshes.glow(Color(1.0, 0.8, 0.3), 4.0), Vector3(cos(a) * w * 0.42, h * 0.45, sin(a) * w * 0.42), Vector3.ZERO, Vector3.ONE, false)
			Meshes.part(body, Meshes.cyl(0.5, 0.2, 20), Meshes.glow(Color(0.5, 1.0, 0.8), 3.0), Vector3(0, h * 0.12, 0), Vector3.ZERO, Vector3.ONE, false)
			for i in 3:
				var a := i * TAU / 3.0
				Meshes.part(body, Meshes.cyl(0.07, 0.9, 6), dark, Vector3(cos(a) * w * 0.3, 0.0, sin(a) * w * 0.3), Vector3(cos(a) * 0.3, 0, -sin(a) * 0.3))
		"cleaning_truck":
			Meshes.part(body, Meshes.box(Vector3(w, h * 0.35, l)), dark, Vector3(0, h * 0.25, 0))
			Meshes.part(body, Meshes.box(Vector3(w, h * 0.9, l * 0.3)), paint, Vector3(0, h * 0.85, -l * 0.33))
			Meshes.part(body, Meshes.box(Vector3(w * 0.9, h * 0.4, 0.05)), Meshes.glow(Color(0.4, 0.8, 1.0), 0.6), Vector3(0, h * 1.05, -l * 0.49), Vector3(-0.2, 0, 0))
			Meshes.part(body, Meshes.cyl(w * 0.42, l * 0.55, 20), Meshes.hs(Color(0.9, 0.9, 0.92), 0.6, 0.3, Color(0, 0, 0), 0.0, 1.0, 0.3), Vector3(0, h * 1.0, l * 0.18), Vector3(PI * 0.5, 0, 0))
			Meshes.part(body, Meshes.box(Vector3(0.5, h * 1.2, 0.5)), paint, Vector3(w * 0.35, h * 1.4, -l * 0.1))
			for i in 3:
				Meshes.part(body, Meshes.box(Vector3(0.4, 0.12, 0.05)), Meshes.glow(Color(1.0, 0.75, 0.2), 3.0), Vector3((i - 1) * 0.8, h * 1.35, -l * 0.49))
	# Parts in the vehicle's paint can be repainted with a skin.
	_paint_parts.clear()
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == paint:
			_paint_parts.append(mi)
	_paint_mat = paint
	apply_paint()
	# Headlights
	for s in [-1, 1]:
		Meshes.part(body, Meshes.box(Vector3(0.22, 0.12, 0.05)), Meshes.glow(Color(1.0, 0.95, 0.8), 4.0), Vector3(s * w * 0.32, h * 0.55, -l * 0.5 - 0.03), Vector3.ZERO, Vector3.ONE, false)
	Meshes.part(body, Meshes.box(Vector3(w * 0.8, 0.08, 0.05)), Meshes.glow(Color(1.0, 0.15, 0.1), 3.0), Vector3(0, h * 0.6, l * 0.5 + 0.03), Vector3.ZERO, Vector3.ONE, false)
	# Cleaning deck
	var cw: float = info["clean_width"]
	if flying:
		_beam = Meshes.part(self, Meshes.cyl(0.5, 1.0, 20), Meshes.energy(Color(0.4, 1.0, 0.85), 0.45, 2.0, 6.0), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		_beam.top_level = true
		_beam.visible = false
		gravity_scale = 0.0
		center_of_mass = Vector3.ZERO
	elif cw > 0.0:
		_deck = Node3D.new()
		_deck.position = Vector3(0, 0.25, l * 0.5 + 0.6)
		body.add_child(_deck)
		Meshes.part(_deck, Meshes.box(Vector3(cw, 0.4, 0.9)), Meshes.hs(col.darkened(0.25), 0.5, 0.4, Color(0, 0, 0), 0.0, 1.5, 0.4, 1.2), Vector3(0, 0.1, 0))
		_deck_brush = Node3D.new()
		_deck.add_child(_deck_brush)
		Meshes.part(_deck_brush, Meshes.cyl(0.22, cw * 0.96, 10), Meshes.hs(Color(0.25, 0.8, 1.0), 0.2, 0.6, Color(0, 0, 0), 0.0, 6.0, 0.2), Vector3.ZERO, Vector3(0, 0, PI * 0.5))
		_particles = CPUParticles3D.new()
		_particles.amount = int(48 * float(Settings.get_value("particles", 0.7))) + 8
		_particles.lifetime = 1.4
		_particles.local_coords = false
		_particles.emitting = false
		var q := QuadMesh.new()
		q.size = Vector2(0.12, 0.12)
		var m := StandardMaterial3D.new()
		m.albedo_texture = UIKit.soft_dot()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		q.material = m
		_particles.mesh = q
		_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_particles.emission_box_extents = Vector3(cw * 0.45, 0.1, 0.3)
		_particles.direction = Vector3(0, 1, 0.4)
		_particles.spread = 40.0
		_particles.initial_velocity_min = 1.0
		_particles.initial_velocity_max = 3.0
		_particles.gravity = Vector3(0, -1.62, 0)
		_particles.scale_amount_min = 0.6
		_particles.scale_amount_max = 2.2
		var g := Gradient.new()
		g.set_color(0, Color(0.8, 0.76, 0.7, 0.85))
		g.set_color(1, Color(0.7, 0.68, 0.64, 0.0))
		_particles.color_ramp = g
		_deck.add_child(_particles)
	# Wheels
	var wr: float = info["wheel_radius"]
	var wheel_mat := Meshes.hs(Color(0.12, 0.12, 0.13), 0.1, 0.9, Color(0, 0, 0), 0.0, 8.0, 0.3)
	var hub_mat := metal
	for zi in ([] if flying else [-1, 1]):
		for xi in [-1, 1]:
			var wh := VehicleWheel3D.new()
			wh.position = Vector3(xi * (w * 0.5 + 0.05), wr * 0.9, zi * (l * 0.5 - wr * 0.9))
			wh.wheel_radius = wr
			wh.wheel_rest_length = 0.45
			wh.suspension_travel = 0.45
			wh.suspension_stiffness = 18.0
			wh.suspension_max_force = mass * 12.0
			wh.damping_compression = 1.2
			wh.damping_relaxation = 1.8
			wh.wheel_friction_slip = 2.4
			wh.wheel_roll_influence = 0.25
			wh.use_as_traction = true
			wh.use_as_steering = zi < 0
			add_child(wh)
			_wheels.append(wh)
			var wm := Node3D.new()
			wh.add_child(wm)
			Meshes.part(wm, Meshes.cyl(wr, wr * 0.7, 18), wheel_mat, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
			Meshes.part(wm, Meshes.cyl(wr * 0.55, wr * 0.74, 12), hub_mat, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
			for k in 6:
				Meshes.part(wm, Meshes.box(Vector3(wr * 0.72, 0.06, wr * 0.25)), wheel_mat, Vector3.ZERO, Vector3(k * PI / 6.0, 0, 0), Vector3(1, 1, 1))
	# Driver (wears the player's suit colours)
	_driver_pos = Vector3(0, h * 0.55, -l * 0.05 if info["id"] != "cleaning_truck" else -l * 0.33)
	_make_driver(body)
	# Label above vehicle
	var lbl := Meshes.label(body, info["name"], Vector3(0, h + 2.0, 0), 48, Color(1, 0.85, 0.5), true)
	lbl.name = "NameLabel"
	cam = Camera3D.new()
	cam.top_level = true
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 2600.0
	add_child(cam)
	_last_pos = global_position


func refresh_stats() -> void:
	info = GameState.vehicle_stats(index)


func hopper() -> float:
	return float(GameState.vehicles[index].get("dust", 0.0))


func hopper_value() -> float:
	return float(GameState.vehicles[index].get("value", 0.0))


func hopper_space() -> float:
	return maxf(float(info["storage"]) - hopper(), 0.0)


func add_hopper(amount: float, value_per_unit: float) -> float:
	var a := minf(amount, hopper_space())
	if a <= 0.0:
		return 0.0
	var v: Dictionary = GameState.vehicles[index]
	v["dust"] = hopper() + a
	v["value"] = hopper_value() + a * value_per_unit
	return a


func empty_hopper() -> Vector2:
	var v: Dictionary = GameState.vehicles[index]
	var out := Vector2(hopper(), hopper_value())
	v["dust"] = 0.0
	v["value"] = 0.0
	return out


func set_driving(on: bool) -> void:
	driving = on
	driver.visible = on
	get_node("Body/NameLabel").visible = not on
	can_sleep = not on
	if on:
		freeze = false
		sleeping = false
		cam.current = true
		cam_yaw = 0.0
		_park_t = 0.0
		_fly_alt = maxf(TerrainGen.altitude(global_position), CRUISE_ALT)
	else:
		cleaning = false
		throttle = 0.0
		steer_input = 0.0
		braking = false
		descending = false
		if _beam:
			_beam.visible = false
		Audio.loop("engine", "", false)
		Audio.loop("vehicle_clean", "", false)
		if _particles:
			_particles.emitting = false


func look(delta: Vector2) -> void:
	var sens := float(Settings.get_value("sensitivity", 1.0)) * 0.005
	cam_yaw -= delta.x * sens
	cam_pitch = clampf(cam_pitch - delta.y * sens, -1.1, 0.2)


func _physics_process(delta: float) -> void:
	_t += delta
	_sanity(delta)
	if flying:
		_fly(delta)
		return
	var speed := linear_velocity.length()
	var fwd_speed := -linear_velocity.dot(global_basis.z)
	if driving:
		if absf(throttle) > 0.05 or absf(steer_input) > 0.05:
			sleeping = false
		var max_speed: float = info["max_speed"]
		var force: float = info["engine"]
		if braking:
			engine_force = 0.0
			brake = mass * 0.06
		elif throttle > 0.05:
			brake = 0.0
			engine_force = -force * throttle if fwd_speed < max_speed else 0.0
		elif throttle < -0.05:
			if fwd_speed > 1.0:
				engine_force = 0.0
				brake = mass * 0.05 * -throttle
			else:
				brake = 0.0
				engine_force = force * -throttle * 0.6 if fwd_speed > -max_speed * 0.4 else 0.0
		else:
			engine_force = 0.0
			brake = mass * 0.006
		var steer_limit := lerpf(0.55, 0.18, clampf(speed / 18.0, 0.0, 1.0))
		steering = move_toward(steering, steer_input * steer_limit, delta * 2.5)
		# Auto-right if flipped
		if global_basis.y.dot(global_position.normalized()) < 0.3 and speed < 2.0:
			_flip_t += delta
			if _flip_t > 2.0:
				_flip_t = 0.0
				var gp := global_position
				global_transform = Transform3D(TerrainGen.upright(gp, -global_basis.z), TerrainGen.surface(gp, 1.5))
				linear_velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO
				GameState.notify.emit("Vehicle flipped back onto its wheels", "info")
		else:
			_flip_t = 0.0
		# Stuck (e.g. nose-up on a steep ridge): throttle held but going nowhere.
		if absf(throttle) > 0.3 and speed < 0.6:
			_stuck_t += delta
			if _stuck_t > 3.0:
				_stuck_t = 0.0
				recover("Vehicle was stuck - moved to flat ground")
		else:
			_stuck_t = 0.0
		# Region permits
		var reg := TerrainGen.region_of(global_position)
		if not GameState.region_unlocked(reg):
			# Previously velocity was overwritten every frame, which fought the engine and
			# left the vehicle shaking in place on border ridges. Now: one clean put-back.
			_border_back(reg)
		var moved := global_position.distance_to(_last_pos)
		if moved < 5.0:
			GameState.add_stat("distance_driven", moved)
		_clean(delta, speed)
		var pitch := 0.7 + clampf(speed / float(info["max_speed"]), 0.0, 1.2) * 0.9
		Audio.loop("engine", "engine_loop", true, -8.0 + absf(throttle) * 4.0, pitch)
	else:
		engine_force = 0.0
		brake = mass * 0.2
		if not freeze:
			_park_t += delta
			if speed < 0.3 and _park_t > 1.0:
				freeze = true
	_last_pos = global_position
	# Safety net
	if TerrainGen.altitude(global_position) < -3.0:
		recover("")


## Parking spot at the Vehicle Bay (fallback when nothing better is known).
static func bay_xform() -> Transform3D:
	return LunarBase.at_xform(LunarBase.BAY_POS + Vector3(0, 2, 0), PI * 0.5)


func _border_back(reg: int) -> void:
	var back := _good_xform
	var bp := back.origin
	if not bp.is_finite() or bp.length() < TerrainGen.RADIUS * 0.5 or not GameState.region_unlocked(TerrainGen.region_of(bp)):
		back = bay_xform()
	# Land a little further inside, facing away from the border (vehicle forward is -Z).
	var up := back.origin.normalized()
	var away := back.origin - global_position
	away -= up * away.dot(up)
	if away.length() < 0.01:
		away = LunarBase.at(Vector3.ZERO) - back.origin
		away -= up * away.dot(up)
	away = away.normalized()
	var pos := TerrainGen.surface(back.origin + away * 2.0, 1.4)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(TerrainGen.upright(pos, away), pos)
	_stuck_t = 0.0
	Diagnostics.event("vehicle border put-back")
	var info := GameData.region(reg)
	GameState.notify.emit("%s needs a permit (%s CR) - Shop > Permits" % [info["name"], GameState.fmt(info["permit"])], "error")


## Guards against physics blow-ups: caps speeds and restores the last good pose if
## the body ever ends up with invalid (NaN/inf) values.
func _sanity(delta: float) -> void:
	if freeze:
		return
	if not global_transform.origin.is_finite() or not linear_velocity.is_finite() or not angular_velocity.is_finite():
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		var ok := _good_xform.origin.is_finite() and _good_xform.origin.length() > TerrainGen.RADIUS * 0.5
		global_transform = _good_xform if ok else bay_xform()
		Diagnostics.event("vehicle physics reset")
		return
	if linear_velocity.length() > 45.0:
		linear_velocity = linear_velocity.normalized() * 45.0
	if angular_velocity.length() > 8.0:
		angular_velocity = angular_velocity.normalized() * 8.0
	_good_t += delta
	var gp := global_position
	if _good_t > 0.5 and global_basis.y.dot(gp.normalized()) > 0.7 and GameState.region_unlocked(TerrainGen.region_of(gp)):
		_good_t = 0.0
		_good_xform = global_transform


## Puts the vehicle upright on the nearest gentle, unlocked ground, facing downhill.
func recover(message: String) -> void:
	var p := global_position
	var up := p.normalized()
	var back := global_basis.z - up * global_basis.z.dot(up)
	back = back.normalized() if back.length() > 0.01 else TerrainGen.frame(up).z
	var best := TerrainGen.surface(p)
	var found := false
	for ring in [4.0, 7.0, 10.0, 14.0, 20.0]:
		for k in 12:
			var dir := back.rotated(up, k * TAU / 12.0)
			var q := TerrainGen.surface(p + dir * ring)
			if TerrainGen.flatness(q) > 0.9 and GameState.region_unlocked(TerrainGen.region_of(q)):
				best = q
				found = true
				break
		if found:
			break
	var bu := best.normalized()
	var n := TerrainGen.normal_dir(bu)
	var downhill := n - bu * n.dot(bu)
	var fwd := downhill if downhill.length() > 0.05 else -global_basis.z
	best = TerrainGen.surface(best, 1.4)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(TerrainGen.upright(best, fwd), best)
	_good_xform = global_transform
	Diagnostics.event("vehicle recover")
	if message != "":
		GameState.notify.emit(message, "info")


## Lunar Saucer flight: forward/back and turning like a car, JUMP climbs, otherwise it
## settles back to cruising height over the ground. Parked, it lands and switches off.
func _fly(delta: float) -> void:
	var p := global_position
	var up := p.normalized()
	var alt := TerrainGen.altitude(p)
	var fwd := -global_basis.z
	fwd = (fwd - up * fwd.dot(up)).normalized()
	if driving:
		sleeping = false
		fwd = fwd.rotated(up, steer_input * 1.7 * delta)
		_fly_speed = move_toward(_fly_speed, throttle * float(info["max_speed"]), 14.0 * delta)
		# UP / DOWN change the height; otherwise it stays at that height over the ground.
		if braking:
			_fly_alt = minf(_fly_alt + 9.0 * delta, MAX_ALT)
		elif descending:
			_fly_alt = maxf(_fly_alt - 9.0 * delta, MIN_ALT)
		var reg := TerrainGen.region_of(p)
		if not GameState.region_unlocked(reg):
			_fly_speed = 0.0
			_border_back(reg)
			_fly_alt = CRUISE_ALT
			return
		Audio.loop("engine", "engine_loop", true, -10.0 + absf(throttle) * 3.0, 1.6 + absf(_fly_speed) / 40.0)
		var moved := global_position.distance_to(_last_pos)
		if moved < 8.0:
			GameState.add_stat("distance_driven", moved)
	else:
		_fly_speed = move_toward(_fly_speed, 0.0, 10.0 * delta)
		_fly_alt = move_toward(_fly_alt, 1.2, 4.0 * delta)
		if alt < 1.5 and absf(_fly_speed) < 0.2:
			_park_t += delta
			if _park_t > 1.0:
				freeze = true
	var climb := clampf((_fly_alt - alt) * 2.2, -9.0, 12.0)
	linear_velocity = fwd * _fly_speed + up * climb
	angular_velocity = Vector3.ZERO
	global_basis = TerrainGen.upright(p, fwd) * Basis(Vector3.FORWARD, -steer_input * 0.22) * Basis(Vector3.RIGHT, -throttle * 0.08)
	_last_pos = global_position
	_fly_clean(delta, alt)


## The saucer's cleaning beam: a wide circle on the ground straight below.
func _fly_clean(delta: float, alt: float) -> void:
	var active := cleaning and driving and alt < MAX_BEAM_ALT
	var removed := 0.0
	var g := TerrainGen.surface(global_position)
	if active:
		var rinfo := GameData.region(TerrainGen.region_of(g))
		var dpm := float(GameData.economy["dust_per_m2"]) * TerrainGen.thickness(g, float(rinfo["thickness"]))
		var area := GameState.dirt.stamp(DirtMap.Shape.ROUND, g, float(info["clean_width"]) * 0.5, 0.0, Vector3.ZERO,
			float(info["clean_strength"]) * delta, hopper_space() / dpm)
		if area > 0.0:
			removed = area * dpm
			add_hopper(removed, float(rinfo["dust_mult"]))
			GameState.record_clean(area)
		elif hopper_space() <= 0.01:
			_full_warn_t -= delta
			if _full_warn_t <= 0.0:
				_full_warn_t = 4.0
				Audio.play("tank_full")
				GameState.notify.emit("Saucer hopper FULL - land at the Dust Exchange", "error")
	elif cleaning and driving:
		_full_warn_t -= delta
		if _full_warn_t <= 0.0:
			_full_warn_t = 4.0
			GameState.notify.emit("Too high for the beam - fly below %d m" % int(MAX_BEAM_ALT), "info")
	_beam.visible = active
	if active:
		var r := float(info["clean_width"]) * 0.5
		var top := global_position - global_position.normalized() * 0.3
		_beam.global_transform = Transform3D(TerrainGen.upright(g, -global_basis.z) * Basis.from_scale(Vector3(r * 2.0, top.distance_to(g), r * 2.0)), (top + g) * 0.5)
	Audio.loop("vehicle_clean", "vacuum_loop", active, -6.0 if removed > 0.0 else -11.0, 0.7)


func _clean(delta: float, speed: float) -> void:
	if _deck == null:
		return
	_deck_brush.rotation.x += delta * (20.0 if cleaning else 0.0)
	var active := cleaning
	var removed := 0.0
	if active:
		var p := _deck.global_position
		var region := TerrainGen.region_of(p)
		var rinfo := GameData.region(region)
		var thick := TerrainGen.thickness(p, float(rinfo["thickness"]))
		var dpm := float(GameData.economy["dust_per_m2"]) * thick
		var budget := hopper_space() / dpm
		var hw: float = float(info["clean_width"]) * 0.5
		var area := GameState.dirt.stamp(DirtMap.Shape.RECT, p, hw, 0.5 + minf(speed * delta, 1.5), global_basis.z, float(info["clean_strength"]) * delta, budget)
		if area > 0.0:
			removed = area * dpm
			add_hopper(removed, float(rinfo["dust_mult"]))
			GameState.record_clean(area)
			_haptic_t -= delta
			if _haptic_t <= 0.0:
				_haptic_t = 0.12
				Settings.vibrate(5, 0.15)
		elif hopper_space() <= 0.01:
			_full_warn_t -= delta
			if _full_warn_t <= 0.0:
				_full_warn_t = 4.0
				Audio.play("tank_full")
				GameState.notify.emit("Vehicle hopper FULL - drive to the Dust Exchange", "error")
	if _particles:
		_particles.emitting = removed > 0.0
		_particles.gravity = -global_position.normalized() * 1.62
	Audio.loop("vehicle_clean", "industrial_vacuum_loop", active, -6.0 if removed > 0.0 else -11.0, 0.8)


func _process(delta: float) -> void:
	if not driving:
		return
	var sz: Array = info["size"]
	var dist: float = 6.0 + float(sz[2]) * 0.9
	var height: float = 2.0 + float(sz[1])
	var up := global_position.normalized()
	var heading := TerrainGen.upright(global_position, -global_basis.z)
	var offset := heading * (Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch) * Vector3(0, 0, dist))
	var target := global_position + up * height + offset
	if TerrainGen.altitude(target) < 1.0:
		target = TerrainGen.surface(target, 1.0)
	# Keep the chase camera out of rocks, hills and buildings (like a spring arm).
	var pivot := global_position + up * (height * 0.6)
	var q := PhysicsRayQueryParameters3D.create(pivot, target, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		target = (hit["position"] as Vector3) + (pivot - target).normalized() * 0.4
	if not target.is_finite():
		return
	var snap := not hit.is_empty() or cam.global_position.distance_to(target) >= 30.0
	cam.global_position = target if snap else cam.global_position.lerp(target, minf(delta * 6.0, 1.0))
	var look := global_position + up * (height * 0.5)
	if cam.global_position.distance_to(look) > 0.2:
		cam.look_at(look, up)
	cam_yaw = lerpf(cam_yaw, 0.0, delta * 0.4) if absf(throttle) > 0.1 else cam_yaw


func save_state() -> void:
	var v: Dictionary = GameState.vehicles[index]
	v["pos"] = [global_position.x, global_position.y, global_position.z]
	v["yaw"] = TerrainGen.yaw_of(global_position, global_basis)
	v.erase("new")
