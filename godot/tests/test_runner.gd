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
	await _test_menus()
	await _test_vehicle()
	await _test_automation()
	await _test_save_load()
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


func _test_dirt() -> void:
	print("[dirt map]")
	var d := DirtMap.new()
	var x := 70.3
	var z := 90.7
	var before := d.sample(x, z)
	check(before > 0.4, "ground starts dusty", str(before))
	var area1 := d.stamp(DirtMap.Shape.ROUND, x, z, 0.5, 0.0, 0.0, 0.5, 1e9)
	var mid := d.sample(x, z)
	check(area1 > 0.0 and mid < before, "stamping removes dirt where brushed", "%f -> %f" % [before, mid])
	check(d.sample(x + 3.0, z) > 0.4, "dirt elsewhere untouched")
	var area2 := d.stamp(DirtMap.Shape.ROUND, x, z, 0.5, 0.0, 0.0, 5.0, 1e9)
	var area3 := d.stamp(DirtMap.Shape.ROUND, x, z, 0.5, 0.0, 0.0, 5.0, 1e9)
	check(d.sample(x, z) == 0.0, "full strength clears completely")
	check(area3 == 0.0, "already-cleaned ground yields nothing", str(area3))
	var total := area1 + area2
	check(total > 0.5 and total < 0.9, "removed area matches brush footprint (~0.785 m2)", str(total))
	var capped := d.stamp(DirtMap.Shape.ROUND, x + 10.0, z, 1.0, 0.0, 0.0, 5.0, 0.1)
	check(capped <= 0.11, "budget caps removal (tank full logic)", str(capped))
	var rect := d.stamp(DirtMap.Shape.RECT, x - 10.0, z, 2.0, 0.5, 0.3, 5.0, 1e9)
	check(rect > 2.0, "wide brushes clean rectangles", str(rect))
	# Cross-chunk stamp
	var edge := d.stamp(DirtMap.Shape.ROUND, 64.0, 64.0, 1.0, 0.0, 0.0, 5.0, 1e9)
	check(edge > 2.0 and d.sample(63.8, 63.8) == 0.0 and d.sample(64.2, 64.2) == 0.0, "stamps span chunk borders", str(edge))
	# Persistence encode/decode
	var bytes := DirtMap.encode_snapshot(d.snapshot())
	var d2 := DirtMap.new()
	check(d2.decode(bytes), "dirt data decodes")
	check(d2.sample(x, z) == 0.0 and d2.sample(x + 3.0, z) > 0.4, "decoded dirt matches")
	check(not DirtMap.new().decode(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])), "corrupted dirt data is rejected")


