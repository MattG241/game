extends Node
## Automated gameplay & logic tests. Run:
##   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
## Exits with code 0 when every check passes.

var passed := 0
var failed := 0
var main: Node
var log_lines: PackedStringArray = []


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		_log("  PASS  " + what)
	else:
		failed += 1
		_log("  FAIL  " + what)


func _log(s: String) -> void:
	print(s)
	log_lines.append(s)


func _ready() -> void:
	await get_tree().process_frame
	_log("== Unit: stout pour model ==")
	_test_pour_model()
	_log("== Unit: economy & inventory ==")
	_test_economy()
	_log("== Unit: save / load / backup ==")
	_test_save()
	_log("== Integration: the first playable loop ==")
	await _test_loop()
	_log("")
	_log("RESULT: %d passed, %d failed" % [passed, failed])
	var f := FileAccess.open("user://test_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))
	get_tree().quit(0 if failed == 0 else 1)


# ------------------------------------------------------------------ unit tests
func _pour(c: GlassContents, seconds: float, flow: float, tilt: float) -> void:
	var dt := 1.0 / 60.0
	var n := int(seconds / dt)
	for i in n:
		c.pour(dt, flow, tilt, "stout", "stout")
	c.stop_pour()


func _pour_until(c: GlassContents, target: float, flow: float, tilt_fn: Callable) -> void:
	var dt := 1.0 / 60.0
	for i in 6000:
		if c.total() >= target:
			break
		c.pour(dt, flow, tilt_fn.call(c), "stout", "stout")
	c.stop_pour()


func _settle(c: GlassContents, seconds: float) -> void:
	for i in int(seconds * 60):
		c.settle(1.0 / 60.0, 12.0)


func _test_pour_model() -> void:
	# a textbook two-part pour
	var c := GlassContents.new()
	_pour_until(c, 0.74, 1.0, func(cc): return 45.0 if cc.total() < 0.45 else lerpf(45.0, 8.0, (cc.total() - 0.45) / 0.3))
	check(c.stage == 2, "first pour stops into the settling stage")
	check(c.first_pour_level > 0.7 and c.first_pour_level < 0.8, "first pour level ~3/4 (%.2f)" % c.first_pour_level)
	check(c.cascade > 0.5, "freshly poured stout is a creamy cascade")
	_settle(c, 15.0)
	check(c.settled_fraction() > 0.98, "cascade settles into dark body (%.3f)" % c.settled_fraction())
	check(c.foam > 0.03 and c.foam < 0.12, "settling forms a head (%.3f)" % c.foam)
	_pour_until(c, 1.015, 0.35, func(_cc): return 0.0)
	_settle(c, 15.0)
	var r := c.evaluate(0.0)
	check(r["score"] >= 88, "perfect technique scores highly (%d, %s, head %.3f, fill %.3f)" % [r["score"], r["verdict"], r["head"], r["fill"]])
	check(r["verdict"] in ["Perfect Head", "Beautiful Pint"], "verdict for a great pint: %s" % r["verdict"])

	# one-shot upright pour straight to the top
	var b := GlassContents.new()
	_pour_until(b, 1.0, 1.0, func(_cc): return 0.0)
	_settle(b, 15.0)
	var rb := b.evaluate(0.0)
	check(rb["score"] < r["score"] - 20, "rushed upright one-shot pour scores much worse (%d)" % rb["score"])
	check(rb["head"] > 0.2, "upright pour makes too much foam (%.2f)" % rb["head"])
	check(rb["verdict"] == "Too Much Foam", "verdict says Too Much Foam (%s)" % rb["verdict"])

	# underfilled
	var u := GlassContents.new()
	_pour_until(u, 0.6, 1.0, func(_cc): return 45.0)
	_settle(u, 15.0)
	_pour_until(u, 0.8, 0.3, func(_cc): return 0.0)
	_settle(u, 15.0)
	var ru := u.evaluate(0.0)
	check(ru["verdict"] == "Underfilled", "underfilled pint is called out (%s)" % ru["verdict"])

	# overfill: keep pouring well past the top
	var o := GlassContents.new()
	_pour_until(o, 0.74, 1.0, func(_cc): return 30.0)
	_settle(o, 15.0)
	_pour(o, 8.0, 1.0, 0.0)
	check(o.spilled > 0.05, "overfilling spills over the rim (%.3f)" % o.spilled)
	check(o.total() <= 1.0 + GlassContents.DOME + 0.001, "glass never holds more than brim + dome")

	# tilt spill: 45 degrees cannot hold more than ~72%
	var t := GlassContents.new()
	_pour(t, 14.0, 1.0, 45.0)
	check(t.spilled > 0.0, "a tilted glass spills when overfilled")
	check(absf(GlassContents.rim_limit(45.0) - 0.72) < 0.01, "rim limit at 45° is 72%")

	# tilt response: upright makes more head than 45 degrees
	var a1 := GlassContents.new()
	_pour(a1, 4.0, 1.0, 45.0)
	var a2 := GlassContents.new()
	_pour(a2, 4.0, 1.0, 0.0)
	check(a2.cascade_head_ratio > a1.cascade_head_ratio * 2.0, "pour angle changes head formation (%.2f vs %.2f)" % [a1.cascade_head_ratio, a2.cascade_head_ratio])
	# flow rate
	var f1 := GlassContents.new()
	_pour(f1, 2.0, 1.0, 45.0)
	var f2 := GlassContents.new()
	_pour(f2, 2.0, 0.4, 45.0)
	check(f1.total() > f2.total() * 2.0, "tap handle position controls flow rate")
	# no flow, no pour
	var z := GlassContents.new()
	z.pour(1.0, 0.0, 45.0, "stout", "stout")
	check(z.total() == 0.0, "tap does not pour without pulling the handle")
	# topping up before settling is penalised
	var h := GlassContents.new()
	_pour_until(h, 0.74, 1.0, func(cc): return 45.0 if cc.total() < 0.45 else 20.0)
	_settle(h, 1.0)
	_pour_until(h, 1.015, 0.35, func(_cc): return 0.0)
	_settle(h, 15.0)
	var rh := h.evaluate(0.0)
	check(h.hurried and rh["score"] < r["score"] - 10, "topping up before it settles costs quality (%d)" % rh["score"])
	# dirty glass penalty
	var rd := c.evaluate(0.8)
	check(rd["score"] < r["score"] - 20 and rd["verdict"] == "Dirty Glass", "dirty glass is penalised")


func _test_economy() -> void:
	GameState.new_game("career", "Test Pub")
	var start := GameState.cash
	check(not GameState.spend(start + 1.0, "other"), "cannot spend more cash than you have")
	check(is_equal_approx(GameState.cash, start), "failed spend leaves cash untouched")
	var units := GameState.serves_left("stout")
	check(GameState.draw_units("stout", 1.0), "drawing a pint from the keg works")
	check(is_equal_approx(GameState.serves_left("stout"), units - 1.0), "keg volume decreases by what was poured")
	check(not GameState.draw_units("stout", 1000.0), "cannot draw more than the keg holds")
	check(is_equal_approx(GameState.serves_left("stout"), units - 1.0), "failed draw takes nothing")
	var spare := int(GameState.stock["stout"])
	check(GameState.change_keg("stout"), "changing a keg uses a spare")
	check(int(GameState.stock["stout"]) == spare - 1, "spare keg count decreases")
	check(not GameState.change_keg("stout"), "cannot change a keg with no spares")
	GameState.cash = 200.0
	var before := GameState.cash
	check(GameState.order_stock("stout", 1), "ordering stock works when affordable")
	var fee := float(GameData.econ("delivery_fee", 6))
	check(is_equal_approx(GameState.cash, before - 112.0 - fee), "stock order charges cost + delivery")
	check(GameState.pending_delivery("stout") == 1, "delivery is pending")
	GameState.cash = 100.0
	check(GameState.buy_upgrade("lamps"), "can buy an affordable upgrade")
	check(is_equal_approx(GameState.cash, 60.0), "upgrade cost deducted (€40)")
	check(not GameState.buy_upgrade("lamps"), "cannot buy the same upgrade twice")
	check(GameState.atmosphere() > 20.0, "upgrade effects apply (atmosphere %.0f)" % GameState.atmosphere())
	check(not GameState.buy_upgrade("glasses_12"), "upgrade prerequisites enforced")
	GameState.set_price("stout", 99.0)
	check(GameState.price_of("stout") <= 5.2 * 2.0 + 0.001, "prices are clamped to a sane range")
	GameState.set_price("stout", 5.2)
	# end of day
	GameState.cash = 100.0
	GameState.today["sales"] = 50.0
	GameState.today["tips"] = 5.0
	var s := GameState.end_day()
	var rent := float(GameData.econ("rent_per_day", 30))
	var util := float(GameData.econ("utilities_per_day", 8))
	check(is_equal_approx(GameState.cash, 100.0 - rent - util), "rent & utilities are paid at close")
	check(is_equal_approx(float(s["income"]), 55.0), "summary income = sales + tips")
	check(GameState.day == 2, "a new day begins after closing")
	check(int(GameState.stock["stout"]) == 1, "yesterday's delivery arrived")


func _test_save() -> void:
	GameState.new_game("career", "Save Test")
	GameState.cash = 123.45
	GameState.upgrades["fireplace"] = 1
	GameState.relationships["nora"] = 7
	check(GameState.save_game(), "save writes successfully")
	GameState.cash = 1.0
	GameState.save_game()  # creates a backup of the 123.45 save
	GameState.cash = 999.0
	check(GameState.load_game(), "load succeeds")
	check(is_equal_approx(GameState.cash, 1.0), "loaded cash matches the latest save")
	check(GameState.has_upgrade("fireplace"), "upgrades persist")
	check(int(GameState.relationships.get("nora", 0)) == 7, "relationships persist")
	# corrupt the main save: the backup must be recovered
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	check(GameState.load_game(), "corrupted save falls back to the backup")
	check(is_equal_approx(GameState.cash, 123.45), "backup restored the previous good state")


# ------------------------------------------------------------------ integration
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, max_seconds: float) -> bool:
	var frames := int(max_seconds * 60)
	for i in frames:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _test_loop() -> void:
	GameState.delete_save()
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await _frames(5)
	check(main.title != null, "main menu loads")
	main.start_new("career", "The Crooked Shamrock")
	await _frames(10)
	var w: World = main.world
	check(w != null and w.player != null, "new game loads the pub with a player")
	check(main.hud != null, "touch HUD is present")
	var total := GameState.glasses_total()
	check(w.glass_count_check() == total, "glass accounting starts correct (%d)" % total)
	# movement via the virtual joystick
	var p0 := w.player.global_position
	main.hud.touch.move = Vector2(0, -1)
	await _frames(40)
	main.hud.touch.move = Vector2.ZERO
	await _frames(5)
	check(w.player.global_position.distance_to(p0) > 0.5, "joystick input moves the player")
	var yaw0 := w.player.rotation.y
	w.player.look(Vector2(120, 0))
	check(absf(w.player.rotation.y - yaw0) > 0.1, "swipe input turns the camera")
	w.player.global_position = PubLayout.PLAYER_START
	# simulated touches through the real input router
	var tc: TouchControls = main.hud.touch
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	ev.position = Vector2(150, 550)
	tc._input(ev)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(150, 470)
	drag.relative = Vector2(0, -80)
	tc._input(drag)
	check(tc.move.y < -0.5, "touch drag on the left half drives the joystick")
	ev.pressed = false
	tc._input(ev)
	check(tc.move == Vector2.ZERO, "releasing the joystick stops movement")
	# open the pub at the door sign
	check(w._sign_prompt().begins_with("Open"), "door sign offers to open the pub")
	w._sign_action()
	check(GameState.phase == "open", "pub opens")
	var ok := await _wait_until(func(): return w.customers.size() > 0, 6.0)
	check(ok, "a customer arrives after opening")
	var c: Customer = w.customers[0] if ok else null
	ok = await _wait_until(func(): return c != null and c.state == "wait_order", 40.0)
	check(ok, "customer walks in and waits at the bar (state %s)" % (c.state if c else "none"))
	if not ok:
		return
	check(w._customer_prompt(c).begins_with("Take"), "prompt to take the order")
	w._customer_action(c)
	check(c.state == "wait_drink" and c.order_taken, "order taken")
	var drink := c.drink_id
	_log("    customer %s ordered %s" % [c.display_name, drink])
	# the first customer always wants what we can pour on day one
	check(drink == "stout", "first order is a stout")
	# glass
	check(w._tap_prompt("stout").begins_with("~"), "tap refuses without a glass")
	var rack_before := w.rack_clean
	w._rack_action()
	check(w.player.held != null and w.player.held.is_clean(), "picked up a clean glass")
	check(w.rack_clean == rack_before - 1, "rack has one fewer glass")
	check(w.glass_count_check() == total, "glass count conserved after pickup")
	# pour mode
	var keg_before := GameState.serves_left("stout")
	w._tap_action("stout")
	await _frames(2)
	var pc: PourController = w.pour
	check(pc.active, "pour mode starts at the stout tap")
	check(main.hud.pour_root.visible, "pour controls are shown")
	check(w.close_cam.current, "close-up pour camera active")
	pc.lever = 0.0
	pc.tilt_input = 0.5
	await _frames(30)
	check(w.player.held.contents.total() == 0.0, "nothing pours until the handle is pulled")
	check(absf(pc.tilt - 45.0) < 2.0, "tilt control angles the glass to 45° (%.1f)" % pc.tilt)
	var up := (w.player.held.global_transform.basis.y).normalized()
	check(up.angle_to(Vector3.UP) > deg_to_rad(40), "the glass model visibly tilts")
	pc.lever = 1.0
	ok = await _wait_until(func():
		var t := w.player.held.contents.total()
		pc.tilt_input = (45.0 if t < 0.45 else lerpf(45.0, 8.0, (t - 0.45) / 0.3)) / 90.0
		return t >= 0.74, 30.0)
	pc.lever = 0.0
	await _frames(3)
	var g: PintGlass = w.player.held
	check(ok and g.contents.stage == 2, "first pour reaches ~3/4 and stops (%.2f)" % g.contents.first_pour_level)
	check(g.contents.cascade > 0.3, "cascade visible after first pour (%.3f body %.3f foam %.3f)" % [g.contents.cascade, g.contents.body, g.contents.foam])
	var mat: ShaderMaterial = g._liq_mat
	check(float(mat.get_shader_parameter("level_body")) > 0.6, "liquid shader level follows the pour")
	check(GameState.serves_left("stout") < keg_before - 0.6, "keg volume decreased while pouring")
	# leave it to settle and do something else
	pc.end(true)
	await _frames(25)
	check(not pc.active and w.player.held == null, "glass left on the drip tray to settle")
	check(w.settle_slots[0] == g, "pint sits in a settling slot")
	check(w.glass_count_check() == total, "glass count conserved while settling")
	await _wait_until(func(): return g.contents.settled_fraction() > 0.99, 20.0)
	check(g.contents.settled_fraction() > 0.99, "stout settles on the shelf")
	# pick it up and top up
	w._settle_action(0)
	check(w.player.held == g, "picked the settled pint back up")
	check(w._tap_prompt("stout").begins_with("Top up"), "tap offers to top up")
	w._tap_action("stout")
	await _frames(20)
	pc.tilt_input = 0.0
	await _frames(30)
	pc.lever = 0.35
	await _wait_until(func(): return g.contents.total() >= 1.015, 20.0)
	pc.lever = 0.0
	await _frames(5)
	pc.end(false)
	await _frames(30)
	check(w.player.held == g and g.contents.stage == 3, "topped up and back in hand")
	await _wait_until(func(): return g.contents.settled_fraction() > 0.99, 20.0)
	# serve
	var cash0 := GameState.cash
	check(w._customer_prompt(c).begins_with("Serve"), "prompt to serve the customer")
	var res: Dictionary = w.serve_customer(c, g)
	check(res.get("ok", false), "customer accepts the pint")
	_log("    pour result: %s, quality %d, price €%.2f, tip €%.2f, satisfaction %d" % [res.get("verdict"), res.get("score"), res.get("price", 0), res.get("tip", 0), res.get("satisfaction", 0)])
	check(int(res.get("score", 0)) >= 80, "well-poured pint scores >= 80")
	check(GameState.cash > cash0 + 5.0, "payment received (€%.2f)" % (GameState.cash - cash0))
	check(float(res.get("tip", 0)) > 0.0, "a good pint earns a tip")
	check(int(GameState.today["served"]) == 1, "served count recorded")
	check(w.glass_count_check() == total, "glass count conserved after serving")
	# buy the first upgrade
	check(GameState.can_buy_upgrade("lamps"), "first upgrade affordable after one pint (cash €%.2f)" % GameState.cash)
	var lamp: OmniLight3D = w.info["lamps"][0]
	var e0 := lamp.light_energy
	var restored: Array = w.info["upgrade_show"]["lamps"]
	check(not restored[0].visible, "restored lamps not visible before buying")
	GameState.buy_upgrade("lamps")
	await _frames(3)
	check(restored[0].visible, "restored lamps appear after buying")
	check(lamp.light_energy > e0 * 1.5, "the pub is visibly brighter (%.2f -> %.2f)" % [e0, lamp.light_energy])
	# customer drinks and leaves a dirty glass
	ok = await _wait_until(func(): return c.state == "drinking" or c.state == "stand_drink", 30.0)
	check(ok, "customer takes the pint to a seat (%s)" % c.state)
	c.drink_left = 0.01
	ok = await _wait_until(func(): return w.loose_glasses.size() > 0, 10.0)
	check(ok, "empty glass left behind after drinking")
	check(w.glass_count_check() == total, "glass count conserved with a dirty glass out")
	if ok:
		var dg: PintGlass = w.loose_glasses[0]
		w._collect_glass(dg)
		check(w.player.dirty_stack.size() == 1, "collected the dirty glass")
		var rack2 := w.rack_clean
		w._sink_action()
		check(w.rack_clean == rack2 + 1 and w.player.dirty_stack.is_empty(), "washed glass returns clean to the rack")
		check(w.glass_count_check() == total, "glass count conserved after washing")
	# spills can be wiped
	w.add_spill(Vector3(-1.6, PubLayout.BAR_TOP, -2.0), 0.08)
	var sp_count := w.spills.size()
	if sp_count > 0:
		w._wipe(w.spills[0])
		check(w.spills.size() == sp_count - 1, "spills can be wiped clean")
	# close the day
	GameState.hour = 23.6
	await _frames(3)
	check(GameState.phase == "last_orders", "last orders called at 23:30")
	GameState.hour = 24.8
	await _frames(3)
	for cc in w.customers.duplicate():
		cc.leave()
	ok = await _wait_until(func(): return w.customers.is_empty(), 60.0)
	check(ok, "all customers leave at closing")
	var cash_close := GameState.cash
	var day0 := GameState.day
	w._sign_action()
	await _frames(3)
	check(GameState.day == day0 + 1, "closing up advances to the next day")
	check(GameState.cash < cash_close, "overheads paid at close")
	check(main.hud.menu.visible and main.hud.menu._summary_mode, "end of day summary shown")
	check(FileAccess.file_exists(GameState.SAVE_PATH), "game saved at the end of the day")
	var saved_cash := GameState.cash
	# quit and reload
	main.quit_to_title()
	await _frames(5)
	GameState._reset()
	check(GameState.load_game(), "save loads after quitting")
	check(GameState.day == day0 + 1 and GameState.has_upgrade("lamps") and is_equal_approx(GameState.cash, saved_cash), "progress intact after reload (day %d, €%.2f)" % [GameState.day, GameState.cash])
	main.continue_game()
	await _frames(10)
	check(main.world != null and GameState.has_upgrade("lamps"), "continuing restores the pub")
	check(main.world.info["upgrade_show"]["lamps"][0].visible, "purchased upgrade still visible after reload")
	await _test_minigames(main.world)


