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
	if OS.get_environment("ONLY") in ["staff", "flow"]:
		# quick run of one section while working on it
		GameState.delete_save()
		main = load("res://scripts/main.gd").new()
		add_child(main)
		await _frames(5)
		if OS.get_environment("ONLY") == "flow":
			await _test_flow()
		else:
			await _test_staff()
		_log("RESULT: %d passed, %d failed" % [passed, failed])
		get_tree().quit(0 if failed == 0 else 1)
		return
	_log("== Unit: stout pour model ==")
	_test_pour_model()
	_log("== Unit: economy & inventory ==")
	_test_economy()
	_log("== Unit: save / load / backup ==")
	_test_save()
	_log("== Unit: soundtrack data and selection ==")
	_test_music_data()
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


## Waits on the wall clock (audio playback runs in real time even when frames are fixed-step).
func _wait_real(cond: Callable, max_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(max_seconds * 1000)
	while Time.get_ticks_msec() < deadline:
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
	ok = await _wait_until(func(): return w.customers.any(func(x): return x.state == "wait_order"), 40.0)
	var c: Customer = null
	for x in w.customers:
		if x.state == "wait_order":
			c = x
	check(ok and c != null, "a customer walks in and comes up to the bar to order")
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
	await _test_music(main.world)
	await _test_voices_and_people(main.world)
	await _test_queue_balance()
	await _test_staff()
	await _test_flow()


func _test_voices_and_people(w: World) -> void:
	_log("== Integration: voices, recorded effects and characters ==")
	var vd := w.voices
	var n := vd.recorded_count()
	check(n >= 1, "recorded voice lines are bundled and indexed (%d found)" % n)
	check(not vd.has_line("old_regular", "order_stout", "lager") or vd.has_line("old_regular", "order_stout", "stout"), "order lines are matched to the drink ordered")
	check(ResourceLoader.exists("res://assets/sfx_el/tap_lever.ogg") and Sfx.get_stream("tap_clunk").resource_path.contains("sfx_el"), "recorded tap effect replaces the synthesised one")
	var crowd_s: AudioStream = Sfx.get_stream("crowd_loop")
	check(crowd_s is AudioStreamOggVorbis and (crowd_s as AudioStreamOggVorbis).loop, "recorded pub ambience loops")
	# a regular orders with their own voice; the mouth moves while they talk
	for c in w.customers.duplicate():
		c.queue_free()
	w.customers.clear()
	await _frames(2)
	var c := w.spawn_customer("packie")
	check(c.voice == "old_regular" and c.gender == "m", "regulars have their own voice and look (%s, %s)" % [c.voice, c.gender])
	var reg_f := w.spawn_customer("nora")
	check(reg_f.gender == "f" and reg_f.voice in VoiceDirector.FEMALE_VOICES, "voices match the character (Nora: %s)" % reg_f.voice)
	c.global_position = w.player.global_position + Vector3(0, 0, 1.5)
	c.drink_id = "stout"
	c.state = "wait_order"
	vd._gap = 0.0
	var before := vd.played.size()
	var music_duck_before := MusicDirector._speech_left
	c.take_order()
	if vd.has_line("old_regular", "order_stout", "stout"):
		check(vd.played.size() == before + 1, "ordering plays the character's recorded line")
		check(c._talk_left > 0.0 and MusicDirector._speech_left > music_duck_before, "they move their mouth and the music dips while speaking")
		await _frames(20)
		check(c._mouth_open > 0.05, "the mouth opens and closes")
		check(c._bubble.text == vd.last_text and vd.played.back().begins_with("old_regular_order_stout"), "the bubble shows the words spoken (%s)" % c._bubble.text)
	# no pile-ups: a second line straight away is held back, unless it matters
	var p2 := vd.played.size()
	vd.speak(reg_f, "old_regular", "order_stout")
	check(vd.played.size() == p2, "a second voice right after is held back (no pile-ups)")
	# characters bend at the knee when they sit
	c._set_seated(true)
	await _frames(3)
	check(c._knees[0].rotation.x < -1.2, "seated characters bend their knees (%.2f)" % c._knees[0].rotation.x)
	var lap: Vector3 = c._knees[0].global_position - c._legs[0].global_position
	var fwd: Vector3 = -c.global_transform.basis.z
	check(lap.dot(fwd) > 0.3, "seated thighs point forward, not back (%.2f)" % lap.dot(fwd))
	c._set_seated(false)
	c._arm_rot[0].x = -1.6
	await _frames(15)
	check(c._elbows[0].rotation.x > 0.8, "a raised arm bends at the elbow")
	var reach: Vector3 = c._elbows[0].global_position - c._arms[0].global_position
	check(reach.dot(fwd) > 0.2, "a raised arm reaches forward, not behind (%.2f)" % reach.dot(fwd))
	c._arm_rot[0] = Vector3.ZERO
	# musicians: both hands reach their instrument (neck, bow, keys, skin, strings)
	var worst := 0.0
	var worst_kind := ""
	for kind in ["fiddle", "whistle", "accordion", "bodhran", "guitar", "banjo"]:
		var mu := Customer.new()
		mu.setup(w, {"gender": "m"}, 77)
		w.add_child(mu)
		mu.global_position = Vector3(0.5, 0, 2.6)
		mu.make_musician(kind, 0.5)
		await _frames(4)
		var pose: Dictionary = mu._rig.pose(mu._anim_t, mu.beat)
		for k in 2:
			var want: Vector3 = mu._body.to_global(pose["l" if k == 0 else "r"])
			var miss: float = mu._hands[k].global_position.distance_to(want)
			if miss > worst:
				worst = miss
				worst_kind = kind
		mu.queue_free()
	check(worst < 0.04, "musicians' hands reach their instruments (worst miss %.3f m, %s)" % [worst, worst_kind])
	# drinking: the pint is carried in front in the hand, and a sip brings the rim to the lips
	var dg := PintGlass.new()
	dg.contents.drink_id = "stout"
	dg.contents.serve = "stout"
	dg.contents.body = 0.88
	dg.contents.foam = 0.1
	c.receive_drink(dg)
	c.state = "stand_drink"
	c._sip_t = 999.0
	await _frames(60)
	var ahead: float = (dg.global_position - c.global_position).dot(fwd)
	check(dg.get_parent() == c._grip and ahead > 0.12, "a held pint is carried in front of them (%.2f m)" % ahead)
	check(dg.global_position.y > c.global_position.y + 0.8 and dg.global_position.y < c.global_position.y + 1.2, "held at waist height (%.2f m)" % (dg.global_position.y - c.global_position.y))
	c._sip_t = 0.0
	await _frames(95)
	var lips: Vector3 = c._head.global_transform * Vector3(0, -0.05, -0.105)
	var rim: Vector3 = dg.global_transform * Vector3(0, dg.height, 0.04)
	check(rim.distance_to(lips) < 0.05, "a sip brings the rim to the lips (%.3f m away)" % rim.distance_to(lips))
	check(dg.global_transform.basis.y.dot(fwd) < -0.2, "the glass tips towards the drinker")
	await _frames(150)
	check(c._sip_phase <= 0.0 and (dg.global_position - c.global_position).dot(fwd) > 0.12, "and back down in front of them afterwards")
	c.leave()
	reg_f.leave()
	# regression: starting a close-up right after leaving another must keep the new view
	GameState.upgrades["dartboard"] = 1
	w.start_darts()
	await _frames(30)
	w.darts.end()
	await _frames(6)
	w.start_split()
	await _frames(60)
	check(get_viewport().get_camera_3d() == w.close_cam, "a close-up started straight after another keeps its camera")
	w.drink_scene.end()
	await _frames(40)
	check(get_viewport().get_camera_3d() == w.player.camera and w.player.input_enabled, "and the view returns to you afterwards")
	# first-person hand appears only while you hold a glass
	var hg := PintGlass.new()
	w.player.take_glass(hg)
	await _frames(2)
	check(w.player.fp_hand.visible, "your hand is shown holding the glass")
	w.player.release_glass()
	hg.queue_free()
	await _frames(2)
	check(not w.player.fp_hand.visible, "and hidden when your hands are empty")
	# graphics presets: old names map onto the new ones and each preset applies
	GameState.settings["graphics"] = "low"
	check(GameState.graphics_preset() == "performance", "older 'low' setting maps to Performance")
	for pr in ["performance", "balanced", "high", "ultra"]:
		GameState.settings["graphics"] = pr
		w.apply_graphics()
		await _frames(2)
	check(get_viewport().msaa_3d == Viewport.MSAA_4X and (w.info["key_light"] as SpotLight3D).shadow_enabled, "Ultra preset turns on 4x MSAA and shadows")
	GameState.settings["graphics"] = "performance"
	w.apply_graphics()
	check(get_viewport().scaling_3d_scale <= 0.75 and not (w.info["key_light"] as SpotLight3D).shadow_enabled and w.max_customers() <= 10, "Performance preset lowers resolution, shadows and crowd size")
	GameState.settings["fps_limit"] = 30
	w.apply_graphics()
	check(Engine.max_fps == 30, "30 FPS mode caps the frame rate")
	GameState.settings["fps_limit"] = 60
	GameState.settings["graphics"] = "balanced"
	w.apply_graphics()
	# the game keeps working with voices switched off
	GameState.settings["voices"] = false
	vd._gap = 0.0
	check(vd.speak(null, "landlord", "last_orders", true) == "", "voices can be switched off")
	GameState.settings["voices"] = true


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

	_log("== Integration: Split the G ==")
	w.player.global_position = Vector3(0.9, 0, -0.9)
	w.player.rotation.y = 0.0
	await _frames(3)
	w.start_split()
	await _frames(45)
	var ds := w.drink_scene
	check(ds.active and main.hud.drink_root.visible, "Split the G starts")
	check(absf(DrinkScene.target_y() - float(GameData.brand["g_center_y"])) < 0.00001 and DrinkScene.target_y() > 0.05, "the target is the measured centre of the G on the glass (%.2f mm up)" % (DrinkScene.target_y() * 1000.0))
	# the printed G must face the camera: the print's G angle, turned by the glass yaw, points at the camera
	var g_ang := float(GameData.brand["g_center_angle"])
	var g_dir := ds.glass.global_transform.basis * Vector3(sin(g_ang), 0, cos(g_ang))
	var to_cam := (w.close_cam.global_position - ds.glass.global_position) * Vector3(1, 0, 1)
	check(g_dir.normalized().dot(to_cam.normalized()) > 0.97, "the glass is turned so the G faces you")
	var body0 := ds.glass.contents.body
	await _frames(30)
	check(is_equal_approx(ds.glass.contents.body, body0), "nothing is drunk until you hold")
	ds.press()
	await _frames(int(2.6 * 60))
	ds.release()
	var after_short := ds.glass.contents.body
	check(after_short < body0 - 0.05, "holding drinks continuously (%.3f -> %.3f)" % [body0, after_short])
	await _wait_until(func(): return ds.state == "reveal", 4.0)
	check(ds.state == "reveal" and not main.hud.drink_retry.visible, "a slow-motion replay plays before the result")
	await _wait_until(func(): return ds.state == "replay", 8.0)
	var err := ds.error_mm()
	var res: Dictionary = ds._result
	check(ds.state == "replay" and res.has("score"), "result shown after the gulp")
	check(is_equal_approx(float(res["error_mm"]), err), "score measures the liquid line against the G (%.1f mm)" % err)
	check(GameState.best_split_mm >= 0.0, "best score recorded")
	# a longer gulp drinks more: skill, not chance
	ds.retry()
	await _frames(40)
	ds.press()
	await _frames(int(3.4 * 60))
	ds.release()
	check(ds.glass.contents.body < after_short, "a longer hold goes further down the glass")
	await _wait_until(func(): return ds.state == "replay", 8.0)
	# a perfect stop scores 100
	ds.glass.contents.body = (DrinkScene.target_y() - PintGlass.BASE) / ds.glass.inner_height
	ds._score()
	check(int(ds._result["score"]) == 100 and str(ds._result["verdict"]) == "Split the G!", "stopping exactly on the line splits the G")
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


# ------------------------------------------------------------------ soundtrack
const EXPECTED_TITLES := ["Welcome to The Local", "First Pint of the Day", "A Quiet Tuesday", "Rain on the Windows",
	"The Friday Crowd", "Last Orders", "Fiddles by the Fire", "The Galway Reel", "The Wild Session",
	"The Old Country Jig", "The Fiddler's Table", "The Big Night", "Split the G", "Perfect Pint",
	"The Pub Gets Bigger", "Champions of the Pub", "One More Round", "Mind the Line",
	"The Pub on the Corner", "The Landlord's Lament"]


func _test_music_data() -> void:
	var md := MusicDirector
	check(md.track_list.size() == 20, "20 soundtrack entries")
	var all_ok := true
	var len_ok := true
	for i in 20:
		var t: Dictionary = md.track_list[i]
		if int(t["number"]) != i + 1 or str(t["title"]) != EXPECTED_TITLES[i]:
			all_ok = false
			_log("    wrong entry %d: %s" % [i + 1, t.get("title")])
		var s: AudioStream = load(t["file"])
		if not (s is AudioStreamMP3):
			all_ok = false
			_log("    %s did not import as MP3" % t["file"])
		elif absf(s.get_length() - float(t["duration"])) > 1.5:
			len_ok = false
			_log("    %s length %.1f vs %.1f" % [t["file"], s.get_length(), float(t["duration"])])
	check(all_ok, "all 20 tracks numbered and titled correctly and import as MP3 streams")
	check(len_ok, "every track's imported length matches the original recording")
	var cats := {}
	for t in md.track_list:
		cats[t["category"]] = int(cats.get(t["category"], 0)) + 1
	check(cats.get("atmosphere") == 6 and cats.get("live") == 6 and cats.get("challenge") == 4 and cats.get("vocal") == 4, "tracks grouped into the four categories")
	# every live and vocal performance track is used by a bookable act or the finale
	var used := {"t17": true}
	for ev in GameData.events:
		used[ev["track"]] = true
	var missing := []
	for id in ["t07", "t08", "t09", "t10", "t11", "t12", "t18", "t20", "t17"]:
		if not used.has(id):
			missing.append(id)
	check(missing.is_empty(), "every live/vocal performance track has a job %s" % str(missing))
	# selection rules
	var ctx: Dictionary = md.context
	var saved := ctx.duplicate()
	md.mode = "auto"
	ctx["screen"] = "menu"
	check(md._pick_for(md.current_situation()) == "t01", "menu plays Welcome to The Local")
	ctx["screen"] = "world"
	ctx["live"] = false
	ctx["phase"] = "prep"
	ctx["hour"] = 15.5
	ctx["customers"] = 0
	ctx["weather"] = "clear"
	var pool: Dictionary = md.pub_pool()
	check(_top(pool) == "t02", "opening up plays First Pint of the Day")
	ctx["phase"] = "open"
	ctx["hour"] = 18.5
	ctx["customers"] = 3
	ctx["capacity_frac"] = 0.2
	ctx["weekday"] = 1
	check(_top(md.pub_pool()) == "t03", "quiet trading plays A Quiet Tuesday")
	ctx["weather"] = "rain"
	ctx["hour"] = 20.0
	check(_top(md.pub_pool()) == "t04", "a rainy evening favours Rain on the Windows")
	ctx["weather"] = "clear"
	ctx["customers"] = 10
	ctx["capacity_frac"] = 0.7
	check(_top(md.pub_pool()) == "t05", "a busy bar plays The Friday Crowd")
	ctx["phase"] = "last_orders"
	check(md._pick_for(md.current_situation()) == "t06", "last orders plays Last Orders")
	ctx["screen"] = "summary"
	ctx["milestone"] = true
	check(md._pick_for(md.current_situation()) == "t19", "milestone nights end with The Pub on the Corner")
	ctx["milestone"] = false
	ctx["screen"] = "world"
	ctx["phase"] = "open"
	ctx["live"] = true
	check(md.current_situation() == "live" and md._pick_for("live") == "", "background music steps aside for live musicians")
	ctx["live"] = false
	md.start_override("t13", "minigame")
	check(md._pick_for(md.current_situation()) == "t13", "the Split challenge plays Split the G")
	md.clear_override()
	for k in saved.keys():
		ctx[k] = saved[k]


func _top(pool: Dictionary) -> String:
	var best := ""
	var bw := -1.0
	for k in pool.keys():
		if float(pool[k]) > bw:
			bw = float(pool[k])
			best = k
	return best


func _test_music(w: World) -> void:
	_log("== Integration: soundtrack in the pub ==")
	var md := MusicDirector
	md.set_mode("auto")
	GameState.phase = "open"
	GameState.hour = 17.0
	await _frames(int(4.5 * 60))
	check(md.current_id in ["t02", "t03", "t04", "t05"], "pub background music playing (%s)" % md.title_of(md.current_id))
	check(md._players[md._active].playing, "the background track is actually playing")
	check(md.audible_players() <= 1, "never two full-volume songs at once")
	# let the song end naturally: the next one is chosen and crossfaded in
	var first := md.current_id
	var p: AudioStreamPlayer = md._players[md._active]
	p.seek(p.stream.get_length() - 2.0)
	await _frames(int(1.0 * 60))
	check(md.current_id != "" and (md.current_id != first or md._players[md._active] != p), "a finished song hands over to the next")
	await _frames(int(3.5 * 60))
	check(md.audible_players() <= 1, "crossfade completes with a single song")
	# last orders
	GameState.hour = 23.6
	await _frames(int(6.0 * 60))
	check(md.current_id == "t06", "Last Orders plays at closing time")
	GameState.phase = "open"
	GameState.hour = 19.0
	# Split the G during the challenge, then back to pub music
	w.start_split()
	await _frames(int(3.5 * 60))
	check(md.current_id == "t13", "Split the G plays during the challenge")
	w.drink_scene.end()
	await _frames(int(4.0 * 60))
	check(md.current_id != "t13" and md.override_id() == "", "music returns to the pub after the challenge (%s)" % md.title_of(md.current_id))
	# perfect pint excerpt
	md._stinger_cooldown = 0.0
	check(md.play_stinger("t14"), "Perfect Pint excerpt plays")
	check(md._stinger.playing and absf(md._stinger.get_playback_position() - 17.5) < 1.0, "the excerpt starts at the celebratory section")
	check(not md.play_stinger("t14"), "the excerpt can't spam on every pint")
	await _frames(int(10.0 * 60))
	check(not md._stinger.playing, "the excerpt stops after a few seconds rather than playing the whole song")
	# jukebox: every track plays
	var played := 0
	for t in md.track_list:
		md.play_track(t["id"])
		await _frames(20)
		var ap: AudioStreamPlayer = md._players[md._active]
		if md.current_id == t["id"] and ap.playing and ap.stream == md.stream(t["id"]):
			played += 1
	check(played == 20, "the jukebox plays all 20 songs (%d)" % played)
	await _frames(int(3.5 * 60))
	check(md.audible_players() <= 1, "switching tracks rapidly still leaves one song audible")
	md.toggle_pause()
	check(md._players[md._active].stream_paused, "pause works")
	md.toggle_pause()
	check(not md._players[md._active].stream_paused, "resume works")
	md.set_playlist("live")
	md.play_track("t07")
	md.skip()
	check(md.current_id == "t08", "skip moves to the next song in the chosen category")
	md.set_playlist("all")
	GameState.set_setting("vol_music", 0.3)
	var bus := AudioServer.get_bus_index("Music")
	check(absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.3)) < 0.01, "music volume slider changes the music bus only")
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")) - linear_to_db(float(GameState.settings["vol_effects"]))) < 0.01, "effects volume is independent")
	GameState.set_setting("vol_music", 0.0)
	check(AudioServer.is_bus_mute(bus), "music can be turned off without muting effects")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")), "effects still on with music off")
	GameState.set_setting("vol_music", 0.8)
	var saved_settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SETTINGS_PATH))
	check(saved_settings.get("music_mode") == "manual" and float(saved_settings.get("vol_music")) == 0.8, "audio preferences are saved")
	# the mix: rain sits on its own muffled bus under the room, and voices push everything else back
	var wb := AudioServer.get_bus_index("Weather")
	check(wb >= 0 and AudioServer.get_bus_send(wb) == "Ambience", "weather has its own bus feeding the room")
	check(AudioServer.get_bus_effect_count(wb) > 0 and AudioServer.get_bus_effect(wb, 0) is AudioEffectLowPassFilter, "rain is muffled as if heard through the windows")
	check(float(GameState.settings["vol_speech"]) > float(GameState.settings["vol_weather"]), "voices are set louder than the weather by default")
	Sfx.set_loop("rain", "rain_loop", 0.5, "Weather")
	check(Sfx._loops.has("rain") and Sfx._loops["rain"].bus == "Weather", "rain plays on the weather bus")
	var amb := AudioServer.get_bus_index("Ambience")
	var amb0 := AudioServer.get_bus_volume_db(amb)
	var w0 := AudioServer.get_bus_volume_db(wb)
	Sfx.duck_for_speech(1.0)
	for i in 30:
		await get_tree().process_frame
	check(AudioServer.get_bus_volume_db(amb) < amb0 - 4.0 and AudioServer.get_bus_volume_db(wb) < w0 - 4.0, "the room and rain dip while someone speaks")
	for i in 150:
		await get_tree().process_frame
	check(absf(AudioServer.get_bus_volume_db(amb) - amb0) < 0.1, "and come back up afterwards")
	Sfx.set_loop("rain", "rain_loop", 0.0, "Weather")
	md.set_mode("auto")
	# live musicians
	_log("== Integration: live music ==")
	GameState.cash = 1000.0
	GameState.hour = 19.0
	var live := w.live
	check(live.can_book(GameState.day, "galway_reel") != "", "stage acts need the snug stage")
	check(LiveMusic.effectiveness(GameData.events_by_id["galway_reel"], 5) == 1.0 and LiveMusic.effectiveness(GameData.events_by_id["galway_reel"], 1) < 1.0, "weekend acts work best at the weekend")
	check(live.book(GameState.day, "fiddles_fire"), "book Fiddles by the Fire for tonight")
	var cash_after := GameState.cash
	check(is_equal_approx(cash_after, 1000.0 - 35.0), "booking fee charged")
	var base_rate := w.arrival_rate_per_hour()
	GameState.hour = 20.05
	await _frames(10)
	check(live.playing and live.musicians.size() == 1, "the fiddler arrives and starts playing")
	check(w.arrival_rate_per_hour() > base_rate * 1.1, "live music draws more customers (%.1f -> %.1f per hour)" % [base_rate, w.arrival_rate_per_hour()])
	check(GameState.live_atmosphere > 0.0 and w.drink_speed_mult() < 1.0, "live music lifts atmosphere and customers linger")
	# the fiddler may say a few words before the first tune
	await _wait_until(func(): return live.player3d.playing, 8.0)
	check(live.player3d.playing and live.now_playing == "t07", "Fiddles by the Fire plays from the musician")
	check(live.player3d.global_position.distance_to(LiveMusic.FIRESIDE_SPOT + Vector3(0, 1.3, 0)) < 0.1, "music comes from the fireside where the fiddler sits")
	await _frames(int(4.5 * 60))
	check(md.situation == "live" and md.audible_players() == 0, "background music fades out while the band plays (no second copy)")
	w.player.global_position = Vector3(-5.0, 0, -7.0)
	await _frames(3)
	check(live.player3d.attenuation_filter_cutoff_hz < 2000.0, "the band sounds muffled from the cellar")
	w.player.global_position = Vector3(-3.0, 0, 1.0)
	await _frames(3)
	check(live.player3d.attenuation_filter_cutoff_hz > 10000.0, "and clear back in the bar")
	# the end of a tune: applause, next tune
	live.player3d.seek(live.player3d.stream.get_length() - 0.5)
	await _wait_real(func(): return live.now_playing != "" and live.now_playing != "t07", 10.0)
	check(live.now_playing != "" and live.now_playing != "t07", "after applause the band plays another tune (%s)" % md.title_of(live.now_playing))
	# a brilliant night earns One More Round
	GameState.upgrades["fireplace"] = 1
	GameState.upgrades["lamps"] = 1
	GameState.upgrades["paint"] = 1
	GameState.today["served"] = 5
	GameState.today["satisfaction_sum"] = 400.0
	for i in 6:
		w.spawn_customer()
	await _frames(5)
	check(live.finale_due(), "a full, happy pub calls for the singalong")
	var rep0 := GameState.reputation
	live.player3d.seek(live.player3d.stream.get_length() - 0.5)
	await _wait_real(func(): return live.now_playing == "t17", 10.0)
	check(live.now_playing == "t17", "One More Round is sung")
	live._on_song_finished()
	check(GameState.reputation > rep0 and bool(GameState.today.get("singalong", false)), "the singalong lifts reputation")
	# the event ends after its last song
	GameState.hour = 23.05
	await _frames(5)
	live.player3d.seek(live.player3d.stream.get_length() - 0.5)
	await _wait_real(func(): return not live.playing, 10.0)
	check(not live.playing and live.musicians.is_empty(), "the musicians finish their song and take a bow")
	GameState.hour = 21.0
	await _frames(int(4.0 * 60))
	check(md.situation != "live" and md.current_id != "", "background music returns after the band (%s / %s / live %s / phase %s)" % [md.title_of(md.current_id), md.situation, str(md.context["live"]), GameState.phase])
	check(live.cancel(GameState.day) == false, "can't cancel an act that already played")
	check(live.book(GameState.day + 2, "fiddlers_table") and live.cancel(GameState.day + 2), "future bookings can be cancelled")
	# renovations and awards get their own music
	GameState.cash = 2000.0
	GameState.buy_upgrade("snug_stage")
	await _frames(10)
	check(md.current_id == "t15" and main.hud.celebration.visible, "a major renovation plays The Pub Gets Bigger")
	main.hud.dismiss_celebration()
	await _frames(int(4.0 * 60))
	check(md.current_id != "t15", "dismissing the celebration returns to the pub's music")
	GameState.objectives_done.erase("best_on_street")
	GameState.reputation = 36.0
	w._check_awards()
	await _frames(10)
	check("best_on_street" in GameState.objectives_done and md.current_id == "t16", "awards play Champions of the Pub")
	check(md._players[md._active].get_playback_position() > 14.0, "the award music starts at its big moment")
	main.hud.dismiss_celebration()
	await _frames(int(4.0 * 60))
	check(live.can_book(GameState.day + 1, "galway_reel") == "", "the stage unlocks weekend sessions")
	# saves from before the soundtrack still load
	var old := GameState.to_dict()
	old.erase("bookings")
	old["today"].erase("live_event")
	GameState.from_dict(old)
	check(GameState.bookings.is_empty() and GameState.today.has("live_event"), "older saves without music data load with defaults")


