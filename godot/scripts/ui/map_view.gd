class_name MapView
extends Control
## Top-down map: shaded relief generated from the terrain functions on a worker thread,
## region overlays, cleaned-area overlay, base, machines, vehicles, landmarks and player.

const RES := 192
const EXTENT := 640.0

static var _cached: ImageTexture
static var _task := -1
static var _img: Image

var world: Node
var _font: Font


func _ready() -> void:
	_font = UIKit.font_bold()
	custom_minimum_size = Vector2(520, 520)
	if _cached == null and _task == -1:
		# Region tints are read here on the main thread; the worker only gets a copy.
		var tints := PackedColorArray()
		for r in GameData.regions:
			tints.append(Color.html(r["tint"]))
		_task = WorkerThreadPool.add_task(_generate.bind(tints), false, "map")


static func _generate(tints: PackedColorArray) -> void:
	TerrainGen.setup()
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	for y in RES:
		for x in RES:
			var wx := (float(x) / RES * 2.0 - 1.0) * EXTENT
			var wz := (float(y) / RES * 2.0 - 1.0) * EXTENT
			var s := TerrainGen.sample(wx, wz)
			var e := 2.0 * EXTENT / RES
			var hx := TerrainGen.height(wx + e, wz)
			var shade := clampf(0.55 + (s.x - hx) * 0.08 + s.x * 0.004, 0.15, 1.0)
			var reg := TerrainGen.region_at(wx, wz)
			var c: Color = tints[reg] * shade
			c = c.darkened(s.y * 0.25)
			img.set_pixel(x, y, c)
	_img = img


func _process(_delta: float) -> void:
	if _cached == null and _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_cached = ImageTexture.create_from_image(_img)
	queue_redraw()


func _to_map(p: Vector3, rect: Rect2) -> Vector2:
	return rect.position + Vector2((p.x / EXTENT + 1.0) * 0.5, (p.z / EXTENT + 1.0) * 0.5) * rect.size


