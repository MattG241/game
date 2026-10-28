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


func setup(vehicle_index: int) -> void:
	index = vehicle_index
	info = GameState.vehicle_stats(vehicle_index)
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
		"cleaning_truck":
			Meshes.part(body, Meshes.box(Vector3(w, h * 0.35, l)), dark, Vector3(0, h * 0.25, 0))
			Meshes.part(body, Meshes.box(Vector3(w, h * 0.9, l * 0.3)), paint, Vector3(0, h * 0.85, -l * 0.33))
			Meshes.part(body, Meshes.box(Vector3(w * 0.9, h * 0.4, 0.05)), Meshes.glow(Color(0.4, 0.8, 1.0), 0.6), Vector3(0, h * 1.05, -l * 0.49), Vector3(-0.2, 0, 0))
			Meshes.part(body, Meshes.cyl(w * 0.42, l * 0.55, 20), Meshes.hs(Color(0.9, 0.9, 0.92), 0.6, 0.3, Color(0, 0, 0), 0.0, 1.0, 0.3), Vector3(0, h * 1.0, l * 0.18), Vector3(PI * 0.5, 0, 0))
			Meshes.part(body, Meshes.box(Vector3(0.5, h * 1.2, 0.5)), paint, Vector3(w * 0.35, h * 1.4, -l * 0.1))
			for i in 3:
				Meshes.part(body, Meshes.box(Vector3(0.4, 0.12, 0.05)), Meshes.glow(Color(1.0, 0.75, 0.2), 3.0), Vector3((i - 1) * 0.8, h * 1.35, -l * 0.49))
	# Headlights
	for s in [-1, 1]:
		Meshes.part(body, Meshes.box(Vector3(0.22, 0.12, 0.05)), Meshes.glow(Color(1.0, 0.95, 0.8), 4.0), Vector3(s * w * 0.32, h * 0.55, -l * 0.5 - 0.03), Vector3.ZERO, Vector3.ONE, false)
	Meshes.part(body, Meshes.box(Vector3(w * 0.8, 0.08, 0.05)), Meshes.glow(Color(1.0, 0.15, 0.1), 3.0), Vector3(0, h * 0.6, l * 0.5 + 0.03), Vector3.ZERO, Vector3.ONE, false)
	# Cleaning deck
	var cw: float = info["clean_width"]
	if cw > 0.0:
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
	for zi in [-1, 1]:
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
	# Driver
	driver = Meshes.astronaut(Color(1.0, 0.5, 0.1))
	driver.position = Vector3(0, h * 0.55, -l * 0.05 if info["id"] != "cleaning_truck" else -l * 0.33)
	driver.scale = Vector3.ONE * 0.92
	driver.visible = false
	body.add_child(driver)
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
	else:
		cleaning = false
		throttle = 0.0
		steer_input = 0.0
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
		if global_basis.y.y < 0.3 and speed < 2.0:
			_flip_t += delta
			if _flip_t > 2.0:
				_flip_t = 0.0
				var yaw := global_rotation.y
				global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3(0, 1.5, 0))
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
		var p := global_position
		var reg := TerrainGen.region_at(p.x, p.z)
		var r := Vector2(p.x, p.z).length()
		var over := r > TerrainGen.WRAP_RADIUS
		if over and GameState.region_unlocked(reg) and GameState.region_unlocked(TerrainGen.region_at(-p.x, -p.z)):
			wrap_around()
		elif not GameState.region_unlocked(reg) or over:
			# Previously velocity was overwritten every frame, which fought the engine and
			# left the vehicle shaking in place on border ridges. Now: one clean put-back.
			_border_back(reg, r)
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
	var ground := TerrainGen.height(global_position.x, global_position.z)
	if global_position.y < ground - 3.0:
		recover("")


## Drove past the far edge: reappear on the opposite side, same speed and heading
## relative to the Moon (a half turn about the vertical axis through the base).
func wrap_around() -> void:
	var half := Basis(Vector3.UP, PI)
	var xf := global_transform
	var dest := Transform3D(half * xf.basis, TerrainGen.wrap_point(xf.origin))
	dest.origin.y = maxf(dest.origin.y, TerrainGen.height(dest.origin.x, dest.origin.z) + 0.6)
	global_transform = dest
	linear_velocity = half * linear_velocity
	angular_velocity = half * angular_velocity
	_good_xform = dest
	_last_pos = dest.origin
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.terrain.ensure_collision_near(dest.origin)
	Diagnostics.event("vehicle wrapped around the moon")
	if not GameState.flags.get("wrapped", false):
		GameState.flags["wrapped"] = true
		GameState.notify.emit("You drove all the way round the Moon!", "achievement")