# ------------------------------------------------------------------ queue balance playtests
## A simulated solo bartender: takes each order a few seconds after the customer reaches the bar
## and hands over a well-poured pint `service` seconds later, one order at a time.
func _bot_session(seconds: float, service: float, difficulty := "balanced", day := 1, rep := 20.0) -> Dictionary:
	main.quit_to_title()
	await _frames(3)
	GameState.set_setting("difficulty", difficulty)
	main.start_new("career", "Playtest")
	await _frames(10)
	GameState.day = day
	GameState.reputation = rep
	GameState.tutorial["done"] = true
	var w: World = main.world
	w.dispatcher = OrderDispatcher.new()
	w._sign_action()
	var t := 0.0
	var busy_until := -1.0
	var current: Customer = null
	var busy_time := 0.0
	var served := 0
	var max_active := 0
	var max_people := 0
	var waits: Array = []
	var arrived_at := {}
	var dt := 1.0 / 60.0
	while t < seconds:
		await get_tree().process_frame
		t += dt
		if GameState.hour >= 23.4:
			GameState.hour = 19.0  # keep trading so the session covers the full span
		var a := w.active_orders()
		max_active = maxi(max_active, a)
		max_people = maxi(max_people, w.customers.size())
		for c in w.customers:
			if c.state == "wait_order" and not arrived_at.has(c):
				arrived_at[c] = t
		if current != null and (not is_instance_valid(current) or current.state != "wait_drink"):
			current = null
			busy_until = -1.0
		if current == null:
			# next customer in line: the one who has waited longest
			var best: Customer = null
			for c in w.customers:
				if c.state == "wait_order" and float(arrived_at.get(c, t)) <= t - 2.0:
					if best == null or float(arrived_at[c]) < float(arrived_at[best]):
						best = c
			if best != null:
				w._customer_action(best)
				current = best
				busy_until = t + service
		else:
			busy_time += dt
			if t >= busy_until:
				var g := PintGlass.new()
				var con := g.contents
				con.drink_id = current.drink_id
				con.serve = str(GameData.drink(current.drink_id).get("serve", "stout"))
				if con.serve == "stout":
					con.stage = 3
					con.first_pour_level = 0.75
					con.angle_sum = 45.0
					con.angle_vol = 1.0
					con.topup_cascade = 0.05
					con.body = 0.88
					con.foam = 0.13
				else:
					con.body = 0.9
					con.foam = 0.09
				w.add_child(g)
				w.rack_clean = maxi(0, w.rack_clean - 1)
				var res: Dictionary = w.serve_customer(current, g)
				if res.get("ok", false):
					served += 1
					waits.append(t - float(arrived_at.get(current, t)))
					arrived_at.erase(current)
				current = null
				# wash whatever is lying around between customers
				for lg in w.loose_glasses.duplicate():
					w.loose_glasses.erase(lg)
					lg.queue_free()
					w.rack_clean += 1
	var avg_wait := 0.0
	for x in waits:
		avg_wait += float(x)
	avg_wait /= maxf(1.0, waits.size())
	var res2 := {"served": served, "max_active": max_active, "walkouts": int(GameState.today["walkouts"]) + int(GameState.stats.get("walkouts_hist", 0)),
		"utilisation": busy_time / seconds, "avg_wait": avg_wait, "max_wait": waits.max() if not waits.is_empty() else 0.0, "max_people": max_people,
		"intervals": _diffs(w.dispatcher.released_times), "caps": w.dispatcher.caps(), "interval": w.dispatcher.order_interval(),
		"service_ema": OrderDispatcher.service_time()}
	return res2


