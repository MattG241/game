extends Node
## Automated gameplay test suite. Runs headless in CI before the APK is exported:
##   godot --headless --path . res://tests/test_runner.tscn
## Exit code = number of failed checks.

const Boot := preload("res://scripts/boot.gd")

var failures := 0
var passed := 0
var boot: Node
var game: Node


func check(cond: bool, name: String, detail := "") -> void:
	if cond:
		passed += 1
		print("  PASS  ", name)
	else:
		failures += 1
		print("  FAIL  ", name, "  ", detail)


## World point on the ground at map coordinates (x, z) (the old flat layout).
static func M(x: float, z: float, lift := 0.0) -> Vector3:
	return TerrainGen.map_ground(x, z, lift)


## A spot (map coordinates) where the ground and the given map offsets from it start
## dusty: no rocks or cliffs, which have no dust.
static func dusty_spot(offsets: Array, from := Vector2(70.0, 90.0)) -> Vector2:
	var d := DirtMap.new()
	for ring in 40:
		for k in 16:
			var p := from + Vector2.from_angle(k * TAU / 16.0) * ring * 4.0
			var ok := true
			for o in offsets:
				if d.sample(M(p.x + o.x, p.y + o.y)) < 0.45:
					ok = false
					break
			if ok:
				return p
	return from


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	print("=== Lunar Cleanup test suite ===")
	SaveManager.current_slot = 3
	SaveManager.delete_slot(3)
	await _test_data()
	await _test_dirt()
	await _test_menu()
	await _test_world()
	await _test_touch_and_movement()
	await _test_cleaning_loop()
	await _test_economy()
	await _test_ads()
	await _test_menus()
	await _test_waypoint_and_finder()
	await _test_hexagons()
	await _test_vehicle()
	await _test_automation()
	await _test_round_moon_and_ending()
	await _test_save_load()
	await _test_diagnostics()
	print("=== %d passed, %d failed ===" % [passed, failures])
	SaveManager.delete_slot(3)
	get_tree().quit(failures)


func _test_data() -> void:
	print("[data]")
	TerrainGen.setup()
	check(GameData.tools.size() == 12, "12 cleaning tools defined")
	check(GameData.vehicles.size() == 4, "4 vehicles defined")
	check(GameData.missions.size() >= 20, "at least 20 missions", str(GameData.missions.size()))
	var upgrades: int = GameData.tools.size() * int(GameData.economy["tool_upgrade"]["max_level"]) + GameData.economy["tank_levels"].size() - 1 + GameData.economy["battery_levels"].size() - 1 + GameData.economy["boots_levels"].size() - 1
	check(upgrades >= 20, "at least 20 progression upgrades", str(upgrades))
	check(GameData.regions.size() == 5, "5 regions")
	check(GameData.machines.size() >= 8, "automation machines defined")
	var a := TerrainGen.height(123.4, -55.6)
	var b := TerrainGen.height(123.4, -55.6)
	check(is_equal_approx(a, b), "terrain is deterministic")
	check(absf(TerrainGen.height(0, 0)) < 0.01, "base pad is flat")
	print("[round moon]")
	var rt := TerrainGen.dir_to_map(TerrainGen.map_to_dir(123.0, -456.0))
	check(rt.distance_to(Vector2(123.0, -456.0)) < 0.01, "map coordinates round-trip onto the sphere", str(rt))
	check(absf(TerrainGen.map_to_dir(0.0, 400.0).angle_to(Vector3.UP) * TerrainGen.RADIUS - 400.0) < 0.01, "map distance from base = distance over the surface")
	var keys_ok := true
	var nb_ok := true
	for k in TerrainGen.all_chunks():
		if TerrainGen.key_of(TerrainGen.chunk_center_dir(k)) != k:
			keys_ok = false
		var nb := TerrainGen.neighbours(k)
		if nb.size() < 7 or nb.size() > 8:
			nb_ok = false
	check(keys_ok and TerrainGen.all_chunks().size() == 6 * TerrainGen.N * TerrainGen.N, "every chunk of the cube-sphere maps back to itself")
	check(nb_ok, "every chunk has 7-8 neighbours (also across cube faces)")
	check(TerrainGen.frame(Vector3.UP).is_equal_approx(Basis.IDENTITY), "at the base the local frame is the world frame")
	var fd := TerrainGen.map_to_dir(500.0, 300.0)
	var fb := TerrainGen.frame(fd)
	check(fb.y.is_equal_approx(fd) and absf(fb.x.dot(fb.z)) < 1e-4 and absf(fb.x.dot(fb.y)) < 1e-4, "local frames stand upright on the sphere")
	var hp := M(-250.0, 420.0)
	check(absf(TerrainGen.yaw_of(hp, TerrainGen.heading_basis(hp, 1.234)) - 1.234) < 1e-4, "headings convert to and from the local frame")
	var lp := TerrainGen.map_ground(0.0, 930.0)
	check(lp.length() > TerrainGen.RADIUS - 60.0 and lp.length() < TerrainGen.RADIUS + 60.0, "far side of the Moon is solid ground", str(lp.length()))


