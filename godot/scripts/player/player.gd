class_name Player
extends CharacterBody3D
## First-person astronaut on the round Moon: low-gravity movement towards the centre, touch/keyboard look, footsteps,
## hover pack, region permits and interaction targeting.

var controls: TouchControls
var camera: Camera3D
var head: Node3D
var cleaner: Cleaner
var world: Node

var pitch := -0.3
var sprint_toggle := false
var input_enabled := true
var _step_accum := 0.0
var _was_on_floor := true
var _blocked_msg_t := 0.0
var _last_pos := Vector3.ZERO
var _kb_look := false
var _bob_t := 0.0
var _land_kick := 0.0
var _last_ok := Vector3.INF
var _ok_t := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(60)
	floor_constant_speed = true   # same walking speed uphill as on the flat
	floor_snap_length = 0.4
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	head = Node3D.new()
	head.position = Vector3(0, 1.62, 0)
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.04
	camera.far = 2600.0
	head.add_child(camera)
	camera.current = true
	_last_pos = global_position


func setup(c: TouchControls, w: Node) -> void:
	controls = c
	world = w
	cleaner = Cleaner.new()
	cleaner.player = self
	cleaner.camera = camera
	w.add_child(cleaner)


func set_active(on: bool) -> void:
	input_enabled = on
	visible = on
	set_physics_process(on)
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = not on
	if cleaner:
		cleaner.set_visible_rig(on)
		cleaner.enabled = on
	if on:
		camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if (event is InputEventMouse) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	# Desktop fallback (testing): right mouse drag to look.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_kb_look = event.pressed
	elif event is InputEventMouseMotion and _kb_look:
		_look(event.relative)


func _look(delta: Vector2) -> void:
	var sens := float(Settings.get_value("sensitivity", 1.0)) * 0.0042
	var inv := -1.0 if Settings.get_value("invert_y", false) else 1.0
	_turn(-delta.x * sens)
	pitch = clampf(pitch - delta.y * sens * inv, -1.45, 1.25)


## Heading relative to the local map frame (0 = facing the map's -Z). Setting it turns
## the body on the spot.
var yaw: float:
	get:
		return TerrainGen.yaw_of(global_position, global_basis)
	set(v):
		global_basis = TerrainGen.heading_basis(global_position, v)


func _turn(a: float) -> void:
	if a != 0.0:
		global_basis = Basis(global_basis.y.normalized(), a) * global_basis


## Keeps the body standing up on the round Moon: turns it (shortest way) so its Y axis
## points away from the centre. Carrying the heading along like this means walking over
## the poles never spins the view.
func _stand_up() -> Vector3:
	var up := global_position.normalized()
	var b := global_basis.orthonormalized()
	if b.y.dot(up) < 0.99999:
		b = Basis(Quaternion(b.y, up)) * b
	global_basis = b.orthonormalized()
	up_direction = up
	return up