func _diffs(arr: Array) -> Array:
	var out := []
	for i in range(1, arr.size()):
		out.append(snappedf(float(arr[i]) - float(arr[i - 1]), 0.1))
	return out


func _test_queue_balance() -> void:
	_log("== Playtest: queue balance (simulated solo bartender) ==")
	GameState.stats["service_time_ema"] = OrderDispatcher.DEFAULT_SERVICE
	var r := await _bot_session(900.0, 55.0)
	_log("    balanced, day 1, 55 s per pint, 15 min: served %d, max orders waiting %d (caps %s), walk-outs %d, busy %d%%, wait at bar avg %.0f s / max %.0f s, peak people %d" % [r["served"], r["max_active"], str(r["caps"]), r["walkouts"], int(r["utilisation"] * 100), r["avg_wait"], r["max_wait"], r["max_people"]])
	_log("    order release gaps (s): %s" % str(r["intervals"]))
	check(r["max_active"] <= 3, "first-day queue never exceeds 3 orders")
	check(r["walkouts"] == 0, "nobody walks out on a careful solo bartender")
	check(r["utilisation"] >= 0.35 and r["utilisation"] <= 0.75, "bartender is busy but not swamped (%d%%)" % int(r["utilisation"] * 100))
	check(int(r["served"]) >= 8, "steady trade: %d pints in 15 minutes" % r["served"])
	var min_gap := 999.0
	for g in r["intervals"]:
		min_gap = minf(min_gap, float(g))
	check(min_gap >= 25.0, "no burst catch-up: orders are spaced at least 25 s apart (min %.0f s)" % min_gap)
	# a slower player: the dispatcher learns their pace
	GameState.stats["service_time_ema"] = OrderDispatcher.DEFAULT_SERVICE
	var slow := await _bot_session(900.0, 95.0)
	_log("    balanced, day 1, 95 s per pint: served %d, max waiting %d, walk-outs %d, busy %d%%, learned service %.0f s, interval %.0f s" % [slow["served"], slow["max_active"], slow["walkouts"], int(slow["utilisation"] * 100), slow["service_ema"], slow["interval"]])
	check(slow["max_active"] <= 3 and slow["walkouts"] == 0, "a slow, careful player is never overwhelmed")
	check(float(slow["service_ema"]) > 80.0, "the game measures the player's real serving time")
	# later on, with reputation and the Busier setting, it gets genuinely busy
	GameState.stats["service_time_ema"] = 45.0
	var late := await _bot_session(600.0, 45.0, "busier", 9, 60.0)
	_log("    busier, day 9, rep 60, 45 s per pint: served %d, max waiting %d (caps %s), busy %d%%, walk-outs %d" % [late["served"], late["max_active"], str(late["caps"]), int(late["utilisation"] * 100), late["walkouts"]])
	check(int(late["caps"][1]) > 3 and float(late["utilisation"]) > float(r["utilisation"]), "demand grows with progression and the Busier setting")
	GameState.set_setting("difficulty", "balanced")