## A dust file from before the Moon was round: [[Vector2i key, 128x128 mask], ...].
static func old_dirt_blob(chunks: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_data("LCDM".to_ascii_buffer())
	buf.put_u32(2)
	buf.put_u32(chunks.size())
	for e in chunks:
		var comp: PackedByteArray = (e[1] as PackedByteArray).compress(FileAccess.COMPRESSION_ZSTD)
		buf.put_32(e[0].x)
		buf.put_32(e[0].y)
		buf.put_u32(16384 * 200)
		buf.put_u32(comp.size())
		buf.put_data(comp)
	return buf.data_array


func _test_dirt() -> void:
	print("[dirt map]")
	var dm := DirtMap.new()
	check(dm.sample(M(4.0, 33.0)) > 0.0, "ground starts dusty before anything is built on it")
	dm.add_cover_circle(M(4.0, 30.0), 8.3)
	dm.add_cover_box(TerrainGen.map_xform(-30.0, 40.0, 0.0), 2.0, 1.0)
	check(dm.sample(M(4.0, 33.0)) == 0.0 and dm.sample(M(-30.0, 40.0)) == 0.0, "no hidden dust under pads and buildings (existing chunks)")
	check(dm.sample(M(4.0, 45.0)) > 0.0 and dm.sample(M(-30.0, 42.0)) > 0.0, "open ground next to them is still dusty")
	var rp := dusty_spot([Vector2(0, 2.5), Vector2(2.5, 0)], Vector2(150, 150))
	dm.add_cover_box(LunarBase.at_xform(Vector3(rp.x, 0, rp.y), PI * 0.5), 3.0, 1.0)
	check(dm.sample(M(rp.x, rp.y + 2.5)) == 0.0 and dm.sample(M(rp.x + 2.5, rp.y)) > 0.0, "rotated covers follow the building's yaw (chunks made later)", str(rp))
	# Unreachable dust: under rocks and on cliffs
	var rk_found := false
	for key in TerrainGen.all_chunks():
		if not TerrainGen.chunk_has_rocks(key):
			continue
		var rk := TerrainGen.rock(key, 0, TerrainGen.big_rocks_in(key))
		if rk.w >= 0.0 and rk.z > 1.0:
			rk_found = true
			check(dm.sample(TerrainGen.chunk_dir(key, rk.x, rk.y) * TerrainGen.RADIUS) == 0.0, "no dust hidden under boulders", str(key))
			break
	check(rk_found, "found a boulder to test")
	var steep_ok := true
	var steep_n := 0
	var key2 := TerrainGen.key_of(TerrainGen.map_to_dir(-6.0, -250.0))
	var mask := TerrainGen.unreachable_mask(key2)
	var init := TerrainGen.initial_dirt(key2)
	for i in mask.size():
		if mask[i] != 0:
			steep_n += 1
			if init[i] != 0:
				steep_ok = false
	check(steep_ok, "unreachable ground (rocks, cliffs) never starts dusty", str(steep_n))
	# 100% tracking
	var pk := dm.playable()
	check(pk.size() == 6 * TerrainGen.N * TerrainGen.N, "the whole Moon is a fixed set of patches", str(pk.size()))
	check(not dm.world_clean() and dm.world_fraction() < 0.999, "a fresh Moon is not clean")
	var cd := DirtMap.new()
	var ckey := TerrainGen.key_of(TerrainGen.map_to_dir(80.0, 80.0))
	cd.stamp(DirtMap.Shape.RECT, TerrainGen.chunk_center_dir(ckey) * TerrainGen.RADIUS, 26.0, 26.0, Vector3.ZERO, 10.0, 1e9)
	check(cd.get_chunk(ckey).dirty == 0 and cd.clean.has(ckey), "a fully scrubbed patch is recorded as spotless")
	check(cd.chunk_state(ckey) == 1.0 and cd.chunk_state(TerrainGen.key_of(Vector3.DOWN)) == 0.0, "map shows which patches are done")
	check(cd.nearest_dust(M(80, 80)).is_finite(), "dust finder points at the nearest dust left")
	var d := DirtMap.new()
	var sp := dusty_spot([Vector2.ZERO, Vector2(3, 0), Vector2(10, 0), Vector2(-10, 0), Vector2(-11, 0), Vector2(-9, 0)])
	var x := sp.x
	var z := sp.y
	var before := d.sample(M(x, z))
	check(before > 0.4, "ground starts dusty", str(before))
	var area1 := d.stamp(DirtMap.Shape.ROUND, M(x, z), 0.5, 0.0, Vector3.ZERO, 0.5, 1e9)
	var mid := d.sample(M(x, z))
	check(area1 > 0.0 and mid < before, "stamping removes dirt where brushed", "%f -> %f" % [before, mid])
	check(d.sample(M(x + 3.0, z)) > 0.4, "dirt elsewhere untouched")
	var area2 := d.stamp(DirtMap.Shape.ROUND, M(x, z), 0.5, 0.0, Vector3.ZERO, 5.0, 1e9)
	# (brush edges remove less per pass, so re-check well inside the cleaned circle)
	var area3 := d.stamp(DirtMap.Shape.ROUND, M(x, z), 0.3, 0.0, Vector3.ZERO, 5.0, 1e9)
	check(d.sample(M(x, z)) == 0.0, "full strength clears completely")
	check(area3 == 0.0, "already-cleaned ground yields nothing", str(area3))
	var total := area1 + area2
	check(total > 0.6 and total < 0.95, "removed area matches brush footprint (~0.785 m2)", str(total))
	var capped := d.stamp(DirtMap.Shape.ROUND, M(x + 10.0, z), 1.0, 0.0, Vector3.ZERO, 5.0, 0.1)
	# Can overshoot by at most one texel.
	check(capped <= 0.1 + TerrainGen.TEXEL * TerrainGen.TEXEL * 1.5, "budget caps removal (tank full logic)", str(capped))
	var rect := d.stamp(DirtMap.Shape.RECT, M(x - 10.0, z), 2.0, 0.5, Vector3(1, 0, 0), 5.0, 1e9)
	check(rect > 2.4 and rect < 4.4, "wide brushes clean rectangles (~4 m2 minus soft edges)", str(rect))
	# Cross-chunk and cross-face stamps: the brush continues seamlessly into the next patch.
	var face_edge := Vector3i(0, TerrainGen.N - 1, TerrainGen.N / 2)
	for j in TerrainGen.N:
		var fk := Vector3i(0, TerrainGen.N - 1, j)
		var probe := DirtMap.new()
		var ep := TerrainGen.chunk_dir(fk, 1.0, 0.5) * TerrainGen.RADIUS
		var ac := (TerrainGen.chunk_dir(fk, 1.05, 0.5) - TerrainGen.chunk_dir(fk, 0.95, 0.5)).normalized()
		if probe.sample(ep - ac * 0.3) > 0.4 and probe.sample(ep + ac * 0.3) > 0.4:
			face_edge = fk
			break
	for k in [ckey, face_edge]:
		var e0 := TerrainGen.chunk_dir(k, 1.0, 0.5) * TerrainGen.RADIUS
		var across := (TerrainGen.chunk_dir(k, 1.05, 0.5) - TerrainGen.chunk_dir(k, 0.95, 0.5)).normalized()
		var ed := DirtMap.new()
		var edge := ed.stamp(DirtMap.Shape.ROUND, e0, 1.0, 0.0, Vector3.ZERO, 5.0, 1e9)
		var a_in := ed.sample(e0 - across * 0.3)
		var a_out := ed.sample(e0 + across * 0.3)
		check(edge > 1.5 and a_in == 0.0 and a_out == 0.0 and TerrainGen.key_of((e0 - across * 0.3).normalized()) != TerrainGen.key_of((e0 + across * 0.3).normalized()),
			"stamps span patch borders" + (" (across a cube face)" if k.x == 0 else ""), "%f %f %f" % [edge, a_in, a_out])
	# Persistence encode/decode
	var bytes := DirtMap.encode_snapshot(d.snapshot())
	var d2 := DirtMap.new()
	check(d2.decode(bytes), "dirt data decodes")
	check(d2.sample(M(x, z)) == 0.0 and d2.sample(M(x + 3.0, z)) > 0.4, "decoded dirt matches")
	check(not DirtMap.new().decode(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])), "corrupted dirt data is rejected")
	# Old flat-world saves: cleaned ground is carried onto the sphere.
	var cleaned := PackedByteArray()
	cleaned.resize(128 * 128)
	var od := DirtMap.new()
	check(od.decode(old_dirt_blob([[Vector2i(2, 2), cleaned]])) and od.has_legacy(), "old flat dust file is read")
	check(od.sample(M(80.0, 80.0)) == 0.0 and od.sample(M(70.0, 70.0)) == 0.0, "ground cleaned on the flat Moon is clean on the round one")
	check(od.sample(M(80.0, 100.0)) > 0.3, "ground not cleaned before is still dusty")
	var re := DirtMap.new()
	check(re.decode(DirtMap.encode_snapshot(od.snapshot())) and re.sample(M(80.0, 80.0)) == 0.0 and not re.has_legacy(), "migrated cleaning saves in the new format")


