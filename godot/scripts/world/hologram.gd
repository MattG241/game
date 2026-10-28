class_name Hologram
extends Node3D
## Supervisor Gleam as a little hologram beside you: cheers your milestones, gives
## tips when you talk to them, and now and then points the way (to the Dust Exchange
## when your tank is full, or to a nearly finished hexagon).

const SPOT := Vector3(-0.95, -0.12, -2.3)   # where it floats, in camera space
const SCALE := 0.3
const POINT_EVERY := Vector2(240.0, 380.0)  # seconds between unprompted hints

var world: Node
var _fig: Node3D
var _arm: Node3D
var _arrow: MeshInstance3D
var _text: Label3D
var _mats: Array[ShaderMaterial] = []
var _show_t := 0.0        # seconds left on screen
var _fade := 0.0          # 0 hidden .. 1 fully shown
var _point_to := Vector3.INF
var _hint_in := 0.0
var _tank_hinted := false
var _queued := ""
var _queued_t := 0.0
var _talk_idx := 0
var quiet := false        # tests: hold back new lines

const CHEERS := ["Lovely work!", "Now that's clean.", "Sparkling!", "I could eat my lunch off that.",
	"The Moon thanks you.", "Spotless, cleaner!", "Head office will hear about this.", "Shiny!"]


func _ready() -> void:
	var shader: Shader = load("res://shaders/hologram.gdshader")
	_fig = Meshes.astronaut(Color(0.2, 0.7, 1.0))
	add_child(_fig)
	_fig.scale = Vector3.ONE * SCALE
	_fig.rotation.y = PI
	_arm = _fig.get_node("ArmR")
	# Projector disc under the feet
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 0.6
	cm.height = 0.04
	disc.mesh = cm
	_fig.add_child(disc)
	# Arrow used when pointing the way
	_arrow = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.3
	_arrow.mesh = cone
	add_child(_arrow)
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := ShaderMaterial.new()
		m.shader = shader
		(mi as MeshInstance3D).material_override = m
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mats.append(m)
	_text = Label3D.new()
	_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_text.no_depth_test = true
	_text.fixed_size = true
	_text.pixel_size = 0.0011
	_text.font_size = 30
	_text.outline_size = 10
	_text.modulate = Color(0.8, 0.97, 1.0)
	_text.outline_modulate = Color(0.0, 0.08, 0.15, 0.85)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.width = 470.0
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text.render_priority = 10
	add_child(_text)
	_hint_in = randf_range(POINT_EVERY.x, POINT_EVERY.y)
	visible = false


## Pops up and says something for a few seconds (replacing what it was saying).
func say(text: String, seconds := 4.0, point_at := Vector3.INF, force := false) -> void:
	if quiet:
		return
	var busy := visible and _show_t > 0.0 and (_point_to.is_finite() or (_fade > 0.5 and _show_t > 1.5))
	if busy and not force and point_at == Vector3.INF:
		# Already talking or pointing the way: say this next instead of cutting in.
		_queued = text
		_queued_t = seconds
		return
	if not visible or _fade < 0.3:
		Audio.play("holo", -6.0)
	_text.text = "GLEAM: " + text
	_show_t = seconds
	_point_to = point_at
	visible = true


func cheer(event: String) -> void:
	say("%s\n%s" % [CHEERS[randi() % CHEERS.size()], event], 3.5)


## Replaces the old tips dialog: the current contract, then a tip.
func talk(tips: Array) -> void:
	var m := GameState.current_mission()
	var tip: String = tips[_talk_idx % tips.size()]
	_talk_idx += 1
	var text := tip
	if not m.is_empty():
		text = "Contract: %s.\n%s" % [m["title"], tip]
	_queued = ""
	say(text, 9.0, Vector3.INF, true)


func showing() -> bool:
	return visible and _show_t > 0.0