# ------------------------------------------------------------------ staff
func _test_staff() -> void:
	_log("== Integration: hired staff ==")
	main.quit_to_title()
	await _frames(3)
	GameState.set_setting("difficulty", "balanced")
	main.start_new("career", "Staff test")
	await _frames(10)
	GameState.tutorial["done"] = true
	var w: World = main.world
	check(GameData.staff_pool.size() >= 4, "there are people looking for work (%d)" % GameData.staff_pool.size())
	check(GameState.hire_block("roisin").begins_with("Needs reputation"), "the best staff want a pub with a name first")
	GameState.cash = 500.0
	check(GameState.hire("ciaran") and GameState.hire("seanie"), "hire a bartender and a glass collector")
	check(not GameState.hire("ciaran"), "can't hire the same person twice")
	GameState.reputation = 60.0
	check(GameState.hire("roisin"), "a second bartender once the pub has a name")
	check(GameState.hire_block("brendan").begins_with("No room"), "no room for a third bartender")
	GameState.fire("roisin")
	await _frames(2)
	check(w.staff_npcs.size() == 2, "the hired staff come in to work (%d)" % w.staff_npcs.size())
	var bar: StaffMember = null
	var floor_st: StaffMember = null
	for st in w.staff_npcs:
		if st.role == "bartender":
			bar = st
		else:
			floor_st = st
	check(bar != null and floor_st != null and bar.model == "m_young_b", "staff are realistic people in their own faces")
	check(OrderDispatcher.servers() > 1.4, "a bartender lets the pub take more orders")
	# a mid-day hire walks in, so wait for everyone to reach their posts
	await _wait_until(func(): return bar.state == "st_idle" and floor_st.state == "st_idle", 30.0)
	var total := GameState.glasses_total()
	# the player stands by the fire and leaves the bar to the staff
	w.player.global_position = Vector3(-5.5, 0, 1.5)
	var staff_results: Array = []
	w.served.connect(func(r): if str(r.get("by", "")) != "": staff_results.append(r))
	w._sign_action()
	var hinted := false
	var count_ok := true
	var picked_up_at := -1
	var t := 0.0
	while t < 260.0 and staff_results.size() < 3:
		await get_tree().process_frame
		t += 1.0 / 60.0
		if int(t * 60.0) % 30 == 0 and w.glass_count_check() != total:
			count_ok = false
		for c in w.customers:
			if w.staff_serving(c) != null and c.state in ["wait_order", "wait_drink"]:
				hinted = hinted or w._customer_prompt(c).begins_with("~")
	check(staff_results.size() >= 3, "the bartender takes orders, pours and serves on their own (%d served in %ds)" % [staff_results.size(), int(t)])
	check(hinted, "customers a bartender is seeing to aren't offered to the player")
	check(count_ok and w.glass_count_check() == total, "no glasses lost or made while staff work")
	var avg := 0.0
	for r in staff_results:
		avg += float(r.get("score", 0)) / maxf(1.0, staff_results.size())
	check(avg >= 60.0, "a novice bartender's pints are drinkable (avg %d)" % int(avg))
	# empties: leave one on a table and the collector clears it to the sink
	var washed0 := int(GameState.stats["glasses_washed"])
	var g := PintGlass.new()
	g.set_dirty(0.6)
	w.rack_clean -= 1
	var seat0: Dictionary = w.seat_info(0)
	w.leave_dirty_glass(g, seat0["table"])
	w.add_spill(Vector3(1.5, 0, 0.5))
	var ok := await _wait_until(func(): return not w.loose_glasses.has(g), 60.0)
	check(ok, "the glass collector picks up empties")
	ok = await _wait_until(func(): return int(GameState.stats["glasses_washed"]) > washed0, 60.0)
	check(ok, "and washes them back onto the rack")
	ok = await _wait_until(func(): return w.spills.is_empty(), 60.0)
	check(ok, "and wipes up spills")
	check(w.glass_count_check() == total, "glass count still right after collecting")
	# letting someone go
	GameState.fire("seanie")
	await _frames(2)
	check(w.staff_npcs.size() == 1 and not GameState.is_hired("seanie"), "let go staff head home")
	check(w.glass_count_check() == total, "whatever they carried is left by the sink")
	# wages at close, and saving
	var wage := GameState.wages_today()
	check(is_equal_approx(wage, 14.0), "wages add up (€%.0f)" % wage)
	GameState.save_game()
	GameState._reset()
	GameState.load_game()
	check(GameState.is_hired("ciaran") and GameState.staff.size() == 1, "staff are kept in the save")