func _test_menu() -> void:
	print("[main menu]")
	# After a crash the first screen is a plain 2D one with COPY CRASH LOG.
	Diagnostics.previous_crashed = true
	var rb: Node = Boot.new()
	add_child(rb)
	await frames(3)
	var copy_found := false
	for b in rb.find_children("*", "Button", true, false):
		if (b as Button).text == "COPY CRASH LOG":
			copy_found = true
	check(copy_found and rb.current == null, "after a crash, a plain recovery screen offers the crash log first")
	rb.queue_free()
	await frames(2)
	Diagnostics.previous_crashed = false
	boot = Boot.new()
	add_child(boot)
	await frames(5)
	check(boot.current != null and boot.current.get_script() != null, "main menu loads")
	check(boot.current.get_child_count() > 0, "main menu built its scene")


func _test_world() -> void:
	print("[new game]")
	boot.start_game(-3)
	await frames(10)
	game = get_tree().get_first_node_in_group("world")
	check(game != null, "new game creates a world")
	check(game.player != null and game.terrain.active_chunks() >= 9, "player and terrain chunks exist", str(game.terrain.active_chunks()))
	game.menu.close()
	await frames(30)
	var p: Vector3 = game.player.global_position
	check(TerrainGen.altitude(p) > -0.5 and TerrainGen.altitude(p) < 1.0, "player stands on the ground", str(TerrainGen.altitude(p)))
	check(game.player.global_basis.y.dot(p.normalized()) > 0.99, "player stands upright on the sphere")