func _process(delta: float) -> void:
	if world == null:
		return
	_hints(delta)
	if not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_show_t -= delta
	if _show_t <= 0.0 and _queued != "":
		_text.text = "GLEAM: " + _queued
		_show_t = _queued_t
		_queued = ""
		_point_to = Vector3.INF
	_fade = move_toward(_fade, 1.0 if _show_t > 0.0 else 0.0, delta * (4.0 if _show_t > 0.0 else 2.5))
	if _fade <= 0.0 and _show_t <= 0.0:
		visible = false
		_point_to = Vector3.INF
		return
	var t := Time.get_ticks_msec() * 0.001
	global_transform = Transform3D(cam.global_basis, cam.global_transform * (SPOT + Vector3(0, 0.03 * sin(t * 2.0), 0)))
	_fig.scale = Vector3(1.0, maxf(_fade, 0.05), 1.0) * SCALE * (0.4 + 0.6 * _fade)
	for m in _mats:
		m.set_shader_parameter("strength", _fade)
	_text.modulate.a = _fade
	_text.position = Vector3(0.3, 0.6, 0)
	# Point the way: turn to face the target, raise an arm, show an arrow.
	if _point_to.is_finite():
		var to := _point_to - cam.global_position
		var local := cam.global_basis.inverse() * to
		var flat := Vector2(local.x, local.z)
		# The model faces -Z; turn it to face the target and lift its arm forward.
		var yaw := atan2(-flat.x, -flat.y)
		_fig.rotation.y = lerp_angle(_fig.rotation.y, yaw, delta * 6.0)
		_arm.rotation.x = lerpf(_arm.rotation.x, PI * 0.5, delta * 6.0)
		_arrow.visible = true
		var dir := Vector3(local.x, 0.0, local.z).normalized()
		_arrow.position = Vector3(0, 0.32, 0) + dir * 0.38
		_arrow.basis = Basis(Quaternion(Vector3.UP, dir)) if dir.length() > 0.5 else Basis.IDENTITY
	else:
		_fig.rotation.y = lerp_angle(_fig.rotation.y, PI + 0.5 * sin(t * 0.7), delta * 3.0)
		_arm.rotation.x = lerpf(_arm.rotation.x, 2.2 + 0.5 * sin(t * 7.0) if _show_t > 2.5 else 0.0, delta * 8.0)
		_arrow.visible = false


## Unprompted help: tank full far from the exchange, or a nearly done hexagon.
func _hints(delta: float) -> void:
	if get_tree().paused or world.ending:
		return
	var fp: Vector3 = (world.focus_node() as Node3D).global_position
	var full := GameState.tank_dust >= GameState.tank_capacity() - 0.01
	if not full:
		_tank_hinted = false
	elif not _tank_hinted and world.current_vehicle == null:
		var ex: Vector3 = LunarBase.at(LunarBase.EXCHANGE_POS)
		var d := fp.distance_to(ex)
		if d > 30.0:
			_tank_hinted = true
			say("Tank's full! The Dust Exchange is %d m that way." % int(d), 6.0, ex)
			return
	_hint_in -= delta
	if _hint_in > 0.0 or showing():
		return
	_hint_in = randf_range(POINT_EVERY.x, POINT_EVERY.y)
	var best := -1
	var best_score := -INF
	var fd := fp.normalized()
	for c in HexGrid.count():
		if GameState.hexes_done.has(c):
			continue
		var ang := HexGrid.centers[c].angle_to(fd)
		if ang * TerrainGen.RADIUS > 260.0:
			continue
		var score := AutomationSim.hex_progress(c) * 2.0 - ang * TerrainGen.RADIUS / 260.0
		if score > best_score:
			best_score = score
			best = c
	if best < 0:
		return
	var p := HexGrid.center_point(best)
	var pct := int(AutomationSim.hex_progress(best) * 100.0)
	var dist := int(p.distance_to(fp))
	if pct >= 40:
		say("That hexagon's %d%% done - finish it off! %d m that way." % [pct, dist], 6.0, p)
	else:
		say("Fresh dust in the next hexagon over, %d m that way." % dist, 6.0, p)
