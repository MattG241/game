class_name Cleaner
extends Node3D
## The equipped cleaning tool: aiming, brush stamping into the dirt map, dust
## collection, battery use, particles, audio, haptics and the animated 3D rig
## (glove, sleeve, shaft and head that physically scrubs the aim point).

var player: Node3D
var camera: Camera3D
var dirt: DirtMap
var cleaning := false          # true while the clean input is active
var enabled := true

var stats := {}
var tool_id := ""
var aim_point := Vector3.ZERO
var aim_normal := Vector3.UP
var aim_valid := false
var removing := false          # actually removing dirt this frame
var rate := 0.0                # smoothed dust/sec for HUD

var _rig := {}
var _head: Node3D
var _shaft: MeshInstance3D
var _grip: MeshInstance3D
var _arm: MeshInstance3D
var _glove: MeshInstance3D
var _hand_item: Node3D
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _beam: MeshInstance3D
var _particles: CPUParticles3D
var _drones: Array = []
var _last_stamp := Vector3.INF
var _time := 0.0
var _haptic_t := 0.0
var _full_warn_t := 0.0
var _battery_warn_t := 0.0
var _removed_accum := 0.0
var _rate_t := 0.0


func _ready() -> void:
	top_level = true
	dirt = GameState.dirt
	var suit := Meshes.hs(Color(0.93, 0.93, 0.9), 0.05, 0.75, Color(0, 0, 0), 0.0, 5.0, 0.2)
	_arm = Meshes.part(self, Meshes.cyl(0.5, 1.0, 12), suit, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	_glove = Meshes.part(self, Meshes.sphere(0.05, 12), Meshes.hs(Color(0.95, 0.5, 0.12), 0.1, 0.6), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	_shaft = Meshes.part(self, Meshes.cyl(0.5, 1.0, 10), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, true)
	_grip = Meshes.part(self, Meshes.cyl(0.5, 1.0, 10), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	_ring = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	_ring.mesh = pm
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = Meshes.world_shader("res://shaders/brush_ring.gdshader")
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_beam = Meshes.part(self, Meshes.cyl(0.5, 1.0, 12), Meshes.energy(Color(0.2, 0.9, 1.0), 1.4, 3.0, 10.0), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	_beam.visible = false
	_particles = _make_particles()
	add_child(_particles)
	GameState.tool_changed.connect(_on_tool_changed)
	_on_tool_changed(GameState.equipped)


func _make_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = int(64 * float(Settings.get_value("particles", 0.7))) + 8
	p.lifetime = 1.3
	p.emitting = false
	p.local_coords = false
	p.explosiveness = 0.0
	p.randomness = 0.6
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.albedo_texture = UIKit.soft_dot()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.albedo_color = Color(0.85, 0.82, 0.76)
	q.material = m
	p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -1.62, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 2.0
	var g := Gradient.new()
	g.set_color(0, Color(0.78, 0.74, 0.68, 0.9))
	g.set_color(1, Color(0.7, 0.68, 0.64, 0.0))
	p.color_ramp = g
	p.damping_min = 0.2
	p.damping_max = 0.8
	return p


func _on_tool_changed(id: String) -> void:
	Diagnostics.event("tool " + id)
	stats = GameState.tool_stats(id)
	if id == tool_id and _head != null:
		_resize_ring()
		return
	tool_id = id
	if _head:
		_head.queue_free()
	if _hand_item:
		_hand_item.queue_free()
		_hand_item = null
	for d in _drones:
		d.queue_free()
	_drones.clear()
	_rig = ToolModels.build(id, stats)
	_head = _rig["head"]
	add_child(_head)
	_shaft.material_override = _rig["shaft_mat"]
	_grip.material_override = _rig["grip_mat"]
	var emitter: bool = _rig["emitter"]
	_shaft.visible = not emitter
	_grip.visible = not emitter
	_head.visible = not emitter
	if _rig["hand_item"]:
		_hand_item = _rig["hand_item"]
		add_child(_hand_item)
	if stats.get("shape", "") == "swarm":
		for i in int(stats.get("drones", 4)):
			var d := ToolModels.mini_drone(Color.html(stats["color"]), 0.8)
			add_child(d)
			d.global_position = TerrainGen.surface(player.global_position, 3.0) if player else Vector3.ZERO
			_drones.append(d)
	var col := Color.html(stats.get("color", "#ffffff"))
	_beam.material_override = Meshes.energy(col.lightened(0.3), 1.4, 3.0, 10.0)
	_particles.radial_accel_min = -6.0 if stats.get("suction", false) else 0.0
	_particles.radial_accel_max = -3.0 if stats.get("suction", false) else 0.0
	_resize_ring()


func _resize_ring() -> void:
	var shape: String = stats.get("shape", "round")
	if shape == "round" or shape == "swarm":
		var r: float = stats["radius"]
		_ring.scale = Vector3(r, 1, r)
		_ring_mat.set_shader_parameter("rect", 0.0)
		_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_particles.emission_sphere_radius = r * 0.7
	else:
		var hw: float = stats["half_width"]
		var hl: float = stats["half_length"]
		_ring.scale = Vector3(hw, 1, hl)
		_ring_mat.set_shader_parameter("rect", 1.0)
		_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_particles.emission_box_extents = Vector3(hw * 0.8, 0.05, hl * 0.8)
	if shape == "swarm":
		var hw: float = stats["half_width"]
		var hl: float = stats["half_length"]
		_ring.scale = Vector3(hw, 1, hl)
		_ring_mat.set_shader_parameter("rect", 1.0)


func set_visible_rig(v: bool) -> void:
	visible = v
	if not v:
		_particles.emitting = false
		Audio.loop("tool", "", false)


func _process(delta: float) -> void:
	if not enabled or player == null or camera == null or not visible:
		return
	_time += delta
	_update_aim()
	var dt := delta
	removing = false
	var shape: String = stats.get("shape", "round")
	var powered: bool = float(stats.get("power", 0.0)) > 0.0
	var strength: float = stats["strength"]
	var active := cleaning and aim_valid
	if powered and (active or shape == "swarm"):
		if not GameState.use_battery(float(stats["power"]) * dt * (1.0 if active else 0.4)):
			strength *= 0.2
			_battery_warn_t -= delta
			if _battery_warn_t <= 0.0:
				_battery_warn_t = 6.0
				GameState.notify.emit("Suit battery empty - tool at 20%. Recharge at base or a Charging Station.", "error")
	var removed_area := 0.0
	var thickness := 1.0
	var region := TerrainGen.region_of(aim_point)
	var rinfo := GameData.region(region)
	if active:
		thickness = TerrainGen.thickness(aim_point, float(rinfo["thickness"]))
		removed_area += _stamp_stroke(shape, strength, dt, thickness)
	if shape == "swarm":
		removed_area += _update_swarm(delta, strength * 0.6)
		if thickness == 1.0:
			thickness = float(rinfo["thickness"])
	if removed_area > 0.0:
		removing = true
		var units := removed_area * float(GameData.economy["dust_per_m2"]) * thickness
		GameState.add_dust(units, float(rinfo["dust_mult"]))
		GameState.record_clean(removed_area)
		_removed_accum += units
		_haptic_t -= delta
		if _haptic_t <= 0.0:
			_haptic_t = 0.09
			Settings.vibrate(6, 0.18)
	elif active and GameState.tank_space() <= 0.001:
		_full_warn_t -= delta
		if _full_warn_t <= 0.0:
			_full_warn_t = 3.0
			Audio.play("tank_full")
			Settings.vibrate(60, 0.7)
			GameState.notify.emit("Dust tank FULL - sell it at the Dust Exchange", "error")
	_rate_t += delta
	if _rate_t >= 0.5:
		rate = lerpf(rate, _removed_accum / _rate_t, 0.6)
		_removed_accum = 0.0
		_rate_t = 0.0
	_update_rig(delta, active)
	_update_effects(active)


func _update_aim() -> void:
	var reach: float = stats.get("reach", 2.5)
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * (reach + 1.8), 1)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	var up := player.global_position.normalized()
	var flat := fwd - up * fwd.dot(up)
	if flat.length_squared() < 0.0001:
		flat = -player.global_basis.z
	flat = flat.normalized()
	if not hit.is_empty() and from.distance_to(hit["position"]) <= reach + 1.6:
		aim_point = hit["position"]
		aim_normal = hit["normal"]
		aim_valid = true
	elif Settings.get_value("aim_assist", true):
		# Aim assist: clean the ground in front of the player when not looking at it.
		var d := minf(reach * 0.7, 2.2) if stats.get("shape", "") != "beam" else reach * 0.6
		var p := TerrainGen.surface(player.global_position + flat * d)
		aim_point = p
		aim_normal = TerrainGen.normal_dir(p.normalized())
		aim_valid = true
	else:
		aim_valid = false
		aim_point = from + fwd * reach


## Stamps the brush along the path travelled since last frame so fast sweeps leave
## continuous trails instead of dotted ones.
func _stamp_stroke(shape: String, strength: float, dt: float, thickness: float) -> float:
	var target := aim_point + _scrub_offset()
	if _last_stamp == Vector3.INF or _last_stamp.distance_to(target) > 6.0:
		_last_stamp = target
	var size: float = stats.get("radius", 0.3) if shape == "round" else stats.get("half_width", 0.5)
	var spacing := maxf(size * 0.5, 0.06)
	var dist := _last_stamp.distance_to(target)
	var steps := clampi(int(ceil(dist / spacing)), 1, 10)
	var fwd := _forward()
	var total := 0.0
	var dust_per_m2 := float(GameData.economy["dust_per_m2"]) * thickness
	for i in steps:
		var p := _last_stamp.lerp(target, float(i + 1) / steps)
		var budget := GameState.tank_space() / dust_per_m2 - total
		if budget <= 0.0:
			break
		if shape == "round":
			total += dirt.stamp(DirtMap.Shape.ROUND, p, stats["radius"], 0.0, Vector3.ZERO, strength * dt, budget)
		else:
			var hw: float = stats["half_width"]
			var hl: float = stats["half_length"]
			total += dirt.stamp(DirtMap.Shape.RECT, p, hw, hl, fwd, strength * dt, budget)
	_last_stamp = target
	return total


func _scrub_offset() -> Vector3:
	var s: float = stats.get("scrub", 0.0)
	if s <= 0.0 or not cleaning:
		return Vector3.ZERO
	var up := aim_point.normalized()
	var right := camera.global_basis.x
	right = (right - up * right.dot(up)).normalized()
	var fwd := up.cross(right)
	return right * sin(_time * 15.0) * s + fwd * cos(_time * 7.5) * s * 0.4


## Where the camera looks, along the ground at the aim point.
func _forward() -> Vector3:
	var up := aim_point.normalized()
	var f := -camera.global_basis.z
	f -= up * f.dot(up)
	return f.normalized() if f.length_squared() > 1e-6 else -player.global_basis.z


func _update_swarm(delta: float, strength: float) -> float:
	var total := 0.0
	var n := _drones.size()
	var base := player.global_position
	var pb := TerrainGen.upright(base, -player.global_basis.z)
	var dust_per_m2 := float(GameData.economy["dust_per_m2"])
	for i in n:
		var d: Node3D = _drones[i]
		var a := _time * 0.6 + i * TAU / n
		var rad := 4.0 + 1.5 * sin(_time * 0.9 + i)
		var target := TerrainGen.surface(base + pb * Vector3(cos(a) * rad, 0, sin(a) * rad), 1.4)
		d.global_position = d.global_position.lerp(target, minf(delta * 3.0, 1.0))
		d.global_basis = pb * Basis(Vector3.UP, -a)
		var props: Node3D = d.get_node("Props")
		props.rotation.y += delta * 40.0
		var budget := GameState.tank_space() / dust_per_m2 - total
		if budget > 0.0:
			total += dirt.stamp(DirtMap.Shape.ROUND, d.global_position, stats["radius"], 0.0, Vector3.ZERO, strength * delta, budget)
	return total


func _update_rig(delta: float, active: bool) -> void:
	var cam_t := camera.global_transform
	var bob := Vector3(0, sin(_time * 2.0) * 0.006, 0)
	var scrub := _scrub_offset()
	var hand_local := Vector3(0.27, -0.3, -0.62) + bob
	if active:
		hand_local += Vector3(0.0, -0.03, -0.05)
	var hand := cam_t * hand_local + scrub * 0.25
	var shoulder := cam_t * Vector3(0.42, -0.62, 0.15)
	Meshes.span(_arm, shoulder, hand, 0.13)
	_glove.global_position = hand
	var emitter: bool = _rig.get("emitter", false)
	if emitter:
		_hand_item.global_transform = Transform3D(cam_t.basis, hand + cam_t.basis * Vector3(0, 0.02, -0.08))
		var tip := _hand_item.global_transform * Vector3(0, 0, -0.42)
		_beam.visible = active
		if active:
			Meshes.span(_beam, tip, aim_point, 0.06 + 0.02 * sin(_time * 40.0))
	else:
		_beam.visible = false
		var head_pos := aim_point + scrub + aim_normal * 0.01
		var fwd := -cam_t.basis.z
		fwd = (fwd - aim_normal * fwd.dot(aim_normal)).normalized()
		if fwd.length_squared() < 0.01:
			fwd = -player.global_basis.z
		var right := fwd.cross(aim_normal).normalized()
		var basis := Basis(right, aim_normal, -fwd)
		_head.global_transform = Transform3D(basis, head_pos)
		var attach: Vector3 = _head.global_transform * (_rig["attach"] as Vector3)
		var r: float = _rig["shaft_r"]
		Meshes.span(_shaft, attach, hand, r * 2.0)
		var grip_start := hand.lerp(attach, minf(0.25 / maxf(hand.distance_to(attach), 0.3), 0.5))
		Meshes.span(_grip, hand, grip_start, r * 2.6)
		for s in _rig["spinners"]:
			(s as Node3D).rotation.y += delta * (28.0 if active else 2.0)
		if _rig.has("roller"):
			(_rig["roller"] as Node3D).rotation.x += delta * (18.0 if active else 0.0)
	# Footprint ring
	var shape: String = stats.get("shape", "round")
	var aim_up := aim_point.normalized()
	var ring_b := TerrainGen.upright(aim_point, _forward())
	if shape == "swarm" or shape == "beam" or shape == "wide":
		_ring.global_transform = Transform3D(ring_b, aim_point + aim_up * 0.04)
		_ring.scale = Vector3(stats["half_width"], 1, stats["half_length"])
	else:
		_ring.global_transform = Transform3D(ring_b, aim_point + aim_up * 0.04)
		_ring.scale = Vector3(stats["radius"], 1, stats["radius"])
	_ring_mat.set_shader_parameter("active", 1.0 if active else 0.0)
	var col := Color(0.3, 1.0, 0.7) if aim_valid else Color(1.0, 0.3, 0.3)
	if GameState.tank_space() <= 0.001:
		col = Color(1.0, 0.6, 0.1)
	_ring_mat.set_shader_parameter("color", col)


func _update_effects(active: bool) -> void:
	var emit := removing and active
	_particles.emitting = emit
	if emit:
		var up := aim_point.normalized()
		_particles.global_transform = Transform3D(TerrainGen.upright(aim_point, _forward()), aim_point + up * 0.05)
		_particles.gravity = -up * 1.62
		if stats.get("suction", false) and not _rig.get("emitter", false):
			_particles.global_position = aim_point + up * 0.25
	var snd: String = stats.get("sound", "brush_small")
	var powered: bool = float(stats.get("power", 0.0)) > 0.0
	var on := active and (removing or powered)
	var pitch := 1.0 + 0.05 * sin(_time * 3.0)
	if snd.begins_with("brush"):
		# Brushing volume follows how much dust is actually coming up.
		var vol := -6.0 if removing else -16.0
		Audio.loop("tool", snd, active, vol, pitch)
	else:
		Audio.loop("tool", snd, on, -4.0 if removing else -9.0, pitch)
	if stats.get("shape", "") == "swarm":
		Audio.loop("swarm", "drone_loop", true, -14.0, 1.2)
	else:
		Audio.loop("swarm", "", false)