func _test_touch_and_movement() -> void:
	print("[touch input + movement]")
	var c: TouchControls = game.controls
	var pl: Player = game.player
	var start := pl.global_position
	var yaw0 := pl.yaw
	# Joystick: touch on the left side and drag upward
	_touch(c, 0, Vector2(200, 500), true)
	_drag(c, 0, Vector2(200, 420))
	check(c.move_vector.y < -0.5, "joystick produces forward input", str(c.move_vector))
	await frames(60)
	_touch(c, 0, Vector2(200, 420), false)
	var moved := pl.global_position.distance_to(start)
	check(moved > 1.5, "player walks with the joystick", str(moved))
	# Look: swipe on the right half
	_touch(c, 1, Vector2(900, 300), true)
	_drag(c, 1, Vector2(800, 300))
	await frames(2)
	_touch(c, 1, Vector2(800, 300), false)
	check(not is_equal_approx(pl.yaw, yaw0), "swipe rotates the camera")
	# Border on foot: walking into a locked region stops smoothly (no back-and-forth).
	var edge := M(5, -140, 0.3)
	game.terrain.prewarm(edge)
	pl.global_position = edge
	pl.yaw = 0.0
	c.move_vector = Vector2(0.15, -1)
	var last := pl.global_position
	var last_dir := Vector3.ZERO
	var flips := 0
	for i in 400:
		await get_tree().physics_frame
		var step := pl.global_position - last
		step -= pl.up_direction * step.dot(pl.up_direction)
		if step.length() > 0.05 and last_dir.length() > 0.05 and step.normalized().dot(last_dir.normalized()) < -0.5:
			flips += 1
		last_dir = step
		last = pl.global_position
	var e2 := pl.global_position
	check(flips == 0 and GameState.region_unlocked(TerrainGen.region_of(e2)), "walking into a locked border stops smoothly", "flips=%d" % flips)
	# Trapped inside a locked region (e.g. old save): player is moved out, not stuck.
	var trapped := M(0, -200, 0.5)
	game.terrain.prewarm(trapped)
	pl.global_position = trapped
	for i in 30:
		await get_tree().physics_frame
	var t2 := pl.global_position
	check(GameState.region_unlocked(TerrainGen.region_of(t2)), "player trapped in a locked region is moved out")
	c.move_vector = Vector2.ZERO
	pl.global_position = TerrainGen.surface(start, 0.5)
	game.terrain.prewarm(pl.global_position)
	await frames(10)
	# Clean button
	var cb := c.button_center("clean")
	_touch(c, 2, cb, true)
	await frames(1)
	check(pl.cleaner.cleaning, "CLEAN button starts cleaning")
	_touch(c, 2, cb, false)
	await frames(1)
	check(not pl.cleaner.cleaning, "releasing CLEAN stops cleaning")
	# Regression: a finger on the joystick or look area must never start cleaning
	# (Android emulates a mouse click for the first finger).
	_touch(c, 3, Vector2(200, 500), true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.device = InputEvent.DEVICE_ID_EMULATION
	Input.parse_input_event(click)
	await frames(3)
	check(not pl.cleaner.cleaning, "joystick touch / emulated click does not start cleaning")
	_touch(c, 3, Vector2(200, 500), false)
	# Regression: a release that arrives while a menu is open still stops cleaning.
	_touch(c, 4, cb, true)
	await frames(1)
	game.controls.enabled = false
	_touch(c, 4, cb, false)
	game.controls.enabled = true
	await frames(2)
	check(not pl.cleaner.cleaning, "release during a menu still stops cleaning")
	# Regression: an OS-cancelled touch (gesture bar) releases everything.
	_touch(c, 5, cb, true)
	await frames(1)
	var cancel := InputEventScreenTouch.new()
	cancel.index = 5
	cancel.position = cb
	cancel.pressed = false
	cancel.canceled = true
	c._input(cancel)
	await frames(2)
	check(not pl.cleaner.cleaning and c.held.is_empty(), "cancelled touch stops cleaning")


func _touch(c: Control, idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	c._input(e)


func _drag(c: Control, idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	c._input(e)


func _test_cleaning_loop() -> void:
	print("[cleaning loop]")
	var pl: Player = game.player
	pl.global_position = M(60, 20, 0.5)
	pl.pitch = -0.9
	game.terrain.prewarm(pl.global_position)
	await frames(20)
	GameState.tank_dust = 0.0
	GameState.tank_value = 0.0
	var aim: Vector3 = pl.cleaner.aim_point
	var before := GameState.dirt.sample(aim)
	game.controls.held["clean"] = true
	await frames(45)
	game.controls.held.erase("clean")
	await frames(1)
	var after := GameState.dirt.sample(aim)
	check(GameState.tank_dust > 0.0, "dust enters the container", str(GameState.tank_dust))
	check(after < before, "toothbrush removes dirt at the aim point", "%f -> %f" % [before, after])
	check(GameState.stat("m2_cleaned") > 0.0, "cleaned area is recorded")
	# Full tank stops collection
	GameState.tank_dust = GameState.tank_capacity()
	pl.yaw += 1.2
	await frames(5)
	var aim2: Vector3 = pl.cleaner.aim_point
	var b2 := GameState.dirt.sample(aim2)
	game.controls.held["clean"] = true
	await frames(30)
	game.controls.held.erase("clean")
	check(is_equal_approx(GameState.tank_dust, GameState.tank_capacity()), "container stops collecting when full")
	check(is_equal_approx(GameState.dirt.sample(aim2), b2), "dirt is not wasted when the tank is full")
	# Mission progression from cleaning
	GameState.check_missions()
	check(GameState.missions_done.has("m_first_m2") or GameState.stat("m2_cleaned") < 1.0, "first mission tracks cleaning")


func _test_economy() -> void:
	print("[economy]")
	GameState.tank_dust = 100.0
	GameState.tank_value = 150.0
	var c0 := GameState.credits
	game.sell_all()
	var expected := 150.0 * GameState.dust_price()
	check(is_equal_approx(GameState.credits - c0, expected), "selling awards value x price", "%f vs %f" % [GameState.credits - c0, expected])
	check(GameState.tank_dust == 0.0, "selling empties the tank")
	GameState.credits = 0.0
	check(not GameState.buy_tool("big_toothbrush"), "can't buy without credits")
	GameState.credits = 100000.0
	check(GameState.buy_tool("big_toothbrush"), "purchase equipment")
	check(GameState.equipped == "big_toothbrush", "new tool is equipped")
	var s0 := GameState.tool_stats("big_toothbrush")
	check(GameState.upgrade_tool("big_toothbrush"), "upgrade tool")
	var s1 := GameState.tool_stats("big_toothbrush")
	check(s1["strength"] > s0["strength"] and s1["radius"] > s0["radius"], "upgrades raise strength and width")
	# Upgraded tool removes more per stamp
	var d := DirtMap.new()
	var tp := dusty_spot([Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(10, 0), Vector2(11, 0), Vector2(9, 0)], Vector2(200, 200))
	var a0 := d.stamp(DirtMap.Shape.ROUND, M(tp.x, tp.y), s0["radius"], 0, Vector3.ZERO, s0["strength"] * 0.05, 1e9)
	var a1 := d.stamp(DirtMap.Shape.ROUND, M(tp.x + 10.0, tp.y), s1["radius"], 0, Vector3.ZERO, s1["strength"] * 0.05, 1e9)
	check(a1 > a0, "upgraded tool cleans more per second", "%f vs %f" % [a0, a1])
	var cap0 := GameState.tank_capacity()
	check(GameState.buy_tank_upgrade() and GameState.tank_capacity() > cap0, "storage upgrade increases capacity")
	check(GameState.buy_permit(1) == GameState.permit_requirement_met(1), "permit purchase respects requirements")
	GameState.missions_done.append("m_sell_1")
	GameState.regions[1] = false
	check(GameState.buy_permit(1) and GameState.region_unlocked(1), "permit unlocks region")


func _test_ads() -> void:
	print("[ads and remove-ads purchase]")
	check(not Ads.available and not IAP.available, "no ad or billing SDK off-device (game still runs)")
	check(not Ads.rewarded_ready(), "no rewarded offer without an ad SDK")
	check(Ads._unit("rewarded").begins_with("ca-app-pub-3940256099942544/") and Ads._unit("interstitial").begins_with("ca-app-pub-3940256099942544/"),
		"non-Play builds use Google test ad units")
	check(str(Ads.config.get("rewarded_unit_android", "")) != Ads._unit("rewarded"), "Play build has its own real ad units")
	var saved_removed := IAP.ads_removed
	IAP.ads_removed = false
	Ads.reset_pacing()
	var now := 10000.0
	check(not Ads.interstitial_allowed(120.0, now), "no interstitial in the first 10 minutes")
	check(Ads.interstitial_allowed(900.0, now), "interstitial allowed later at a natural break")
	Ads.simulate = true
	IAP.simulate = true
	GameState.stats["play_time"] = 900.0
	GameState.tank_dust = 50.0
	GameState.tank_value = 100.0
	var shown0 := Ads.interstitials_shown
	game.sell_all()
	check(Ads.interstitials_shown == shown0 + 1, "selling can show an interstitial")
	check(not game.hud._offer.visible, "no double offer on top of an interstitial")
	GameState.tank_dust = 50.0
	GameState.tank_value = 100.0
	game.sell_all()
	check(Ads.interstitials_shown == shown0 + 1, "interstitials are spaced out (5 min)")
	check(game.hud._offer.visible, "sale offers an optional rewarded double")
	var c0 := GameState.credits
	game.hud._take_double()
	check(is_equal_approx(GameState.credits - c0, game.hud._offer_amount) and c0 > 0.0, "watching the rewarded ad doubles the sale")
	check(not Ads.interstitial_allowed(900.0, Ads._now() + 30.0), "no interstitial right after a rewarded ad")
	# Low battery -> optional instant recharge
	GameState.battery = 1.0
	game.hud._recharge_cooldown = 0.0
	game.hud._bat_row.visible = true
	await frames(2)
	check(game.hud._recharge.visible, "low battery offers a rewarded recharge")
	game.hud._take_recharge()
	check(GameState.battery >= GameState.battery_capacity() - 0.01, "rewarded recharge fills the battery")
	# Touches on the HUD offer must not be eaten by the look area
	game.hud.offer_double(30.0)
	await frames(1)
	var r: Rect2 = game.hud._offer.get_global_rect()
	_touch(game.controls, 5, r.get_center(), true)
	check(game.controls._look_index != 5, "HUD ad button takes the touch, not the camera")
	_touch(game.controls, 5, r.get_center(), false)
	game.hud._offer.visible = false
	# Remove ads
	Ads.reset_pacing()
	IAP.buy()
	check(IAP.ads_removed and bool(Settings.get_value("ads_removed", false)), "remove-ads purchase is stored")
	check(not Ads.interstitial_allowed(900.0, 1e6), "remove ads stops interstitials")
	check(Ads.rewarded_ready(), "rewarded bonuses stay available after removing ads")
	Ads.simulate = false
	IAP.simulate = false
	IAP.ads_removed = saved_removed
	Settings.set_value("ads_removed", saved_removed)
	Ads.reset_pacing()


func _test_round_moon_and_ending() -> void:
	print("[round moon: no edge, all the way round]")
	var saved_regions := GameState.regions.duplicate()
	for i in GameState.regions.size():
		GameState.regions[i] = true
	if game.current_vehicle:
		game.exit_vehicle()
	var p: Player = game.player
	var c: TouchControls = game.controls
	# Walk straight over the far (south) pole: it's just more ground.
	var start := M(920.0, 6.0, 0.4)
	game.terrain.prewarm(start)
	p.global_position = start
	p.velocity = Vector3.ZERO
	await frames(5)
	p.global_basis = TerrainGen.upright(p.global_position, Vector3.DOWN - p.global_position.normalized() * -1.0)
	var pole := TerrainGen.surface(Vector3.DOWN)
	p.global_basis = TerrainGen.upright(p.global_position, pole - p.global_position)
	c.move_vector = Vector2(0, -1)
	var lowest := INF
	var bad := 0
	var d_pole := INF
	for i in 600:
		await get_tree().physics_frame
		var gp := p.global_position
		if not gp.is_finite():
			bad += 1
			break
		lowest = minf(lowest, TerrainGen.altitude(gp))
		d_pole = minf(d_pole, gp.normalized().angle_to(Vector3.DOWN) * TerrainGen.RADIUS)
		if p.global_basis.y.dot(gp.normalized()) < 0.98:
			bad += 1
	c.move_vector = Vector2.ZERO
	var end := p.global_position
	check(bad == 0 and lowest > -0.6, "walking over the far pole stays on the ground, standing upright", "lowest %.2f bad %d" % [lowest, bad])
	check(d_pole < 6.0 and end.normalized().angle_to(start.normalized()) * TerrainGen.RADIUS > 25.0, "walked across the far pole and out the other side", "closest %.1f m" % d_pole)
	check(TerrainGen.altitude(end) > -0.5 and p.is_on_floor(), "standing on solid ground on the far side")
	var sky_up: Vector3 = game.env._frame.y
	check(sky_up.dot(p.camera.global_position.normalized()) > 0.999, "sun and Earth travel with you: always day overhead")
	# A rover on the far side sits on the sphere too (gravity towards the centre).
	var fv: LunarVehicle = game.vehicles[0]
	var fvp := M(700.0, -200.0, 1.5)
	game.terrain.prewarm(fvp)
	fv.global_transform = Transform3D(TerrainGen.heading_basis(fvp, 0.0), fvp)
	fv.linear_velocity = Vector3.ZERO
	fv.freeze = false
	fv.sleeping = false
	game.terrain.ensure_collision_near(fvp)
	for i in 120:
		fv.freeze = false
		await get_tree().physics_frame
	var fva := TerrainGen.altitude(fv.global_position)
	check(fva > -0.5 and fva < 2.5 and fv.global_basis.y.dot(fv.global_position.normalized()) > 0.9, "a parked rover settles on its wheels on the far side", "alt %.2f" % fva)
	game.recall_vehicle(0)
	p.global_position = LunarBase.spawn_point()
	game.terrain.prewarm(p.global_position)
	await frames(5)
	GameState.regions = saved_regions
	# Ending
	check(not game.can_fly_home(), "lander won't leave before the Moon is clean")
	GameState.missions_done.append("m_clean_moon")
	game._lander_action()
	check(game.ending != null and not game.hud.visible, "lander lift-off cinematic starts")
	await frames(5)
	game.ending._t = Ending.LIFT_AT + 4.0
	await frames(3)
	check(TerrainGen.altitude(game.base.lander.global_position) > 10.0, "lander climbs into the sky", str(TerrainGen.altitude(game.base.lander.global_position)))
	game.ending._t = Ending.FADE_AT + 2.0
	await frames(3)
	check(GameState.flags.get("went_home", false) and GameState.missions_done.has("m_go_home"), "end screen: your work here is done")
	game.ending.finish()
	await frames(2)
	check(game.ending == null and game.hud.visible and TerrainGen.altitude(game.base.lander.global_position) < 1.0, "keep cleaning returns to the game")
	GameState.missions_done.erase("m_clean_moon")
	GameState.missions_done.erase("m_go_home")
	GameState.flags.erase("went_home")


func _test_waypoint_and_finder() -> void:
	print("[map waypoint + dust finder]")
	game.open_menu("map")
	await frames(3)
	var mv: MapView = game.menu._content.get_child(0)
	mv._center_on_focus()
	await frames(2)
	var centre := mv.size * 0.5
	var d := mv.globe_dir_at(centre)
	check(d.angle_to(game.focus_node().global_position.normalized()) < 0.05, "tapping the middle of the map points at where you are")
	check(mv.globe_dir_at(Vector2(2, 2)) == Vector3.ZERO, "tapping beside the globe does nothing")
	mv._tap(centre + Vector2(60, 0))
	var w: Vector3 = game.waypoint()
	check(w.is_finite() and absf(TerrainGen.altitude(w)) < 0.1, "tapping the globe sets a waypoint on the ground")
	game.menu.close()
	await frames(3)
	check(game.hud._finder_on and game.hud._finder_wp, "the HUD arrow points to the waypoint")
	game.player.global_position = TerrainGen.surface(w, 0.3)
	await frames(70)
	check(not game.waypoint().is_finite(), "reaching the waypoint clears it")
	var saved := GameState.missions_done.duplicate()
	for m in GameData.missions:
		if m["id"] != "m_clean_moon" and m["id"] != "m_go_home" and not GameState.missions_done.has(m["id"]):
			GameState.missions_done.append(m["id"])
	check(str(GameState.current_mission().get("id", "")) == "m_clean_moon" and not game.hunting_dust(), "no dust arrow in the final mission before 60% is clean")
	GameState.missions_done = saved


func _test_hexagons() -> void:
	print("[hexagon sectors]")
	HexGrid.setup()
	check(HexGrid.count() == 10 * HexGrid.FREQ * HexGrid.FREQ + 2, "the Moon is split into hexagons (and 12 pentagons)", str(HexGrid.count()))
	var own_ok := true
	for i in HexGrid.count():
		if HexGrid.cell_of(HexGrid.centers[i]) != i:
			own_ok = false
	check(own_ok and HexGrid.cell_of(Vector3.UP) == HexGrid.cell_of(HexGrid.centers[0]), "every hexagon owns its centre")
	var cell := HexGrid.cell_of(M(150.0, 120.0).normalized())
	var dm := DirtMap.new()
	var dusty := 0
	for d in HexGrid.samples(cell):
		if dm.sample(d * TerrainGen.RADIUS) > 0.05:
			dusty += 1
	for k in HexGrid.chunks_of(cell):
		dm.sweep_cell(k, cell)
	var left := 0
	for d in HexGrid.samples(cell):
		if dm.sample(d * TerrainGen.RADIUS) > 0.0:
			left += 1
	check(dusty > 100 and left == 0, "the finishing sweep clears a whole hexagon", "%d dusty, %d left" % [dusty, left])
	var outside := HexGrid.centers[cell].slerp(Vector3.DOWN, 0.4)
	check(dm.sample(outside * TerrainGen.RADIUS) > 0.3, "ground outside the hexagon is untouched")
	# In the game: a hexagon at 90% gets finished and pays a bonus.
	var pl: Player = game.player
	var here := HexGrid.cell_of(pl.global_position)
	for k in HexGrid.chunks_of(here):
		GameState.dirt.sweep_cell(k, here)
	var cr := GameState.credits
	var done0 := GameState.hexes_done.size()
	for i in 90:
		await get_tree().process_frame
		if GameState.hexes_done.size() > done0:
			break
	check(GameState.hexes_done.has(here) and GameState.credits > cr, "clearing a hexagon completes it with a bonus", "%d hexes" % GameState.hexes_done.size())
	check(game.current_hex_fraction() == 1.0, "HUD shows the hexagon as done")


func _test_menus() -> void:
	print("[menus]")
	var ok := true
	for t in GameMenu.TABS:
		game.open_menu(t[0])
		await get_tree().process_frame
		if not game.menu.visible or game.menu._content.get_child_count() == 0:
			ok = false
			print("    tab failed: ", t[0])
	check(ok, "every menu tab opens and has content")
	check(get_tree().paused, "menus pause gameplay")
	game.menu.close()
	await get_tree().process_frame
	check(not get_tree().paused and not game.menu.visible, "closing menu resumes")
	game.supervisor_talk()
	await get_tree().process_frame
	check(game.menu.visible, "supervisor dialog shows")
	game.menu.close()


func _test_vehicle() -> void:
	print("[vehicles]")
	GameState.credits = 1e7
	check(GameState.buy_vehicle("vacuum_buggy"), "buy vehicle")
	await frames(2)
	check(game.vehicles.size() == 1, "vehicle spawned")
	var v: LunarVehicle = game.vehicles[0]
	game.terrain.prewarm(v.global_position)
	game.enter_vehicle(v)
	await frames(30)
	check(game.mode == "vehicle" and v.driving, "enter vehicle")
	var start := v.global_position
	var fwd := -v.global_basis.z
	game.controls.move_vector = Vector2(0, -1)
	await frames(150)
	game.controls.move_vector = Vector2.ZERO
	var delta := v.global_position - start
	check(delta.length() > 3.0, "vehicle drives", str(delta.length()))
	check(delta.dot(fwd) > 0.0, "throttle drives forward", str(delta.dot(fwd)))
	var yaw0 := TerrainGen.yaw_of(v.global_position, v.global_basis)
	game.controls.move_vector = Vector2(-0.8, -0.6)
	await frames(90)
	game.controls.move_vector = Vector2.ZERO
	check(absf(wrapf(TerrainGen.yaw_of(v.global_position, v.global_basis) - yaw0, -PI, PI)) > 0.05, "vehicle steers")
	# Vacuum deck uses the shared dirt map
	var h0 := v.hopper()
	v.cleaning = true
	game.controls.move_vector = Vector2(0, -0.6)
	await frames(90)
	v.cleaning = false
	game.controls.move_vector = Vector2.ZERO
	check(v.hopper() > h0, "vacuum buggy collects dust into its hopper", str(v.hopper()))
	# Stuck on a steep slope: pin it in place with throttle held, expect auto-recovery.
	var steep := M(118.0, -111.5, 0.5)
	game.terrain.prewarm(steep)
	v.global_transform = Transform3D(TerrainGen.heading_basis(steep, 0.0) * Basis(Vector3.RIGHT, 0.9), steep)
	game.controls.move_vector = Vector2(0, -1)
	var stuck_from := v.global_position
	for i in 260:
		v.linear_velocity = Vector3.ZERO
		await get_tree().physics_frame
		if v.global_position.distance_to(stuck_from) > 2.0:
			break
	game.controls.move_vector = Vector2.ZERO
	check(v.global_position.distance_to(stuck_from) > 2.0 and v.global_basis.y.dot(v.global_position.normalized()) > 0.9, "stuck vehicle recovers to flat ground", str(v.global_position))
	# Locked region border: one clean put-back, no shaking at the boundary.
	GameState.regions[2] = false
	var inside := M(0, -120, 1.2)
	game.terrain.prewarm(inside)
	v.global_transform = Transform3D(TerrainGen.heading_basis(inside, 0.0), inside)
	for i in 40:
		await get_tree().physics_frame
	game.controls.move_vector = Vector2(0, -1)
	var in_locked := 0
	for i in 400:
		await get_tree().physics_frame
		var q := v.global_position
		if not GameState.region_unlocked(TerrainGen.region_of(q)):
			in_locked += 1
	game.controls.move_vector = Vector2.ZERO
	var q2 := v.global_position
	check(GameState.region_unlocked(TerrainGen.region_of(q2)) and in_locked < 5, "vehicle is put back from a locked region without shaking", "frames in locked=%d" % in_locked)
	# Physics blow-up guard
	v.linear_velocity = Vector3(NAN, 0, 0)
	await frames(2)
	check(v.global_position.is_finite() and v.linear_velocity.is_finite(), "vehicle recovers from invalid physics state")
	v.braking = true
	await frames(60)
	v.braking = false
	game.exit_vehicle()
	await frames(5)
	check(game.mode == "foot" and game.player.visible, "exit vehicle")
	game.write_state()
	var saved_pos := AutomationSim.v3(GameState.vehicles[0]["pos"])
	check(saved_pos.distance_to(v.global_position) < 0.5 and saved_pos.distance_to(start) > 3.0, "vehicle position saved", str(saved_pos))


func _test_automation() -> void:
	print("[automation]")
	var auto: Automation = game.automation
	var sim := auto.sim
	GameState.credits = 1e7
	var near_base := M(30, 10)
	check(sim.can_place("dust_collector", M(0, 0)) != "", "can't build inside the base")
	check(sim.can_place("dust_collector", M(600, 200)) == "" or sim.can_place("dust_collector", M(600, 200)) == "Ground too steep", "machines can be built anywhere round the Moon", sim.can_place("dust_collector", M(600, 200)))
	auto.add_machine("solar_array", M(-36, 10), 0.0)
	var solar: Dictionary = GameState.machines[0]
	var sv: Node3D = auto.visuals[int(solar["uid"])]["root"]
	var bounds := Automation.model_bounds(sv)
	var body_box: BoxShape3D = null
	for b in sv.find_children("*", "CollisionShape3D", true, false):
		body_box = (b as CollisionShape3D).shape as BoxShape3D
	check(body_box != null and body_box.size.x >= bounds.size.x - 0.01 and body_box.size.z >= bounds.size.z - 0.01, "machine collision covers the whole model (no driving through panels)", str(bounds.size))
	check(GameState.dirt.sample(M(-36.0, 10.0)) == 0.0, "no dust left hidden under a new machine")
	check(sv.global_basis.y.dot(sv.global_position.normalized()) > 0.999, "machines stand upright on the sphere")
	auto.add_machine("dust_collector", near_base, 0.0)
	auto.add_machine("conveyor", M(22, 4), 0.0)
	var col: Dictionary = GameState.machines[1]
	check(sim.net_of.has(int(col["uid"])) and sim.net_of.has(AutomationSim.BASE_UID) and sim.net_of[int(col["uid"])] == sim.net_of[AutomationSim.BASE_UID], "conveyor links collector to the base exchange")
	var dust0 := GameState.stat("auto_dust")
	var cr0 := GameState.credits
	var dirt0 := GameState.dirt.area_clean_fraction(near_base, 6.0, 0.5)
	for i in 20:
		sim.tick(1.0)
	check(GameState.stat("auto_dust") > dust0, "collector produces dust", str(GameState.stat("auto_dust") - dust0))
	check(GameState.credits > cr0, "linked automation sells automatically", str(GameState.credits - cr0))
	check(GameState.dirt.area_clean_fraction(near_base, 6.0, 0.5) > dirt0, "collector visibly cleans the ground around it")
	# Remote network with storage + depot
	var far := M(80, 80)
	auto.add_machine("dust_collector", far, 0.0)
	auto.add_machine("storage_container", M(86, 80), 0.0)
	for i in 5:
		sim.tick(1.0)
	var st: Dictionary = GameState.machines[GameState.machines.size() - 1]
	check(sim.stored(st) > 0.0, "storage container receives dust")
	auto.add_machine("processor", M(80, 86), 0.0)
	for i in 3:
		sim.tick(1.0)
	check(float(st.get("rd", 0.0)) > 0.0, "processor refines stored dust")
	auto.add_machine("shipping_depot", M(74, 80), 0.0)
	var cr1 := GameState.credits
	for i in 32:
		sim.tick(1.0)
	check(GameState.credits > cr1, "shipping depot sells on its timer")
	# Drones need a charger, then clean
	auto.add_machine("drone_bay", M(-40, 40), 0.0)
	var bay: Dictionary = GameState.machines[GameState.machines.size() - 1]
	sim.tick(1.0)
	check(String(bay["status"]).begins_with("Needs"), "drone bay requires a charging station")
	auto.add_machine("charging_station", M(-46, 40), 0.0)
	auto.add_machine("solar_array", M(-40, 52), 0.0)
	for i in 60:
		sim.tick(1.0)
	check(float(bay["produced"]) > 0.0, "cleaning drone produces dust", str(bay["produced"]))
	# Power shortage reduces efficiency
	check(sim.efficiency > 0.0 and sim.efficiency <= 1.0, "power efficiency computed", str(sim.efficiency))
	# Link preview while placing
	var pv := sim.preview_links("dust_collector", M(35, 10))
	check(pv["base"] and not (pv["links"] as Array).is_empty(), "placement preview shows a link to the base network")
	check((sim.preview_links("dust_collector", M(-200, 200))["links"] as Array).is_empty(), "placement preview warns when nothing is in reach")
	# A processor + storage also pays off in a network linked to the base
	auto.add_machine("storage_container", M(30, 16), 0.0)
	var bst: Dictionary = GameState.machines[GameState.machines.size() - 1]
	auto.add_machine("processor", M(36, 13), 0.0)
	var bpr: Dictionary = GameState.machines[GameState.machines.size() - 1]
	check(sim.net_of.has(int(bpr["uid"])) and sim.net_of[int(bpr["uid"])] == sim.net_of[AutomationSim.BASE_UID], "processor joins the base network")
	var cr2 := GameState.credits
	for i in 30:
		sim.tick(1.0)
	check(float(bpr.get("produced", 0.0)) > 0.0 and String(bpr["status"]) != "No power", "processor refines in a base network", str(bpr.get("status", "")))
	check(GameState.credits > cr2 and sim.stored(bst) < sim.storage_capacity(bst), "base sells refined dust (storage never stalls)")


func _test_save_load() -> void:
	print("[save / load]")
	GameState.credits = 4242.0
	GameState.rp = 77.0
	var cleaned_point := M(70.3, 90.7)
	GameState.dirt.stamp(DirtMap.Shape.ROUND, cleaned_point, 1.0, 0.0, Vector3.ZERO, 5.0, 1e9)
	var machines := GameState.machines.size()
	var tools := GameState.tools.duplicate()
	game.player.global_position = M(12, 30, 1.0)
	SaveManager.save_game(3, false)
	check(SaveManager.has_save(3), "save file written")
	GameState.new_game()
	check(GameState.credits == 0.0 and GameState.dirt.chunks.is_empty(), "state reset")
	check(SaveManager.load_game(3), "save loads")
	check(GameState.credits == 4242.0 and int(GameState.rp) == 77, "credits and research points restored")
	check(GameState.machines.size() == machines, "machines restored")
	check(GameState.tools.has("big_toothbrush") and GameState.tools["big_toothbrush"] == tools["big_toothbrush"], "tools and upgrades restored")
	check(GameState.dirt.sample(cleaned_point) == 0.0, "world cleaning persists")
	check(GameState.dirt.sample(M(75.3, 90.7)) > 0.3, "uncleaned ground still dusty")
	var pp: Array = GameState.player["pos"]
	check(AutomationSim.v3(pp).distance_to(M(12, 30, 1.0)) < 0.5, "player position restored")
	# Corrupt main file -> backup recovery
	SaveManager.save_game(3, false)
	var f := FileAccess.open(SaveManager.slot_dir(3) + "/state.json", FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	GameState.new_game()
	check(SaveManager.load_game(3) and GameState.credits == 4242.0, "corrupted save recovers from backup")
	# Threaded save path
	SaveManager.save_game(3, true)
	await frames(10)
	check(not SaveManager.is_saving(), "threaded save completes")


func _test_diagnostics() -> void:
	print("[crash diagnostics]")
	var D := load("res://scripts/autoload/diagnostics.gd")
	var cases := [["SESSION x\n12:00:01 | foot (1,2,3) | fps 60\n", true, "abrupt end is a crash"],
		["SESSION x\n12:00:01 | foot | fps 60\nEND 12:00:05\n", false, "clean exit is not a crash"],
		["SESSION x\n12:00:01 | foot | fps 60\nPAUSED 12:00:05\n", false, "killed in background is not a crash"]]
	for c in cases:
		if FileAccess.file_exists(D.LAST_CRASH):
			DirAccess.remove_absolute(D.LAST_CRASH)
		var f := FileAccess.open(D.SESSION, FileAccess.WRITE)
		f.store_string(c[0])
		f.close()
		var d: Node = D.new()
		add_child(d)
		check(d.previous_crashed == c[1], c[2])
		if c[1]:
			check(d.report().contains("LAST CRASHED SESSION") and d.report().contains("foot (1,2,3)"), "crash report includes the breadcrumbs")
		d.queue_free()
	await frames(1)
	check(SettingsPanel.copy_crash_log() > 3, "copy crash log puts a report on the clipboard")
	# Freeze watchdog: block the main thread for 4 s and check it was recorded.
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 4200:
		pass
	await frames(2)
	check(FileAccess.get_file_as_string(D.SESSION).contains("FREEZE main thread stalled"), "watchdog records a main-thread freeze")