func _draw() -> void:
	var side := minf(size.x, size.y)
	var rect := Rect2(Vector2((size.x - side) * 0.5, 0), Vector2(side, side))
	draw_rect(rect, Color(0.02, 0.025, 0.04))
	if _cached:
		draw_texture_rect(_cached, rect, false)
	else:
		draw_string(_font, rect.get_center() - Vector2(80, 0), "Charting the Moon...", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIKit.MUTED)
	# Locked regions dim
	var center := _to_map(Vector3.ZERO, rect)
	var k := rect.size.x / (2.0 * EXTENT)
	for idx in range(1, 5):
		if not GameState.region_unlocked(idx):
			var a0: float = [0.0, -PI * 0.5, PI, PI * 0.5][idx - 1] - PI * 0.25
			var pts := PackedVector2Array()
			pts.append(center + Vector2.from_angle(a0) * TerrainGen.ZONE_RADIUS * k)
			for i in 9:
				pts.append(center + Vector2.from_angle(a0 + i * PI * 0.5 / 8.0) * 640.0 * k)
			pts.append(center + Vector2.from_angle(a0 + PI * 0.5) * TerrainGen.ZONE_RADIUS * k)
			for i in 9:
				pts.append(center + Vector2.from_angle(a0 + PI * 0.5 - i * PI * 0.5 / 8.0) * TerrainGen.ZONE_RADIUS * k)
			draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
	draw_arc(center, TerrainGen.ZONE_RADIUS * k, 0, TAU, 64, Color(1, 0.6, 0.2, 0.6), 2.0, true)
	# Dust finder: every 32 m patch of the Moon - green = spotless, amber = started,
	# red tint = untouched dust (shown once the final mission is active).
	var dm := GameState.dirt
	var hunting: bool = GameState.current_mission().get("id", "") == "m_clean_moon"
	var cell := Vector2(TerrainGen.CHUNK * k, TerrainGen.CHUNK * k)
	for key in dm.playable():
		var o := TerrainGen.chunk_origin(key)
		var p0 := _to_map(Vector3(o.x, 0, o.y), rect)
		if dm.clean.has(key):
			draw_rect(Rect2(p0, cell), Color(0.2, 1.0, 0.5, 0.45))
		else:
			var c: DirtMap.DirtChunk = dm.chunks.get(key)
			if c != null and c.modified:
				draw_rect(Rect2(p0, cell), Color(1.0, 0.75, 0.2, 0.2 + 0.4 * dm.chunk_fraction(key)))
			elif hunting:
				draw_rect(Rect2(p0, cell), Color(1.0, 0.25, 0.2, 0.25))
	# The edge of the map continues round the far side of the Moon.
	draw_arc(center, TerrainGen.WRAP_RADIUS * k, 0, TAU, 96, Color(0.6, 0.8, 1.0, 0.5), 1.5, true)
	var pct := "MOON CLEANED  %.1f%%" % (GameState.world_clean_fraction() * 100.0)
	draw_string_outline(_font, rect.position + Vector2(10, 24), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.85))
	draw_string(_font, rect.position + Vector2(10, 24), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.GOOD)
	draw_string_outline(_font, rect.position + Vector2(10, rect.size.y - 10), "Edge of map: keep going to come round the far side", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
	draw_string(_font, rect.position + Vector2(10, rect.size.y - 10), "Edge of map: keep going to come round the far side", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.85, 1.0))
	if hunting and world and world.has_method("dust_target"):
		var t: Vector3 = world.dust_target()
		if t.is_finite():
			_marker(_to_map(t, rect), Color(1.0, 0.35, 0.3), "DUST")
	# Region names
	var names := {1: Vector3(380, 0, 0), 2: Vector3(0, 0, -380), 3: Vector3(-380, 0, 0), 4: Vector3(0, 0, 380), 0: Vector3(0, 0, 90)}
	for idx in names:
		var info := GameData.region(idx)
		var pos := _to_map(names[idx], rect)
		var txt: String = info["name"]
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string_outline(_font, pos - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
		draw_string(_font, pos - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9) if GameState.region_unlocked(idx) else Color(1, 0.5, 0.4))
	# Base
	_marker(_to_map(Vector3(0, 0, -2), rect), UIKit.ACCENT, "BASE")
	# Landmarks
	for lm in TerrainGen.LANDMARK_CRATERS:
		var p := _to_map(Vector3(lm[1], 0, lm[2]), rect)
		draw_arc(p, lm[3] * k, 0, TAU, 32, Color(0.7, 0.85, 1.0, 0.6), 1.5, true)
	if not GameState.flags.get("probe_recovered", false):
		_marker(_to_map(Vector3(Landmarks.PROBE_POS.x, 0, Landmarks.PROBE_POS.y), rect), UIKit.GOOD, "PROBE")
	_marker(_to_map(Vector3(Landmarks.RESEARCH_CENTER.x, 0, Landmarks.RESEARCH_CENTER.y), rect), Color(1.0, 0.6, 0.4), "SALVAGE")
	# Machines
	for m in GameState.machines:
		var p := _to_map(AutomationSim.v3(m["pos"]), rect)
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color.html(GameData.machine(m["id"]).get("color", "#ffffff")))
	# Vehicles
	for v in GameState.vehicles:
		var p := _to_map(AutomationSim.v3(v["pos"]), rect)
		draw_circle(p, 5, Color(0.7, 0.55, 1.0))
	# Player
	if world:
		var fp: Vector3 = world.focus_node().global_position
		var pp := _to_map(fp, rect)
		var yaw: float = world.player.yaw if world.current_vehicle == null else world.current_vehicle.global_rotation.y
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([pp + fwd * 12, pp - fwd * 7 + right * 7, pp - fwd * 4, pp - fwd * 7 - right * 7]), Color.WHITE)
	draw_rect(rect, Color(0.3, 0.4, 0.55), false, 2.0)


func _marker(p: Vector2, c: Color, txt: String) -> void:
	draw_circle(p, 6, c)
	draw_arc(p, 9, 0, TAU, 16, Color(0, 0, 0, 0.7), 2.0, true)
	draw_string_outline(_font, p + Vector2(10, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
	draw_string(_font, p + Vector2(10, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