func _test_minigames(w: World) -> void:
	_log("== Integration: darts ==")
	check(DartsGame.score_at(Vector2.ZERO)[0] == 50, "bullseye scores 50")
	check(DartsGame.score_at(Vector2(0, 0.012))[0] == 25, "outer bull scores 25")
	check(DartsGame.score_at(Vector2(0, 0.103))[0] == 60, "treble 20 scores 60")
	check(DartsGame.score_at(Vector2(0, 0.166))[0] == 40, "double 20 scores 40")
	check(DartsGame.score_at(Vector2(0, 0.05))[0] == 20, "single 20 scores 20")
	var a := TAU / 20.0 * 5.0  # fifth segment clockwise from the top is 6
	check(DartsGame.score_at(Vector2(sin(a), cos(a)) * 0.05)[0] == 6, "segment layout follows the standard board (6 at 3 o'clock)")
	check(DartsGame.score_at(Vector2(0, -0.103))[0] == 9, "treble 3 at the bottom scores 9")
	check(DartsGame.score_at(Vector2(0.2, 0.1))[0] == 0, "outside the board scores 0")
	check(w._darts_prompt() == "", "darts need the dartboard upgrade")
	GameState.upgrades["dartboard"] = 1
	GameState.upgrades_changed.emit()
	w.player.global_position = Vector3(PubLayout.OCHE_X - 0.6, 0, PubLayout.DARTBOARD.z)
	w.player.rotation.y = -PI / 2.0
	await _frames(3)
	check(w._darts_prompt().begins_with("Play darts"), "dartboard offers a game once bought")
	w.start_darts()
	await _frames(40)
	var dg := w.darts
	check(dg.active and main.hud.darts_root.visible, "darts mode starts with its own controls")
	# aim at treble 20 and throw three darts through the real drag/release path
	for i in 3:
		dg.aim = Vector2(0, 0.103)
		dg.aiming = true
		dg._sway_t = 0.0
		dg.release_throw()
		await _wait_until(func(): return not dg._busy, 3.0)
		await _frames(45)
	check(dg.scores[0] < 301, "player's throws score (%d left)" % dg.scores[0])
	var ok := await _wait_until(func(): return dg.turn == 0 and dg.darts_left == 3 and not dg._busy, 20.0)
	check(ok and dg.scores[1] < 301, "opponent takes a turn and scores (%d left)" % dg.scores[1])
	# a deliberate bust: needing 10, hitting 20 resets the turn
	dg.scores[0] = 10
	dg.turn_start = 10
	dg.darts_left = 3
	dg.aim = Vector2(0, 0.05)
	dg.aiming = true
	dg._sway_t = 0.0
	dg.release_throw()
	await _wait_until(func(): return dg.turn == 1 or dg.scores[0] != 10, 3.0)
	check(dg.scores[0] == 10, "going below zero is a bust")
	await _wait_until(func(): return dg.turn == 0 and not dg._busy, 20.0)
	# finish: needing exactly 20
	dg.scores[0] = 20
	dg.turn_start = 20
	dg.aim = Vector2(0, 0.05)
	dg.aiming = true
	dg._sway_t = 0.0
	dg.release_throw()
	await _wait_until(func(): return dg.winner >= 0, 3.0)
	check(dg.winner == 0 and int(GameState.stats["darts_wins"]) >= 1, "checking out exactly wins the game")
	dg.end()
	await _frames(40)
	check(not dg.active and w.player.input_enabled, "leaving darts returns control")

	_log("== Integration: Split the Knot ==")
	w.player.global_position = Vector3(0.9, 0, -0.9)
	w.player.rotation.y = 0.0
	await _frames(3)
	w.start_split()
	await _frames(45)
	var ds := w.drink_scene
	check(ds.active and main.hud.drink_root.visible, "Split the Knot starts")
	var body0 := ds.glass.contents.body
	await _frames(30)
	check(is_equal_approx(ds.glass.contents.body, body0), "nothing is drunk until you hold")
	ds.press()
	await _frames(int(2.6 * 60))
	ds.release()
	var after_short := ds.glass.contents.body
	check(after_short < body0 - 0.05, "holding drinks continuously (%.3f -> %.3f)" % [body0, after_short])
	await _wait_until(func(): return ds.state == "replay", 5.0)
	var err := ds.error_mm()
	var res: Dictionary = ds._result
	check(ds.state == "replay" and res.has("score"), "result shown after the gulp")
	check(is_equal_approx(float(res["error_mm"]), err), "score measures the liquid line against the knot (%.1f mm)" % err)
	check(GameState.best_split_mm >= 0.0, "best score recorded")
	# a longer gulp drinks more: skill, not chance
	ds.retry()
	await _frames(40)
	ds.press()
	await _frames(int(3.4 * 60))
	ds.release()
	check(ds.glass.contents.body < after_short, "a longer hold goes further down the glass")
	await _wait_until(func(): return ds.state == "replay", 5.0)
	# a perfect stop scores 100
	ds.glass.contents.body = (DrinkScene.TARGET_Y - PintGlass.BASE) / ds.glass.inner_height
	ds._score()
	check(int(ds._result["score"]) == 100 and str(ds._result["verdict"]) == "Split the Knot!", "stopping exactly on the line splits the knot")
	ds.end()
	await _frames(40)
	check(not ds.active and w.player.input_enabled, "leaving the challenge returns control")
	_log("== Integration: a pint by the fire ==")
	w.start_relax()
	await _frames(45)
	check(ds.active and ds.mode == "relax", "fireside pint starts")
	check(ds.drink_id == "zero" or w.pub_closed_for_you(), "alcohol-free while the pub is open")
	var b0 := ds.glass.contents.body
	ds.press()
	await _frames(90)
	ds.release()
	check(ds.glass.contents.body < b0, "sipping lowers the pint")
	ds.end()
	await _frames(40)
	check(w.player.input_enabled, "back on your feet after the pint")