func _physics_process(delta: float) -> void:
	var up := _stand_up()
	if controls and input_enabled:
		_look(controls.consume_look())
	head.rotation.x = pitch
	var mv := GameState.move_stats()
	var input := Vector2.ZERO
	if controls and input_enabled:
		input = controls.move_vector
	input += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") if input.length() < 0.05 else Vector2.ZERO
	if Input.is_key_pressed(KEY_A): input.x -= 1
	if Input.is_key_pressed(KEY_D): input.x += 1
	if Input.is_key_pressed(KEY_W): input.y -= 1
	if Input.is_key_pressed(KEY_S): input.y += 1
	input = input.limit_length(1.0)
	var sprint := sprint_toggle or Input.is_key_pressed(KEY_SHIFT)
	var speed: float = mv["sprint"] if sprint else mv["walk"]
	if cleaner and cleaner.cleaning:
		speed *= 0.8
	var dir := global_basis * Vector3(input.x, 0, input.y)
	dir -= up * dir.dot(up)
	var target := dir * speed
	var on_floor := is_on_floor()
	var accel := 14.0 if on_floor else 3.5
	var v_up := velocity.dot(up)
	var v_h := (velocity - up * v_up).move_toward(target, accel * speed * delta)
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	v_up -= g * delta
	var jump_held := (controls and controls.is_held("jump")) or Input.is_key_pressed(KEY_SPACE)
	if not on_floor and jump_held and mv["jetpack"] and v_up < 1.5:
		v_up += 6.0 * delta
	velocity = v_h + up * v_up
	var prev := global_position
	move_and_slide()
	# Region permits: stop at the border of a locked region.
	var p := global_position
	var reg := TerrainGen.region_of(p)
	if not GameState.region_unlocked(reg):
		# Stop at the border smoothly (stay where we were last frame). Only if that spot
		# was also off-limits (e.g. a save inside a now-locked area) jump to the last
		# allowed spot, so the player can never be trapped bouncing in place.
		if GameState.region_unlocked(TerrainGen.region_of(prev)):
			global_position = prev if TerrainGen.altitude(prev) > -0.05 else TerrainGen.surface(prev)
		else:
			var back := _last_ok if _last_ok != Vector3.INF else LunarBase.spawn_point()
			global_position = back if TerrainGen.altitude(back) > 0.0 else TerrainGen.surface(back, 0.1)
		var nu := global_position.normalized()
		velocity = nu * minf(velocity.dot(nu), 0.0)
		_blocked_msg_t -= delta
		if _blocked_msg_t <= 0.0:
			_blocked_msg_t = 3.0
			var info := GameData.region(reg)
			GameState.notify.emit("%s requires a permit (%s CR) - see Shop > Permits" % [info["name"], GameState.fmt(info["permit"])], "error")
	else:
		_blocked_msg_t = 0.0
		if is_on_floor():
			_ok_t += delta
			if _ok_t > 0.25:
				_ok_t = 0.0
				# A point 1.5 m back along the way we came, so we land clear of the border.
				_last_ok = global_position - v_h.limit_length(1.0) * 1.5
	# Safety net: never fall through the world.
	if TerrainGen.altitude(global_position) < -2.0:
		global_position = TerrainGen.surface(global_position, 0.5)
		velocity = Vector3.ZERO
	_footsteps(delta, on_floor)
	_head_bob(delta, on_floor, input.length())


func jump() -> void:
	if is_on_floor():
		var up := up_direction
		velocity += up * (float(GameState.move_stats()["jump"]) - velocity.dot(up))
		Audio.play("jump", -6.0)


func _footsteps(delta: float, on_floor: bool) -> void:
	var dv := global_position - _last_pos
	var moved := (dv - up_direction * dv.dot(up_direction)).length()
	_last_pos = global_position
	if on_floor and not _was_on_floor:
		Audio.play("land", -5.0)
		Settings.vibrate(20, 0.35)
		_land_kick = 0.08
	_was_on_floor = on_floor
	if moved > 2.0:
		return
	GameState.add_stat("distance_walked", moved)
	if on_floor:
		_step_accum += moved
		if _step_accum > 1.7:
			_step_accum = 0.0
			Audio.play("step_%d" % (randi() % 3 + 1), -10.0, randf_range(0.9, 1.1))


func _head_bob(delta: float, on_floor: bool, amount: float) -> void:
	if on_floor:
		_bob_t += delta * (7.0 if sprint_toggle else 5.0) * amount
	_land_kick = move_toward(_land_kick, 0.0, delta * 0.4)
	head.position.y = 1.62 + sin(_bob_t * 2.0) * 0.025 * amount - _land_kick


func save_state() -> Dictionary:
	return {"pos": [global_position.x, global_position.y, global_position.z], "yaw": yaw, "pitch": pitch}


func load_state(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	global_position = Vector3(p[0], p[1], p[2]) if p.size() == 3 else LunarBase.spawn_point()
	if global_position.length() < TerrainGen.RADIUS * 0.5:
		global_position = LunarBase.spawn_point()
	yaw = float(d.get("yaw", 0.0))
	pitch = float(d.get("pitch", -0.3))
	_last_pos = global_position