func _test_menu() -> void:
	print("[main menu]")
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
	check(p.y > TerrainGen.height(p.x, p.z) - 0.5, "player stands on the ground", str(p))


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
	var moved := Vector2(pl.global_position.x - start.x, pl.global_position.z - start.z).length()
	check(moved > 1.5, "player walks with the joystick", str(moved))
	# Look: swipe on the right half
	_touch(c, 1, Vector2(900, 300), true)
	_drag(c, 1, Vector2(800, 300))
	await frames(2)
	_touch(c, 1, Vector2(800, 300), false)
	check(not is_equal_approx(pl.yaw, yaw0), "swipe rotates the camera")
	# Clean button
	var cb := c.button_center("clean")
	_touch(c, 2, cb, true)
	await frames(1)
	check(pl.cleaner.cleaning, "CLEAN button starts cleaning")
	_touch(c, 2, cb, false)
	await frames(1)
	check(not pl.cleaner.cleaning, "releasing CLEAN stops cleaning")


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
	pl.global_position = Vector3(60, TerrainGen.height(60, 20) + 0.5, 20)
	pl.pitch = -0.9
	game.terrain.prewarm(pl.global_position)
	await frames(20)
	GameState.tank_dust = 0.0
	GameState.tank_value = 0.0
	var aim: Vector3 = pl.cleaner.aim_point
	var before := GameState.dirt.sample(aim.x, aim.z)
	pl.cleaner.cleaning = true
	await frames(45)
	pl.cleaner.cleaning = false
	await frames(1)
	var after := GameState.dirt.sample(aim.x, aim.z)
	check(GameState.tank_dust > 0.0, "dust enters the container", str(GameState.tank_dust))
	check(after < before, "toothbrush removes dirt at the aim point", "%f -> %f" % [before, after])
	check(GameState.stat("m2_cleaned") > 0.0, "cleaned area is recorded")
	# Full tank stops collection
	GameState.tank_dust = GameState.tank_capacity()
	pl.yaw += 1.2
	await frames(5)
	var aim2: Vector3 = pl.cleaner.aim_point
	var b2 := GameState.dirt.sample(aim2.x, aim2.z)
	pl.cleaner.cleaning = true
	await frames(30)
	pl.cleaner.cleaning = false
	check(is_equal_approx(GameState.tank_dust, GameState.tank_capacity()), "container stops collecting when full")
	check(is_equal_approx(GameState.dirt.sample(aim2.x, aim2.z), b2), "dirt is not wasted when the tank is full")
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
	var a0 := d.stamp(DirtMap.Shape.ROUND, 200, 200, s0["radius"], 0, 0, s0["strength"] * 0.05, 1e9)
	var a1 := d.stamp(DirtMap.Shape.ROUND, 210, 200, s1["radius"], 0, 0, s1["strength"] * 0.05, 1e9)
	check(a1 > a0, "upgraded tool cleans more per second", "%f vs %f" % [a0, a1])
	var cap0 := GameState.tank_capacity()
	check(GameState.buy_tank_upgrade() and GameState.tank_capacity() > cap0, "storage upgrade increases capacity")
	check(GameState.buy_permit(1) == GameState.permit_requirement_met(1), "permit purchase respects requirements")
	GameState.missions_done.append("m_sell_1")
	GameState.regions[1] = false
	check(GameState.buy_permit(1) and GameState.region_unlocked(1), "permit unlocks region")


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
	var yaw0 := v.global_rotation.y
	game.controls.move_vector = Vector2(-0.8, -0.6)
	await frames(90)
	game.controls.move_vector = Vector2.ZERO
	check(absf(wrapf(v.global_rotation.y - yaw0, -PI, PI)) > 0.05, "vehicle steers")
	# Vacuum deck uses the shared dirt map
	var h0 := v.hopper()
	v.cleaning = true
	game.controls.move_vector = Vector2(0, -0.6)
	await frames(90)
	v.cleaning = false
	game.controls.move_vector = Vector2.ZERO
	check(v.hopper() > h0, "vacuum buggy collects dust into its hopper", str(v.hopper()))
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
	var near_base := Vector3(30, 0, 10)
	near_base.y = TerrainGen.height(near_base.x, near_base.z)
	check(sim.can_place("dust_collector", Vector3(0, 0, 0)) != "", "can't build inside the base")
	auto.add_machine("solar_array", Vector3(-36, TerrainGen.height(-36, 10), 10), 0.0)
	auto.add_machine("dust_collector", near_base, 0.0)
	auto.add_machine("conveyor", Vector3(22, TerrainGen.height(22, 4), 4), 0.0)
	var col: Dictionary = GameState.machines[1]
	check(sim.net_of.has(int(col["uid"])) and sim.net_of.has(AutomationSim.BASE_UID) and sim.net_of[int(col["uid"])] == sim.net_of[AutomationSim.BASE_UID], "conveyor links collector to the base exchange")
	var dust0 := GameState.stat("auto_dust")
	var cr0 := GameState.credits
	var dirt0 := GameState.dirt.area_clean_fraction(near_base.x, near_base.z, 6.0, 0.5)
	for i in 20:
		sim.tick(1.0)
	check(GameState.stat("auto_dust") > dust0, "collector produces dust", str(GameState.stat("auto_dust") - dust0))
	check(GameState.credits > cr0, "linked automation sells automatically", str(GameState.credits - cr0))
	check(GameState.dirt.area_clean_fraction(near_base.x, near_base.z, 6.0, 0.5) > dirt0, "collector visibly cleans the ground around it")
	# Remote network with storage + depot
	var far := Vector3(80, 0, 80)
	far.y = TerrainGen.height(far.x, far.z)
	auto.add_machine("dust_collector", far, 0.0)
	auto.add_machine("storage_container", far + Vector3(6, 0, 0), 0.0)
	for i in 5:
		sim.tick(1.0)
	var st: Dictionary = GameState.machines[GameState.machines.size() - 1]
	check(sim.stored(st) > 0.0, "storage container receives dust")
	auto.add_machine("processor", far + Vector3(0, 0, 6), 0.0)
	for i in 3:
		sim.tick(1.0)
	check(float(st.get("rd", 0.0)) > 0.0, "processor refines stored dust")
	auto.add_machine("shipping_depot", far + Vector3(-6, 0, 0), 0.0)
	var cr1 := GameState.credits
	for i in 32:
		sim.tick(1.0)
	check(GameState.credits > cr1, "shipping depot sells on its timer")
	# Drones need a charger, then clean
	auto.add_machine("drone_bay", Vector3(-40, TerrainGen.height(-40, 40), 40), 0.0)
	var bay: Dictionary = GameState.machines[GameState.machines.size() - 1]
	sim.tick(1.0)
	check(String(bay["status"]).begins_with("Needs"), "drone bay requires a charging station")
	auto.add_machine("charging_station", Vector3(-46, TerrainGen.height(-46, 40), 40), 0.0)
	auto.add_machine("solar_array", Vector3(-40, TerrainGen.height(-40, 52), 52), 0.0)
	for i in 60:
		sim.tick(1.0)
	check(float(bay["produced"]) > 0.0, "cleaning drone produces dust", str(bay["produced"]))
	# Power shortage reduces efficiency
	check(sim.efficiency > 0.0 and sim.efficiency <= 1.0, "power efficiency computed", str(sim.efficiency))


func _test_save_load() -> void:
	print("[save / load]")
	GameState.credits = 4242.0
	GameState.rp = 77.0
	var cleaned_point := Vector3(70.3, 0, 90.7)
	GameState.dirt.stamp(DirtMap.Shape.ROUND, cleaned_point.x, cleaned_point.z, 1.0, 0.0, 0.0, 5.0, 1e9)
	var machines := GameState.machines.size()
	var tools := GameState.tools.duplicate()
	game.player.global_position = Vector3(12, TerrainGen.height(12, 30) + 1.0, 30)
	SaveManager.save_game(3, false)
	check(SaveManager.has_save(3), "save file written")
	GameState.new_game()
	check(GameState.credits == 0.0 and GameState.dirt.chunks.is_empty(), "state reset")
	check(SaveManager.load_game(3), "save loads")
	check(GameState.credits == 4242.0 and int(GameState.rp) == 77, "credits and research points restored")
	check(GameState.machines.size() == machines, "machines restored")
	check(GameState.tools.has("big_toothbrush") and GameState.tools["big_toothbrush"] == tools["big_toothbrush"], "tools and upgrades restored")
	check(GameState.dirt.sample(cleaned_point.x, cleaned_point.z) == 0.0, "world cleaning persists")
	check(GameState.dirt.sample(cleaned_point.x + 5.0, cleaned_point.z) > 0.3, "uncleaned ground still dusty")
	var pp: Array = GameState.player["pos"]
	check(absf(float(pp[0]) - 12.0) < 0.5, "player position restored")
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