func _border_back(reg: int, r: float) -> void:
	var back := _good_xform
	var bp := back.origin
	if not bp.is_finite() or bp == Vector3.ZERO or not GameState.region_unlocked(TerrainGen.region_at(bp.x, bp.z)):
		back = Transform3D(Basis.IDENTITY, LunarBase.BAY_POS + Vector3(0, 2, 0))
	# Land a little further inside, facing away from the border (vehicle forward is -Z).
	var away := back.origin - global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -Vector3(global_position.x, 0, global_position.z).normalized()
	var yaw := atan2(-away.x, -away.z)
	var pos := back.origin + away * 2.0
	pos.y = TerrainGen.height(pos.x, pos.z) + 1.4
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_stuck_t = 0.0
	Diagnostics.event("vehicle border put-back")
	if r > TerrainGen.WRAP_RADIUS:
		var p := global_position
		var fi := GameData.region(TerrainGen.region_at(-p.x, -p.z))
		GameState.notify.emit("Round the Moon is %s - it needs a permit (%s CR)" % [fi["name"], GameState.fmt(fi["permit"])], "error")
	else:
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
		var fallback := Transform3D(Basis.IDENTITY, LunarBase.BAY_POS + Vector3(0, 2, 0))
		global_transform = _good_xform if _good_xform.origin.is_finite() and _good_xform.origin != Vector3.ZERO else fallback
		Diagnostics.event("vehicle physics reset")
		return
	if linear_velocity.length() > 45.0:
		linear_velocity = linear_velocity.normalized() * 45.0
	if angular_velocity.length() > 8.0:
		angular_velocity = angular_velocity.normalized() * 8.0
	_good_t += delta
	var gp := global_position
	if _good_t > 0.5 and global_basis.y.y > 0.7 and GameState.region_unlocked(TerrainGen.region_at(gp.x, gp.z)) \
			and Vector2(gp.x, gp.z).length() < TerrainGen.WRAP_RADIUS - 2.0:
		_good_t = 0.0
		_good_xform = global_transform


## Puts the vehicle upright on the nearest gentle, unlocked ground, facing downhill.
func recover(message: String) -> void:
	var p := global_position
	var back := global_basis.z
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	var best := p
	var found := false
	for ring in [4.0, 7.0, 10.0, 14.0, 20.0]:
		for k in 12:
			var dir := back.rotated(Vector3.UP, k * TAU / 12.0)
			var q: Vector3 = p + dir * ring
			if TerrainGen.normal(q.x, q.z).y > 0.9 and GameState.region_unlocked(TerrainGen.region_at(q.x, q.z)):
				best = q
				found = true
				break
		if found:
			break
	var n := TerrainGen.normal(best.x, best.z)
	var downhill := Vector3(n.x, 0, n.z)
	var yaw := atan2(-downhill.x, -downhill.z) if downhill.length() > 0.05 else global_rotation.y
	best.y = TerrainGen.height(best.x, best.z) + 1.4
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(Vector3.UP, yaw), best)
	_good_xform = global_transform
	Diagnostics.event("vehicle recover")
	if message != "":
		GameState.notify.emit(message, "info")


func _clean(delta: float, speed: float) -> void:
	if _deck == null:
		return
	_deck_brush.rotation.x += delta * (20.0 if cleaning else 0.0)
	var active := cleaning
	var removed := 0.0
	if active:
		var p := _deck.global_position
		var region := TerrainGen.region_at(p.x, p.z)
		var rinfo := GameData.region(region)
		var thick := TerrainGen.thickness(p.x, p.z, float(rinfo["thickness"]))
		var dpm := float(GameData.economy["dust_per_m2"]) * thick
		var budget := hopper_space() / dpm
		var f := global_basis.z
		var yaw := atan2(f.x, f.z)
		var hw: float = float(info["clean_width"]) * 0.5
		var area := GameState.dirt.stamp(DirtMap.Shape.RECT, p.x, p.z, hw, 0.5 + minf(speed * delta, 1.5), yaw, float(info["clean_strength"]) * delta, budget)
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
	Audio.loop("vehicle_clean", "industrial_vacuum_loop", active, -6.0 if removed > 0.0 else -11.0, 0.8)


func _process(delta: float) -> void:
	if not driving:
		return
	var sz: Array = info["size"]
	var dist: float = 6.0 + float(sz[2]) * 0.9
	var height: float = 2.0 + float(sz[1])
	var yaw := global_rotation.y + cam_yaw
	var offset := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, cam_pitch) * Vector3(0, 0, dist)
	var target := global_position + Vector3(0, height, 0) + offset
	var tg := TerrainGen.height(target.x, target.z) + 1.0
	target.y = maxf(target.y, tg)
	# Keep the chase camera out of rocks, hills and buildings (like a spring arm).
	var pivot := global_position + Vector3(0, height * 0.6, 0)
	var q := PhysicsRayQueryParameters3D.create(pivot, target, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		target = (hit["position"] as Vector3) + (pivot - target).normalized() * 0.4
	if not target.is_finite():
		return
	var snap := not hit.is_empty() or cam.global_position.distance_to(target) >= 30.0
	cam.global_position = target if snap else cam.global_position.lerp(target, minf(delta * 6.0, 1.0))
	var look := global_position + Vector3(0, height * 0.5, 0)
	if cam.global_position.distance_to(look) > 0.2:
		cam.look_at(look, Vector3.UP)
	cam_yaw = lerpf(cam_yaw, 0.0, delta * 0.4) if absf(throttle) > 0.1 else cam_yaw


func save_state() -> void:
	var v: Dictionary = GameState.vehicles[index]
	v["pos"] = [global_position.x, global_position.y, global_position.z]
	v["yaw"] = global_rotation.y
	v.erase("new")