# ------------------------------------------------------------------ guidance, goals, streaks
func _stout_for(w: World, c: Customer) -> PintGlass:
	var g := PintGlass.new()
	var con := g.contents
	con.drink_id = c.drink_id
	con.serve = str(GameData.drink(c.drink_id).get("serve", "stout"))
	if con.serve == "stout":
		con.stage = 3
		con.first_pour_level = 0.75
		con.angle_sum = 45.0
		con.angle_vol = 1.0
		con.topup_cascade = 0.05
		con.body = 0.88
		con.foam = 0.13
	else:
		con.body = 0.9
		con.foam = 0.09
	w.add_child(g)
	w.rack_clean -= 1
	return g


func _test_flow() -> void:
	_log("== Integration: what to do next, daily goals and streaks ==")
	main.quit_to_title()
	await _frames(3)
	GameState.delete_save()
	main.start_new("career", "Flow test")
	await _frames(3)
	GameState.tutorial["dirty_overnight"] = 3
	main.start_world()
	await _frames(10)
	var w: World = main.world
	check(w.loose_glasses.size() == 3 and w.tutorial_step <= 1, "last night's glasses don't skip the tutorial ahead (step %d)" % w.tutorial_step)
	var step := w.next_step()
	check(str(step["text"]).contains("sign") and step.has("pos"), "before opening, the guide points at the door sign")
	var goals := GameState.daily_goals()
	check(goals.size() == 3 and goals[0]["id"] == "serve", "three goals for the day, starting with a serving target")
	check(GameState.daily_goals() == goals, "the day's goals stay the same once set")
	await _frames(40)
	check(main.hud.next_pill.visible and main.hud.next_label.text != "" and main.hud.goals_box.get_child_count() == 4, "the HUD shows the next step and today's goals")
	check(main.hud.goal_chip.text.begins_with("Goals 0/3"), "goals fold into a small chip")
	w.player.global_position = Vector3(-5.5, 0, 1.5)
	await _frames(30)
	check(w.guide_marker.visible, "a gold marker floats over what to do next")
	w.player.global_position = PubLayout.PLAYER_START
	w._sign_action()
	var ok := await _wait_until(func(): return w.customers.any(func(x): return x.state == "wait_order"), 40.0)
	var c: Customer = null
	for x in w.customers:
		if x.state == "wait_order":
			c = x
	check(ok and str(w.next_step()["text"]).begins_with("Take %s" % c.display_name), "a customer at the bar: take their order")
	w._customer_action(c)
	check(str(w.next_step()["text"]).begins_with("Grab a clean glass"), "order taken: grab a glass")
	w._rack_action()
	check(str(w.next_step()["text"]).begins_with("Pour"), "glass in hand: pour at the tap")
	w.player.release_glass().queue_free()
	w.rack_clean += 1
	# a good pint starts a streak, and the serving goal pays out when it's reached
	var g0: Dictionary = goals[0]
	GameState.today["served"] = int(g0["target"]) - 1
	var cash0 := GameState.cash
	c.tip_mult = 1.0
	c.patience = c.patience_max
	var res := w.serve_customer(c, _stout_for(w, c))
	check(res.get("ok", false) and w.streak == 1 and int(res["streak"]) == 1, "a good pint starts a streak")
	GameState.check_goals()
	check(g0["done"] and GameState.cash > cash0 + float(res["price"]) + float(g0["reward"]) - 0.01, "reaching a goal pays its reward (€%d)" % int(g0["reward"]))
	w.streak = 4
	var c2 := w.spawn_customer()
	c2.drink_id = "stout"
	c2.state = "wait_drink"
	c2.tip_mult = 1.0      # same customer generosity and wait, so only the streak differs
	c2.patience = c2.patience_max
	var res2 := w.serve_customer(c2, _stout_for(w, c2))
	check(w.streak == 5 and int(GameState.today.get("best_streak", 0)) >= 5, "the streak keeps count (%d)" % w.streak)
	check(float(res2.get("tip", 0.0)) > float(res.get("tip", 0.0)), "a longer streak means bigger tips (€%.2f vs €%.2f)" % [float(res2.get("tip", 0.0)), float(res.get("tip", 0.0))])
	# the end-of-day summary reports the goals and looks ahead
	GameState.hour = 24.9
	GameState.phase = "closing"
	for cc in w.customers.duplicate():
		cc.leave()
	await _wait_until(func(): return w.customers.is_empty(), 60.0)
	check(str(w.next_step()["text"]).contains("cash up"), "everyone gone: the guide says to cash up")
	w.close_day()
	await _frames(3)
	var texts := []
	for n in main.hud.menu.content.find_children("*", "Label", true, false):
		texts.append((n as Label).text)
	var all := "\n".join(texts)
	check(all.contains("Today's goals") and all.contains("Done"), "the day's summary lists the goals met")
	check(all.contains("Looking ahead"), "and what to aim for tomorrow")
