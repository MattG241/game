extends Node
## Plays whole trading days (16:00 to midnight) with a bot barman at a fixed pace, under different
## staffing, and reports how busy the player is and what the day earns. Used to balance staff:
##   godot --headless --path . --fixed-fps 60 res://tests/balance_probe.tscn
## SERVICE (seconds per order, default 45) and DAYS (default all configs) can be set in the env.

var main: Node
const CONFIGS := [
	["solo, early (rep 25, day 3)", [], 25.0, 3],
	["solo, established (rep 45, day 8)", [], 45.0, 8],
	["+ novice bartender (rep 45, day 8)", ["ciaran"], 45.0, 8],
	["+ novice + collector (rep 45, day 8)", ["ciaran", "seanie"], 45.0, 8],
	["+ 2 bartenders + collector (rep 65, day 14)", ["roisin", "brendan", "mags"], 65.0, 14],
	["slow player 90s + novice (rep 45, day 8)", ["ciaran"], 45.0, 8, 90.0],
]


func _ready() -> void:
	await get_tree().process_frame
	var service := float(OS.get_environment("SERVICE")) if OS.get_environment("SERVICE") != "" else 45.0
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await _frames(5)
	print("BALANCE  service %.0fs per order, one full trading day each" % service)
	print("BALANCE  %-44s %6s %6s %6s %6s %7s %7s %7s %7s" % ["config", "you", "staff", "walk", "busy%", "sales", "wages", "fee", "profit"])
	for cfg in CONFIGS:
		var r: Dictionary = await _day(cfg[1], cfg[2], cfg[3], float(cfg[4]) if cfg.size() > 4 else service)
		print("BALANCE  %-44s %6d %6d %6d %5d%% %7.0f %7.0f %7.0f %7.0f" % [cfg[0], r["you"], r["staff"], r["walk"], int(r["busy"] * 100.0), r["sales"], r["wages"], r["fee"], r["profit"]])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _day(hires: Array, rep: float, day: int, service: float) -> Dictionary:
	if main.world:
		main.quit_to_title()
		await _frames(3)
	GameState.delete_save()
	main.start_new("career", "Balance")
	await _frames(10)
	GameState.tutorial["done"] = true
	GameState.day = day
	GameState.reputation = rep
	GameState.cash = 5000.0
	for u in ["lager_tap", "glasses_6", "glasses_12"]:
		GameState.upgrades[u] = 1
	for id in GameState.tap_units.keys():
		GameState.tap_units[id] = 500.0
	var fee := 0.0
	for h in hires:
		var c0 := GameState.cash
		GameState.hire(h)
		fee += c0 - GameState.cash
	GameState.upgrades_changed.emit()
	var w: World = main.world
	await _frames(10)
	w.rack_clean = GameState.glasses_total()
	w._sign_action()
	GameState.hour = 16.0
	var dt := 1.0 / 60.0
	var current: Customer = null
	var busy_until := 0.0
	var t := 0.0
	var busy := 0.0
	var you := 0
	var staff_n := [0]      # lambdas capture locals by value, so count in an array
	w.served.connect(func(r): if str(r.get("by", "")) != "": staff_n[0] += 1)
	var open_time := 0.0
	while GameState.phase in ["open", "last_orders"] and t < 3600.0:
		await get_tree().process_frame
		t += dt
		open_time += dt
		if current != null and (not is_instance_valid(current) or current.state != "wait_drink"):
			current = null
		if current == null:
			for c in w.customers:
				if c.state == "wait_order" and w.staff_serving(c) == null:
					w._customer_action(c)
					current = c
					busy_until = t + service
					break
		else:
			busy += dt
			if t >= busy_until:
				var g := PintGlass.new()
				g.contents.drink_id = current.drink_id
				g.contents.serve = str(GameData.drink(current.drink_id).get("serve", "stout"))
				if g.contents.serve == "stout":
					g.contents.stage = 3
					g.contents.first_pour_level = 0.75
					g.contents.angle_sum = 45.0
					g.contents.angle_vol = 1.0
					g.contents.topup_cascade = 0.05
					g.contents.body = 0.88
					g.contents.foam = 0.13
				else:
					g.contents.body = 0.9
					g.contents.foam = 0.09
				w.add_child(g)
				w.rack_clean = maxi(0, w.rack_clean - 1)
				if w.serve_customer(current, g).get("ok", false):
					you += 1
				current = null
		# the bot keeps the glasses moving when nobody's collecting
		if GameState.staff_count("collector") == 0 and int(t * 60.0) % 600 == 0:
			for lg in w.loose_glasses.duplicate():
				w.loose_glasses.erase(lg)
				lg.queue_free()
				w.rack_clean += 1
	var sales := float(GameState.today["sales"]) + float(GameState.today["tips"])
	var wages := GameState.wages_today()
	var cogs := float(GameState.today["cogs"])
	var profit := sales - cogs - wages - 38.0
	return {"you": you, "staff": staff_n[0], "walk": int(GameState.today["walkouts"]), "busy": busy / maxf(1.0, open_time),
		"sales": sales, "wages": wages, "fee": fee, "profit": profit}
